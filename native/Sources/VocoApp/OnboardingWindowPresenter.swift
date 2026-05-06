import AppKit
import SwiftUI
import VocoAppCore

@MainActor
final class OnboardingWindowPresenter {
    static let shared = OnboardingWindowPresenter()

    private var window: NSWindow?

    private init() {}

    func show(coordinator: AppCoordinator) {
        if window == nil {
            let view = OnboardingView(coordinator: coordinator)
            let hostingController = NSHostingController(rootView: view)
            let onboardingWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            onboardingWindow.title = "Voco 首次设置"
            onboardingWindow.center()
            onboardingWindow.contentViewController = hostingController
            onboardingWindow.isReleasedWhenClosed = false
            window = onboardingWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}
