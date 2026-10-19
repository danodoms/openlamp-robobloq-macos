import AppKit
import Combine
import OpenLampKit
import SwiftUI

@MainActor
final class AppModel: NSObject, ObservableObject {
    @Published var state: LampState {
        didSet {
            store.state = state
            actor.update(state)
        }
    }
    @Published private(set) var isConnected = false
    @Published private(set) var deviceInfo: DeviceInfo?
    @Published private(set) var errorText: String?

    private let store = LampStore()
    private let actor = DeviceActor()

    override init() {
        state = store.state
        super.init()
        actor.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
        }
        actor.start(state: state)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func didWake() {
        actor.reapply()
    }

    func choose(_ color: RGB) {
        var next = state
        next.color = color
        next.isOn = true
        state = next
    }

    func toggle() {
        var next = state
        next.isOn.toggle()
        state = next
    }

    var menuBarIcon: String {
        guard isConnected else { return "lightbulb.slash" }
        return state.isOn ? "lightbulb.fill" : "lightbulb"
    }

    var menuBarOpacity: Double {
        isConnected ? 1 : 0.35
    }

    private func handle(_ event: DeviceEvent) {
        switch event {
        case .connected(let info):
            isConnected = true
            deviceInfo = info
            errorText = nil
            NSLog("OpenLamp: connected (\(info.ledCount) LEDs, firmware \(info.firmware))")
        case .disconnected:
            isConnected = false
            NSLog("OpenLamp: disconnected")
        case .failure(let message):
            errorText = message
            NSLog("OpenLamp: \(message)")
        }
    }
}

extension RGB {
    var swiftUIColor: Color {
        Color(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
