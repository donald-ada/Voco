import AppKit
import SwiftUI
import VocoHUDCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = HudModel()
    private var topPanel: NSPanel?
    private var errorGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createTopPanel()
        startInputReader()
    }

    private func createTopPanel() {
        let view = TranscriptIslandView(model: model)
        let hosting = NSHostingController(rootView: view)
        makeTransparent(hosting.view)
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: HudTheme.Layout.notchPanelWidth,
                height: HudTheme.Layout.notchPanelHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        makeTransparent(panel.contentView)
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.orderOut(nil)
        self.topPanel = panel
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
        let action = HudPresentationPolicy.action(for: event, isVisible: model.isVisible)

        switch action.topPanel {
        case .show:
            positionTopPanel()
            topPanel?.orderFrontRegardless()
        case .hide:
            topPanel?.orderOut(nil)
        case .unchanged:
            break
        }

        if action.autoHideError {
            errorGeneration += 1
            let generation = errorGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.model.state == .error && self.errorGeneration == generation {
                    self.model.apply(.state(.hidden, message: nil))
                    self.topPanel?.orderOut(nil)
                }
            }
        }
    }

    private func positionTopPanel() {
        guard let panel = topPanel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen, !screen.frame.isEmpty else { return }
        let size = panel.frame.size
        let origin = HudPanelPositioning.notchOrigin(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            panelSize: size
        )
        panel.setFrameOrigin(origin)
    }

    private func makeTransparent(_ view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
