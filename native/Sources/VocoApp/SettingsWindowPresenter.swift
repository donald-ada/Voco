import AppKit
import SwiftUI
import VocoAppCore

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?

    private init() {}

    func show(coordinator: AppCoordinator) {
        if window == nil {
            let view = SettingsView(coordinator: coordinator)
            let hostingController = NSHostingController(rootView: view)
            let settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow.title = "Voco 设置"
            settingsWindow.center()
            settingsWindow.contentViewController = hostingController
            settingsWindow.isReleasedWhenClosed = false
            window = settingsWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
