import Foundation

public struct RGB: Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            r: UInt8((value >> 16) & 0xFF),
            g: UInt8((value >> 8) & 0xFF),
            b: UInt8(value & 0xFF)
        )
    }

    public static let black = RGB(r: 0, g: 0, b: 0)

    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
}

public struct DeviceInfo: Equatable, Sendable {
    public let ledCount: UInt8
    public let physicalSize: UInt8
    public let firmware: String
    public let uuid: String
    public let deviceID: String
}

/// Wire protocol for the Robobloq monitor light strip.
/// Derived from OpenRGB's RobobloqLightStripController (GPL-2.0-or-later).
public enum Robobloq {
    public static let vendorID = 0x1A86
    public static let productID = 0xFE07
    public static let usagePage = 0xFF00
    public static let usage = 0x01
    public static let reportLength = 64

    public static let disableKeyboard: [UInt8] = [0x93, 0x00]
    public static let readDeviceInfo: [UInt8] = [0x82]
    public static let turnOff: [UInt8] = [0x97]

    /// Simple packet: 52 42 <len> <index> <command...> <checksum> [pad to 64].
    /// `len` is command length plus five.
    public static func packet(_ command: [UInt8], index: UInt8) -> [UInt8] {
        precondition(command.count + 6 <= reportLength, "command too large for one packet")
        let length = UInt8(command.count + 5)
        var packet: [UInt8] = [0x52, 0x42, length, index] + command
        packet.append(checksum(packet))
        packet.append(contentsOf: repeatElement(0, count: reportLength - packet.count))
        return packet
    }

    /// Multi packet: 53 43 <len hi> <len lo> <index> <command> <payload...> <checksum>,
    /// padded to a multiple of 64 bytes. `len` is payload length plus seven.
    public static func multiPacket(command: UInt8, payload: [UInt8], index: UInt8) -> [UInt8] {
        let length = payload.count + 7
        var data: [UInt8] = [
            0x53, 0x43,
            UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF),
            index, command,
        ] + payload
        data.append(checksum(data))
        let remainder = data.count % reportLength
        if remainder > 0 {
            data.append(contentsOf: repeatElement(0, count: reportLength - remainder))
        }
        return data
    }

    public static func setColor(_ color: RGB, ledCount: UInt8) -> [UInt8] {
        [
            0x86, 0x01,
            color.r, color.g, color.b,
            ledCount, ledCount &+ 1,
            0x00, 0x00, 0x00, 0xFE,
        ]
    }

    /// Zero is interpreted by the device as maximum, so it is coerced to one.
    public static func setBrightness(_ value: UInt8) -> [UInt8] {
        [0x87, value == 0 ? 1 : value]
    }

    /// The device counts down from 0x64: 0x00 is fast, 0x64 is slow.
    public static func setDynamicSpeed(_ speed: UInt8) -> [UInt8] {
        [0x8A, 0x64 &- min(speed, 0x64)]
    }

    public static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(UInt8(0)) { $0 &+ $1 }
    }

    public static func deviceInfo(from report: [UInt8]) -> DeviceInfo? {
        guard report.count >= 24, report[11] > 0 else { return nil }
        let id = String(format: "%02X%02X%02X", report[5], report[6], report[7])
        let uuid = report[12..<20].map { String(format: "%02x", $0) }.joined()
        let firmware = "\(report[21]).\(report[22]).\(report[23])"
        return DeviceInfo(
            ledCount: report[11],
            physicalSize: report[8],
            firmware: firmware,
            uuid: uuid,
            deviceID: id
        )
    }
}
