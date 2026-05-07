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
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            settingsWindow.title = "Voco 设置"
            settingsWindow.titleVisibility = .hidden
            settingsWindow.titlebarAppearsTransparent = true
            settingsWindow.isMovableByWindowBackground = true
            settingsWindow.minSize = NSSize(width: 900, height: 600)
            settingsWindow.center()
            settingsWindow.contentViewController = hostingController
            settingsWindow.isReleasedWhenClosed = false
            window = settingsWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
