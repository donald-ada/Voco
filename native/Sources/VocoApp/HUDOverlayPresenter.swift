import AppKit
import Combine
import SwiftUI
import VocoAppCore

@MainActor
final class HUDOverlayPresenter {
    static let shared = HUDOverlayPresenter()

    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var autoHideTask: Task<Void, Never>?
    private var lastSnapshot: HUDSnapshot = .hidden

    private init() {}

    func attach(coordinator: AppCoordinator) {
        if panel == nil {
            createPanel(coordinator: coordinator)
        }

        cancellables.removeAll()
        coordinator.objectWillChange
            .sink { [weak self, weak coordinator] _ in
                Task { @MainActor in
                    guard let coordinator else {
                        return
                    }
                    self?.update(with: coordinator.hudSnapshot)
                }
            }
            .store(in: &cancellables)

        update(with: coordinator.hudSnapshot)
    }

    private func createPanel(coordinator: AppCoordinator) {
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: HUDOverlayChrome.Layout.panelSize.width,
                height: HUDOverlayChrome.Layout.panelSize.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = NSHostingController(rootView: HUDOverlayView(coordinator: coordinator))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
    }

    private func update(with snapshot: HUDSnapshot) {
        autoHideTask?.cancel()
        lastSnapshot = snapshot

        guard snapshot.isVisible else {
            panel?.orderOut(nil)
            return
        }

        positionPanel()
        panel?.orderFrontRegardless()

        if let seconds = snapshot.autoHideAfterSeconds {
            scheduleAutoHide(after: seconds, snapshot: snapshot)
        }
    }

    private func positionPanel() {
        guard let panel else {
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? .zero
        let visibleFrame = screen?.visibleFrame ?? screenFrame
        let origin = HUDOverlayChrome.panelOrigin(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )
        panel.setFrame(
            NSRect(origin: origin, size: HUDOverlayChrome.Layout.panelSize),
            display: true
        )
    }

    private func scheduleAutoHide(after seconds: Double, snapshot: HUDSnapshot) {
        autoHideTask = Task { [weak self] in
            let nanoseconds = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            await MainActor.run {
                guard self?.lastSnapshot == snapshot else {
                    return
                }
                self?.panel?.orderOut(nil)
            }
        }
    }
}
