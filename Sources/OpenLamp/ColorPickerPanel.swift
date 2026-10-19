import OpenLampKit
import SwiftUI

/// A compact HSB picker that lives inside the menu bar popover. It avoids the
/// system NSColorPanel, which does not stay attached to a MenuBarExtra window.
struct ColorPickerPanel: View {
    let color: RGB
    let onColorChange: (RGB) -> Void

    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double

    init(color: RGB, onColorChange: @escaping (RGB) -> Void) {
        self.color = color
        self.onColorChange = onColorChange
        let hsb = color.hsb
        _hue = State(initialValue: hsb.hue)
        _saturation = State(initialValue: hsb.saturation)
        _brightness = State(initialValue: hsb.brightness)
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    marker(size: 14)
                        .position(
                            x: 7 + saturation * (geometry.size.width - 14),
                            y: 7 + (1 - brightness) * (geometry.size.height - 14)
                        )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.15))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        saturation = clamp((value.location.x - 7) / (geometry.size.width - 14))
                        brightness = 1 - clamp((value.location.y - 7) / (geometry.size.height - 14))
                        apply()
                    }
                )
            }
            .frame(height: 96)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    LinearGradient(colors: hueStops, startPoint: .leading, endPoint: .trailing)
                        .clipShape(Capsule())
                    marker(size: 16)
                        .position(
                            x: 8 + hue * (geometry.size.width - 16),
                            y: geometry.size.height / 2
                        )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        hue = clamp((value.location.x - 8) / (geometry.size.width - 16))
                        if saturation == 0 { saturation = 1 }
                        if brightness == 0 { brightness = 1 }
                        apply()
                    }
                )
            }
            .frame(height: 16)
        }
        .onChange(of: color) { newColor in
            let current = RGB(hue: hue, saturation: saturation, brightness: brightness)
            guard current != newColor else { return }
            let hsb = newColor.hsb
            hue = hsb.hue
            saturation = hsb.saturation
            brightness = hsb.brightness
        }
    }

    private func marker(size: CGFloat) -> some View {
        Circle()
            .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
            .overlay {
                Circle().strokeBorder(.white, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.25), radius: 2)
            .frame(width: size, height: size)
    }

    private func apply() {
        onColorChange(RGB(hue: hue, saturation: saturation, brightness: brightness))
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private var hueStops: [Color] {
        stride(from: 0.0, through: 1.0, by: 1.0 / 6.0).map {
            Color(hue: $0, saturation: 1, brightness: 1)
        }
    }
}
