import AppKit
import SwiftUI
import VocoHUDCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = HudModel()
    private var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        startInputReader()
    }

    private func createPanel() {
        let view = CapsuleView(model: model)
        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.orderOut(nil)
        self.panel = panel
    }

    private func startInputReader() {
        DispatchQueue.global(qos: .userInitiated).async {
            while let line = readLine() {
                do {
                    let event = try HudEvent.decodeLine(line)
                    DispatchQueue.main.async {
                        self.apply(event)
                    }
                } catch {
                    fputs("voco-hud: decode error: \(error)\n", stderr)
                }
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    private func apply(_ event: HudEvent) {
        model.apply(event)
        switch event {
        case .state(.hidden, _):
            panel?.orderOut(nil)
        case .state(.error, _):
            positionPanel()
            panel?.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.model.state == .error {
                    self.model.apply(.state(.hidden, message: nil))
                    self.panel?.orderOut(nil)
                }
            }
        case .state:
            positionPanel()
            panel?.orderFrontRegardless()
        case .amplitude:
            break
        }
    }

    private func positionPanel() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + 96
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
