import AppKit
import SwiftUI
import VocoAppCore

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()
    static let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("com.voco.settings-window")

    private var window: NSWindow?
    private let windowFactory: @MainActor (AppCoordinator) -> NSWindow

    init(windowFactory: @escaping @MainActor (AppCoordinator) -> NSWindow = SettingsWindowPresenter.makeSettingsWindow) {
        self.windowFactory = windowFactory
    }

    func show(coordinator: AppCoordinator) {
        let settingsWindow = resolvedWindow(coordinator: coordinator)
        configure(settingsWindow, coordinator: coordinator)

        NSApplication.shared.activate(ignoringOtherApps: true)
        if settingsWindow.isMiniaturized {
            settingsWindow.deminiaturize(nil)
        }
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    var presentedWindowForTesting: NSWindow? {
        window
    }

    private func resolvedWindow(coordinator: AppCoordinator) -> NSWindow {
        if let window {
            return window
        }

        if let existingWindow = NSApplication.shared.windows.first(where: { $0.identifier == Self.settingsWindowIdentifier }) {
            window = existingWindow
            return existingWindow
        }

        let settingsWindow = windowFactory(coordinator)
        window = settingsWindow
        return settingsWindow
    }

    private func configure(_ settingsWindow: NSWindow, coordinator: AppCoordinator) {
        settingsWindow.identifier = Self.settingsWindowIdentifier
        settingsWindow.title = coordinator.strings.app.settingsWindowTitle
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.isRestorable = false
        settingsWindow.tabbingMode = .disallowed

        var collectionBehavior = settingsWindow.collectionBehavior
        collectionBehavior.insert(.fullScreenNone)
        collectionBehavior.remove(.fullScreenPrimary)
        collectionBehavior.remove(.fullScreenAuxiliary)
        settingsWindow.collectionBehavior = collectionBehavior
    }

    private static func makeSettingsWindow(coordinator: AppCoordinator) -> NSWindow {
        let layoutPolicy = SettingsWorkbenchLayoutPolicy.standard
        let view = SettingsView(coordinator: coordinator)
        let hostingController = NSHostingController(rootView: view)
        let settingsWindow = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: layoutPolicy.windowInitialWidth,
                height: layoutPolicy.windowInitialHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = coordinator.strings.app.settingsWindowTitle
        settingsWindow.titleVisibility = .hidden
        settingsWindow.titlebarAppearsTransparent = true
        settingsWindow.isMovableByWindowBackground = false
        settingsWindow.minSize = NSSize(
            width: layoutPolicy.windowMinimumWidth,
            height: layoutPolicy.windowMinimumHeight
        )
        settingsWindow.center()
        settingsWindow.contentViewController = hostingController
        return settingsWindow
    }
}
