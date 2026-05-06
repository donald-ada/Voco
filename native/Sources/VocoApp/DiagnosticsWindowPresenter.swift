import AppKit
import SwiftUI
import VocoAppCore

@MainActor
final class DiagnosticsWindowPresenter {
    static let shared = DiagnosticsWindowPresenter()

    private var window: NSWindow?

    private init() {}

    func show(coordinator: AppCoordinator) {
        if window == nil {
            let view = DiagnosticsView(coordinator: coordinator)
            let hostingController = NSHostingController(rootView: view)
            let diagnosticsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            diagnosticsWindow.title = "Voco 诊断"
            diagnosticsWindow.center()
            diagnosticsWindow.contentViewController = hostingController
            diagnosticsWindow.isReleasedWhenClosed = false
            window = diagnosticsWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
