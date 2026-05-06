import AppKit
import Foundation
import VocoAppCore

@MainActor
final class MacHotkeyProvider: HotkeyProviding {
    private var monitor: HotkeyNSEventMonitor?

    func start(
        binding: HotkeyBinding,
        mode: HotkeyMode,
        onAction: @escaping @MainActor @Sendable (HotkeyAction) -> Void
    ) -> HotkeyRuntimeState {
        stop()

        let monitor = HotkeyNSEventMonitor(binding: binding, mode: mode, onAction: onAction)
        switch monitor.start() {
        case .success:
            self.monitor = monitor
            return .listening
        case .failure(let message):
            return .failed(message)
        }
    }

    func stop() {
        monitor?.stop()
        monitor = nil
    }
}

private final class HotkeyNSEventMonitor: @unchecked Sendable {
    private static let eventMask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]

    private let state: HotkeyNSEventState
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(
        binding: HotkeyBinding,
        mode: HotkeyMode,
        onAction: @escaping @MainActor @Sendable (HotkeyAction) -> Void
    ) {
        self.state = HotkeyNSEventState(binding: binding, mode: mode, onAction: onAction)
    }

    func start() -> HotkeyMonitorStartResult {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.eventMask) { [state] event in
            state.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.eventMask) { [state] event in
            state.handle(event)
            return event
        }

        guard globalMonitor != nil || localMonitor != nil else {
            return .failure("failed to install NSEvent hotkey monitor; grant Accessibility")
        }

        return .success
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }
}

private final class HotkeyNSEventState: @unchecked Sendable {
    private let lock = NSLock()
    private var matcher: HotkeyMatcher
    private let onAction: @MainActor @Sendable (HotkeyAction) -> Void

    init(
        binding: HotkeyBinding,
        mode: HotkeyMode,
        onAction: @escaping @MainActor @Sendable (HotkeyAction) -> Void
    ) {
        self.matcher = HotkeyMatcher(binding: binding, mode: mode)
        self.onAction = onAction
    }

    func handle(_ event: NSEvent) {
        guard let kind = HotkeyInputEventKind(eventType: event.type) else {
            return
        }

        let keyCode = event.keyCode
        let flags = UInt64(event.modifierFlags.rawValue)
        let input = HotkeyInputEvent(kind: kind, keyCode: keyCode, modifierFlags: flags)

        lock.lock()
        let action = matcher.handle(input)
        lock.unlock()

        if let action {
            Task { @MainActor in
                onAction(action)
            }
        }
    }
}

private extension HotkeyInputEventKind {
    init?(eventType: NSEvent.EventType) {
        switch eventType {
        case .keyDown:
            self = .keyDown
        case .keyUp:
            self = .keyUp
        case .flagsChanged:
            self = .flagsChanged
        default:
            return nil
        }
    }
}

private enum HotkeyMonitorStartResult {
    case success
    case failure(String)
}
