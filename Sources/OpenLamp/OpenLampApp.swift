import AppKit
import OpenLampKit
import ServiceManagement
import SwiftUI

@main
struct OpenLampApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
        } label: {
            Image(systemName: model.menuBarIcon)
                .opacity(model.menuBarOpacity)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.offerLoginItem()
        }
    }

    /// Offered once on first launch, then left to System Settings.
    private func offerLoginItem() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let store = LampStore()
        guard !store.hasAskedLogin else { return }
        store.hasAskedLogin = true

        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }

        let alert = NSAlert()
        alert.messageText = "Start OpenLamp at login?"
        alert.informativeText = "OpenLamp keeps the strip at its last colour. You can change this later in System Settings > General > Login Items."
        alert.addButton(withTitle: "Start at Login")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try service.register()
            } catch {
                NSLog("OpenLamp: could not register login item: \(error)")
            }
        }
    }
}
