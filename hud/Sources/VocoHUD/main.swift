import AppKit
import SwiftUI
import VocoHUDCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = HudModel()
    private var bottomPanel: NSPanel?
    private var topPanel: NSPanel?
    private var errorGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createBottomPanel()
        createTopPanel()
        startInputReader()
    }

    private func createBottomPanel() {
        let view = CapsuleView(model: model)
        let hosting = NSHostingController(rootView: view)
        makeTransparent(hosting.view)
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: HudTheme.Layout.panelWidth,
                height: HudTheme.Layout.panelHeight
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
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.orderOut(nil)
        self.bottomPanel = panel
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
        panel.level = .floating
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
        switch event {
        case .state(.hidden, _):
            bottomPanel?.orderOut(nil)
            topPanel?.orderOut(nil)
        case .state(.error, _):
            errorGeneration += 1
            let generation = errorGeneration
            topPanel?.orderOut(nil)
            positionBottomPanel()
            bottomPanel?.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.model.state == .error && self.errorGeneration == generation {
                    self.model.apply(.state(.hidden, message: nil))
                    self.bottomPanel?.orderOut(nil)
                    self.topPanel?.orderOut(nil)
                }
            }
        case .state:
            positionBottomPanel()
            positionTopPanel()
            bottomPanel?.orderFrontRegardless()
            topPanel?.orderFrontRegardless()
        case .amplitude:
            break
        case .transcript:
            guard model.isVisible else { return }
            positionTopPanel()
            topPanel?.orderFrontRegardless()
        }
    }

    private func positionBottomPanel() {
        guard let panel = bottomPanel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + HudTheme.Layout.panelBottomOffset - HudTheme.Layout.shadowPadding
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func positionTopPanel() {
        guard let panel = topPanel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height + HudTheme.Layout.notchShadowPadding - HudTheme.Layout.notchTopOffset
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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
