import XCTest
@testable import OpenLampKit

final class ProtocolTests: XCTestCase {
    func testSimplePacketFramingAndChecksum() {
        let packet = Robobloq.packet([0x87, 0xFF], index: 0x02)

        XCTAssertEqual(packet.count, 64)
        XCTAssertEqual(Array(packet.prefix(6)), [0x52, 0x42, 0x07, 0x02, 0x87, 0xFF])
        XCTAssertEqual(packet[6], 0x52 &+ 0x42 &+ 0x07 &+ 0x02 &+ 0x87 &+ 0xFF)
        XCTAssertTrue(packet.dropFirst(7).allSatisfy { $0 == 0 })
    }

    func testWholeStripColourPayload() {
        let payload = Robobloq.setColor(RGB(r: 0x11, g: 0x22, b: 0x33), ledCount: 54)

        XCTAssertEqual(
            payload,
            [0x86, 0x01, 0x11, 0x22, 0x33, 54, 55, 0x00, 0x00, 0x00, 0xFE]
        )

        let packet = Robobloq.packet(payload, index: 0x02)
        XCTAssertEqual(packet[2], UInt8(payload.count + 5))
        XCTAssertEqual(packet[3], 0x02)
    }

    func testLedCountWrapsInDummyRange() {
        let payload = Robobloq.setColor(.black, ledCount: 255)
        XCTAssertEqual(payload[6], 0)
    }

    func testBrightnessCoercesZeroToOne() {
        XCTAssertEqual(Robobloq.setBrightness(0), [0x87, 0x01])
        XCTAssertEqual(Robobloq.setBrightness(0xF9), [0x87, 0xF9])
        XCTAssertEqual(Robobloq.setBrightness(0xFF), [0x87, 0xFF])
    }

    func testDynamicSpeedIsInverted() {
        XCTAssertEqual(Robobloq.setDynamicSpeed(0x00), [0x8A, 0x64])
        XCTAssertEqual(Robobloq.setDynamicSpeed(0x32), [0x8A, 0x32])
        XCTAssertEqual(Robobloq.setDynamicSpeed(0x64), [0x8A, 0x00])
        XCTAssertEqual(Robobloq.setDynamicSpeed(0xFF), [0x8A, 0x00])
    }

    func testMultiPacketHeaderLengthAndPadding() {
        let payload = Array(repeating: UInt8(0xAB), count: 5 * 34)
        let data = Robobloq.multiPacket(command: 0x80, payload: payload, index: 0x03)

        XCTAssertEqual(Array(data.prefix(6)), [0x53, 0x43, 0x00, 0xB1, 0x03, 0x80])
        XCTAssertEqual(data.count % 64, 0)
        XCTAssertEqual(data.count, 192)
        let checksumIndex = 6 + payload.count
        XCTAssertEqual(data[checksumIndex], Robobloq.checksum(Array(data.prefix(checksumIndex))))
        XCTAssertTrue(data[(checksumIndex + 1)...].allSatisfy { $0 == 0 })
    }

    func testDeviceInfoParsing() {
        var report = [UInt8](repeating: 0, count: 64)
        report[0] = 0x52
        report[1] = 0x42
        report[2] = 0x19
        report[3] = 0x02
        report[4] = 0x82
        report[5] = 0x00
        report[6] = 0x05
        report[7] = 0x01
        report[8] = 24
        report[11] = 54
        let uuid: [UInt8] = [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77]
        report.replaceSubrange(12..<20, with: uuid)
        report[21] = 1
        report[22] = 9
        report[23] = 4

        let info = Robobloq.deviceInfo(from: report)

        XCTAssertEqual(info?.ledCount, 54)
        XCTAssertEqual(info?.physicalSize, 24)
        XCTAssertEqual(info?.firmware, "1.9.4")
        XCTAssertEqual(info?.uuid, "0011223344556677")
        XCTAssertEqual(info?.deviceID, "000501")
    }

    func testDeviceInfoRejectsShortOrEmptyReplies() {
        XCTAssertNil(Robobloq.deviceInfo(from: []))
        XCTAssertNil(Robobloq.deviceInfo(from: [UInt8](repeating: 0, count: 23)))

        var report = [UInt8](repeating: 0, count: 64)
        report[11] = 0
        XCTAssertNil(Robobloq.deviceInfo(from: report))
    }

    func testBrightnessByteClamps() {
        XCTAssertEqual(LampState(brightness: 0).brightnessByte, 1)
        XCTAssertEqual(LampState(brightness: 0.5).brightnessByte, 128)
        XCTAssertEqual(LampState(brightness: 1).brightnessByte, 255)
        XCTAssertEqual(LampState(brightness: 2).brightnessByte, 255)
    }

    func testStoreRoundTrip() {
        let suite = "OpenLampTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = LampStore(defaults: defaults)
        XCTAssertEqual(store.state, LampState(color: Preset.warm.color, brightness: 0.8, isOn: false))
        XCTAssertFalse(store.hasAskedLogin)

        let state = LampState(color: RGB(r: 1, g: 2, b: 3), brightness: 0.25, isOn: true)
        store.state = state
        store.hasAskedLogin = true

        XCTAssertEqual(LampStore(defaults: defaults).state, state)
        XCTAssertTrue(LampStore(defaults: defaults).hasAskedLogin)
    }

    func testColourHex() {
        XCTAssertEqual(RGB(hex: "#FFB46B"), RGB(r: 255, g: 180, b: 107))
        XCTAssertEqual(RGB(hex: "ffb46b")?.hex, "#FFB46B")
        XCTAssertNil(RGB(hex: "nope"))
        XCTAssertNil(RGB(hex: "12345"))
    }
}
