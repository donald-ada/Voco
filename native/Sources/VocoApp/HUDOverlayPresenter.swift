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
    private var deferredUpdateTask: Task<Void, Never>?
    private var lastSnapshot: HUDSnapshot = .hidden
    private var presentationState = HUDOverlayPresentationState()

    private init() {}

    func attach(coordinator: AppCoordinator) {
        if panel == nil {
            createPanel(coordinator: coordinator)
        }

        cancellables.removeAll()
        deferredUpdateTask?.cancel()
        deferredUpdateTask = nil
        coordinator.objectWillChange
            .sink { [weak self, weak coordinator] _ in
                Task { @MainActor in
                    guard let coordinator else {
                        return
                    }
                    self?.scheduleDeferredUpdate(coordinator: coordinator)
                }
            }
            .store(in: &cancellables)

        update(with: coordinator.hudSnapshot)
    }

    private func scheduleDeferredUpdate(coordinator: AppCoordinator) {
        deferredUpdateTask?.cancel()
        deferredUpdateTask = Task { @MainActor [weak self, weak coordinator] in
            await Task.yield()
            guard !Task.isCancelled, let coordinator else {
                return
            }
            self?.update(with: coordinator.hudSnapshot)
        }
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

        switch presentationState.presentationDecision(for: snapshot) {
        case .hide:
            panel?.orderOut(nil)
            return
        case .ignore:
            return
        case .show:
            break
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
                self?.presentationState.markAutoHidden(snapshot)
                self?.panel?.orderOut(nil)
            }
        }
    }
}

enum HUDOverlayPresentationDecision: Equatable {
    case show
    case hide
    case ignore
}

struct HUDOverlayPresentationState {
    private var autoHiddenSnapshot: HUDSnapshot?

    mutating func presentationDecision(for snapshot: HUDSnapshot) -> HUDOverlayPresentationDecision {
        if autoHiddenSnapshot != snapshot {
            autoHiddenSnapshot = nil
        }

        guard snapshot.isVisible else {
            autoHiddenSnapshot = nil
            return .hide
        }

        guard autoHiddenSnapshot != snapshot else {
            return .ignore
        }

        return .show
    }

    mutating func markAutoHidden(_ snapshot: HUDSnapshot) {
        autoHiddenSnapshot = snapshot
    }
}
