import Foundation

public enum DeviceEvent {
    case connected(DeviceInfo)
    case disconnected
    case failure(String)
}

/// A serial owner of one open strip. All writes go through one queue, so a UI
/// change and a re-apply on wake cannot interleave packets.
public final class RobobloqSession {
    public let device: HIDDevice
    public private(set) var info: DeviceInfo?
    private var packetIndex: UInt8 = 0x02

    public init(device: HIDDevice) {
        self.device = device
    }

    /// Ask for the device info block, retrying with a no-op nudge like OpenRGB.
    public func readInfo() -> DeviceInfo? {
        let expected = packetIndex
        device.inbox.clear()
        guard write(Robobloq.readDeviceInfo) else { return nil }

        for _ in 0..<3 {
            if let report = device.inbox.wait(forPacket: expected, timeout: 1.0),
               let info = Robobloq.deviceInfo(from: report) {
                self.info = info
                return info
            }
            guard write(Robobloq.disableKeyboard) else { return nil }
        }
        return nil
    }

    /// Linear init from the reference controller: disable the keyboard page,
    /// then brightness, dynamic speed and current colour.
    public func initialize(_ state: LampState) -> Bool {
        guard let info else { return false }
        guard write(Robobloq.disableKeyboard) else { return false }
        guard write(Robobloq.setBrightness(state.brightnessByte)) else { return false }
        guard write(Robobloq.setDynamicSpeed(0x32)) else { return false }
        return writeColor(state, ledCount: info.ledCount)
    }

    public func apply(_ state: LampState) -> Bool {
        guard let info else { return false }
        guard write(Robobloq.setBrightness(state.brightnessByte)) else { return false }
        return writeColor(state, ledCount: info.ledCount)
    }

    public func close() {
        device.close()
    }

    private func writeColor(_ state: LampState, ledCount: UInt8) -> Bool {
        if state.isOn {
            return write(Robobloq.setColor(state.color, ledCount: ledCount))
        }
        guard write(Robobloq.turnOff) else { return false }
        return write(Robobloq.setColor(.black, ledCount: ledCount))
    }

    @discardableResult
    private func write(_ command: [UInt8]) -> Bool {
        let packet = Robobloq.packet(command, index: packetIndex)
        packetIndex = packetIndex &+ 1
        return device.write(packet)
    }
}

public final class DeviceActor {
    public var onEvent: ((DeviceEvent) -> Void)?

    private let queue = DispatchQueue(label: "OpenLamp.Device")
    private let transport = HIDTransport()
    private var session: RobobloqSession?
    private var state = LampState()
    private var pendingState: LampState?
    private var applyQueued = false
    private var started = false

    public init() {
        transport.onAttach = { [weak self] device in
            self?.queue.async { self?.attach(device) }
        }
        transport.onDetach = { [weak self] device in
            self?.queue.async { self?.detach(device) }
        }
        transport.onError = { [weak self] message in
            self?.emit(.failure(message))
        }
    }

    public func start(state: LampState) {
        queue.async {
            self.state = state
            guard !self.started else { return }
            self.started = true
            self.transport.start()
        }
    }

    public func stop() {
        queue.async {
            self.started = false
            self.session?.close()
            self.session = nil
            self.transport.stop()
        }
    }

    public func update(_ state: LampState) {
        queue.async {
            self.state = state
            guard self.session != nil else { return }
            self.pendingState = state
            guard !self.applyQueued else { return }
            self.applyQueued = true
            self.queue.async { self.flush() }
        }
    }

    /// Re-send everything after system wake. The device may have lost its state
    /// without a removal callback.
    public func reapply() {
        queue.async {
            guard let session = self.session else { return }
            if !session.initialize(self.state) {
                self.lost(session)
            }
        }
    }

    private func flush() {
        applyQueued = false
        guard let state = pendingState else { return }
        pendingState = nil
        guard let session else { return }
        if !session.apply(state) {
            lost(session)
        }
    }

    private func attach(_ device: HIDDevice) {
        guard session == nil else {
            device.close()
            return
        }

        let session = RobobloqSession(device: device)
        guard let info = session.readInfo() else {
            device.close()
            emit(.failure("Could not read the light strip's device info."))
            return
        }

        self.session = session
        guard session.initialize(state) else {
            lost(session)
            return
        }
        emit(.connected(info))
    }

    private func detach(_ device: HIDDevice) {
        guard let session, session.device === device else { return }
        self.session = nil
        session.close()
        emit(.disconnected)
    }

    private func lost(_ session: RobobloqSession) {
        guard self.session === session else { return }
        self.session = nil
        session.close()
        emit(.disconnected)

        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.started, self.session == nil else { return }
            self.transport.restart()
        }
    }

    private func emit(_ event: DeviceEvent) {
        onEvent?(event)
    }
}
