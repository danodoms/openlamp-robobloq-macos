import AppKit
import OpenLampKit
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.isConnected ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(model.isConnected ? "Connected" : "Light strip not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let info = model.deviceInfo {
                    Text("\(info.ledCount) LEDs · \(info.firmware)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 10) {
                ForEach(Preset.all) { preset in
                    Button {
                        model.choose(preset.color)
                    } label: {
                        Circle()
                            .fill(preset.color.swiftUIColor)
                            .frame(width: 30, height: 30)
                            .overlay {
                                Circle().strokeBorder(
                                    Color.primary.opacity(model.state.color == preset.color ? 0.7 : 0.12),
                                    lineWidth: model.state.color == preset.color ? 2 : 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                }
            }

            ColorPicker("Colour", selection: colorBinding, supportsOpacity: false)
                .font(.callout)

            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                Slider(value: brightnessBinding, in: 0...1)
                Image(systemName: "sun.max")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let error = model.errorText {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button(model.state.isOn ? "Turn Off" : "Turn On") {
                    model.toggle()
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { model.state.color.swiftUIColor },
            set: { model.choose(RGB(color: $0)) }
        )
    }

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { model.state.brightness },
            set: { value in
                var next = model.state
                next.brightness = value
                model.state = next
            }
        )
    }
}
