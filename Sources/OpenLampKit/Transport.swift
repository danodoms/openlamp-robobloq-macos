import Foundation
import IOKit.hid

/// Collects input reports from the device. Reports arrive on the HID run loop
/// thread; device-info requests wait from the serial device queue.
final class ReportInbox {
    private let condition = NSCondition()
    private var reports: [[UInt8]] = []

    func push(_ report: [UInt8]) {
        condition.lock()
        reports.append(report)
        if reports.count > 16 { reports.removeFirst() }
        condition.broadcast()
        condition.unlock()
    }

    func clear() {
        condition.lock()
        reports.removeAll()
        condition.unlock()
    }

    func wait(forPacket index: UInt8, timeout: TimeInterval) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let position = reports.firstIndex(where: { $0.count > 3 && $0[3] == index }) {
                return reports.remove(at: position)
            }
            if !condition.wait(until: deadline) { return nil }
        }
    }
}

/// One opened HID interface on the strip. Writes are 64-byte reports with
/// report ID zero; input reports are copied into the inbox.
public final class HIDDevice {
    let device: IOHIDDevice
    let inbox = ReportInbox()
    private let buffer: UnsafeMutablePointer<UInt8>
    private var closed = false

    init(device: IOHIDDevice) {
        self.device = device
        self.buffer = .allocate(capacity: Robobloq.reportLength)
        self.buffer.initialize(repeating: 0, count: Robobloq.reportLength)

        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            Robobloq.reportLength,
            { context, _, _, type, _, report, length in
                guard type == kIOHIDReportTypeInput, let context else { return }
                let device = Unmanaged<HIDDevice>.fromOpaque(context).takeUnretainedValue()
                device.inbox.push(Array(UnsafeBufferPointer(start: report, count: length)))
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    @discardableResult
    func write(_ packet: [UInt8]) -> Bool {
        guard packet.count == Robobloq.reportLength, !closed else { return false }
        let result = packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                0,
                $0.baseAddress!,
                Robobloq.reportLength
            )
        }
        return result == kIOReturnSuccess
    }

    public func close() {
        guard !closed else { return }
        closed = true
        IOHIDDeviceRegisterInputReportCallback(device, buffer, Robobloq.reportLength, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deinitialize(count: Robobloq.reportLength)
        buffer.deallocate()
    }

    deinit {
        close()
    }
}

public final class HIDTransport {
    public var onAttach: ((HIDDevice) -> Void)?
    public var onDetach: ((HIDDevice) -> Void)?
    public var onError: ((String) -> Void)?

    private let manager: IOHIDManager
    private let callbacks = DispatchQueue(label: "OpenLamp.Transport.Callbacks")
    private let lock = NSLock()
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var device: HIDDevice?
    private var started = false

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    public func start() {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else { return }

            let matching: [String: Any] = [
                kIOHIDVendorIDKey: NSNumber(value: Robobloq.vendorID),
                kIOHIDProductIDKey: NSNumber(value: Robobloq.productID),
                kIOHIDDeviceUsagePageKey: NSNumber(value: Robobloq.usagePage),
                kIOHIDDeviceUsageKey: NSNumber(value: Robobloq.usage),
            ]
            IOHIDManagerSetDeviceMatching(self.manager, matching as CFDictionary)
            IOHIDManagerRegisterDeviceMatchingCallback(
                self.manager,
                deviceAddedCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )
            IOHIDManagerRegisterDeviceRemovalCallback(
                self.manager,
                deviceRemovedCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )

            let loop = CFRunLoopGetCurrent()!
            self.lock.lock()
            self.runLoop = loop
            self.lock.unlock()

            IOHIDManagerScheduleWithRunLoop(self.manager, loop, CFRunLoopMode.defaultMode.rawValue)
            let result = IOHIDManagerOpen(self.manager, IOOptionBits(kIOHIDOptionsTypeNone))
            if result != kIOReturnSuccess {
                self.report("Could not open the HID manager (0x\(String(result, radix: 16))).")
            }

            ready.signal()
            CFRunLoopRun()
            IOHIDManagerClose(self.manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        thread.name = "OpenLamp HID"
        thread.start()

        lock.lock()
        self.thread = thread
        lock.unlock()

        _ = ready.wait(timeout: .now() + 2)
    }

    public func stop() {
        lock.lock()
        let loop = runLoop
        let opened = device
        device = nil
        runLoop = nil
        started = false
        lock.unlock()

        opened?.close()
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
                guard let self else { return }
                IOHIDManagerClose(self.manager, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            CFRunLoopStop(loop)
            CFRunLoopWakeUp(loop)
        }
    }

    /// Close and reopen the manager once. Used after a failed write, which is
    /// the only case where the handle can go stale without a removal callback.
    public func restart() {
        lock.lock()
        let loop = runLoop
        lock.unlock()
        guard let loop else { return }

        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let opened = self.device
            self.device = nil
            self.lock.unlock()
            opened?.close()

            IOHIDManagerClose(self.manager, IOOptionBits(kIOHIDOptionsTypeNone))
            let result = IOHIDManagerOpen(self.manager, IOOptionBits(kIOHIDOptionsTypeNone))
            if result != kIOReturnSuccess {
                self.report("Could not reopen the HID manager (0x\(String(result, radix: 16))).")
            }
        }
        CFRunLoopWakeUp(loop)
    }

    fileprivate func handleAdded(_ deviceRef: IOHIDDevice) {
        lock.lock()
        let existing = device
        lock.unlock()
        guard existing == nil else { return }

        let result = IOHIDDeviceOpen(deviceRef, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            report("Could not open the light strip (0x\(String(result, radix: 16))). Quit any other controller holding it.")
            return
        }

        let handle = HIDDevice(device: deviceRef)
        lock.lock()
        device = handle
        lock.unlock()

        callbacks.async { [weak self] in self?.onAttach?(handle) }
    }

    fileprivate func handleRemoved(_ deviceRef: IOHIDDevice) {
        lock.lock()
        let handle = device
        device = nil
        lock.unlock()
        guard let handle, CFEqual(handle.device, deviceRef) else { return }
        callbacks.async { [weak self] in self?.onDetach?(handle) }
    }

    fileprivate func report(_ message: String) {
        callbacks.async { [weak self] in self?.onError?(message) }
    }
}

private func deviceAddedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue().handleAdded(device)
}

private func deviceRemovedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue().handleRemoved(device)
}
