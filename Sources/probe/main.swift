import Foundation
import OpenLampKit

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    usage: probe [RRGGBB | off] [brightness]

    Reads the strip's device info, applies one colour and exits.
    With no arguments it lights the strip warm at 80%.
    """)
    exit(0)
}

let shouldTurnOff = arguments.first?.lowercased() == "off"
var color = Preset.warm.color
if let first = arguments.first, !shouldTurnOff {
    guard let parsed = RGB(hex: first) else {
        fputs("probe: colour must be six hex digits, e.g. FFB46B\n", stderr)
        exit(2)
    }
    color = parsed
}

var brightness = 0.8
if arguments.count > 1 {
    guard let parsed = Double(arguments[1]), (0...1).contains(parsed) else {
        fputs("probe: brightness must be between 0 and 1\n", stderr)
        exit(2)
    }
    brightness = parsed
}

final class DeviceBox {
    var device: HIDDevice?
}

let box = DeviceBox()
let found = DispatchSemaphore(value: 0)
let transport = HIDTransport()
transport.onAttach = { device in
    box.device = device
    found.signal()
}
transport.onError = { message in
    fputs("probe: \(message)\n", stderr)
}

transport.start()

guard found.wait(timeout: .now() + 3) == .success, let device = box.device else {
    fputs("probe: light strip not found on 0x1A86:0xFE07\n", stderr)
    transport.stop()
    exit(1)
}

let session = RobobloqSession(device: device)
guard let info = session.readInfo() else {
    fputs("probe: could not read device info (another controller may be holding the strip)\n", stderr)
    device.close()
    transport.stop()
    exit(1)
}

print("\(info.ledCount) LEDs, \(info.physicalSize)\", firmware \(info.firmware), uuid \(info.uuid)")

let state = LampState(color: color, brightness: brightness, isOn: !shouldTurnOff)
guard session.initialize(state) else {
    fputs("probe: write failed\n", stderr)
    device.close()
    transport.stop()
    exit(1)
}

print(shouldTurnOff ? "strip off" : "strip set to \(color.hex) at \(Int(brightness * 100))%")

Thread.sleep(forTimeInterval: 0.2)
device.close()
transport.stop()
exit(0)
