import Foundation

extension RGB {
    public init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue.truncatingRemainder(dividingBy: 1) + 1)
            .truncatingRemainder(dividingBy: 1) * 6
        let s = min(max(saturation, 0), 1)
        let v = min(max(brightness, 0), 1)

        let index = Int(h)
        let f = h - Double(index)
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))

        let rgb: (Double, Double, Double)
        switch index % 6 {
        case 0: rgb = (v, t, p)
        case 1: rgb = (q, v, p)
        case 2: rgb = (p, v, t)
        case 3: rgb = (p, q, v)
        case 4: rgb = (t, p, v)
        default: rgb = (v, p, q)
        }

        self.init(
            r: UInt8((rgb.0 * 255).rounded()),
            g: UInt8((rgb.1 * 255).rounded()),
            b: UInt8((rgb.2 * 255).rounded())
        )
    }

    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let r = Double(r) / 255
        let g = Double(g) / 255
        let b = Double(b) / 255

        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue

        var hue = 0.0
        if delta > 0 {
            if maxValue == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxValue == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }

        return (hue, maxValue == 0 ? 0 : delta / maxValue, maxValue)
    }
}
