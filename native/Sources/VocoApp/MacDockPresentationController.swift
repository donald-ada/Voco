import AppKit
import VocoAppCore

@MainActor
enum MacDockPresentationController {
    static func apply(displayInDockEnabled: Bool) {
        switch AppDockPresentationPolicy(displayInDockEnabled: displayInDockEnabled).action {
        case .showInDock:
            NSApplication.shared.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        case .hideFromDock:
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}
