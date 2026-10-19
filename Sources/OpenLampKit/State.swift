import Foundation

public struct LampState: Equatable, Sendable {
    public var color: RGB
    /// UI brightness, 0 to 1. The device takes 1 to 255.
    public var brightness: Double
    public var isOn: Bool

    public init(color: RGB = Preset.warm.color, brightness: Double = 0.8, isOn: Bool = false) {
        self.color = color
        self.brightness = brightness
        self.isOn = isOn
    }

    public var brightnessByte: UInt8 {
        let scaled = (min(max(brightness, 0), 1) * 255).rounded()
        return UInt8(max(1, min(255, Int(scaled))))
    }
}

public struct Preset: Identifiable, Sendable {
    public let name: String
    public let color: RGB

    public var id: String { name }

    public static let candle = Preset(name: "Candle", color: RGB(r: 255, g: 147, b: 41))
    public static let warm = Preset(name: "Warm", color: RGB(r: 255, g: 180, b: 107))
    public static let paper = Preset(name: "Paper", color: RGB(r: 255, g: 214, b: 170))
    public static let daylight = Preset(name: "Daylight", color: RGB(r: 255, g: 241, b: 224))

    public static let all: [Preset] = [candle, warm, paper, daylight]
}

public final class LampStore {
    private enum Key {
        static let red = "color.red"
        static let green = "color.green"
        static let blue = "color.blue"
        static let brightness = "brightness"
        static let isOn = "isOn"
        static let askedLogin = "askedLogin"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var state: LampState {
        get {
            let fallback = LampState()
            let color: RGB
            if defaults.object(forKey: Key.red) != nil {
                color = RGB(
                    r: UInt8(clamping: defaults.integer(forKey: Key.red)),
                    g: UInt8(clamping: defaults.integer(forKey: Key.green)),
                    b: UInt8(clamping: defaults.integer(forKey: Key.blue))
                )
            } else {
                color = fallback.color
            }
            let brightness = defaults.object(forKey: Key.brightness) == nil
                ? fallback.brightness
                : defaults.double(forKey: Key.brightness)
            return LampState(
                color: color,
                brightness: brightness,
                isOn: defaults.bool(forKey: Key.isOn)
            )
        }
        set {
            defaults.set(Int(newValue.color.r), forKey: Key.red)
            defaults.set(Int(newValue.color.g), forKey: Key.green)
            defaults.set(Int(newValue.color.b), forKey: Key.blue)
            defaults.set(newValue.brightness, forKey: Key.brightness)
            defaults.set(newValue.isOn, forKey: Key.isOn)
        }
    }

    /// Set once, after the first-launch login item prompt has been shown.
    public var hasAskedLogin: Bool {
        get { defaults.bool(forKey: Key.askedLogin) }
        set { defaults.set(newValue, forKey: Key.askedLogin) }
    }
}
