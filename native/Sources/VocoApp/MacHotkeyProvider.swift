import CoreGraphics
import Foundation
import VocoAppCore

@MainActor
final class MacHotkeyProvider: HotkeyProviding {
    private var worker: HotkeyEventTapWorker?

    func start(
        binding: HotkeyBinding,
        mode: HotkeyMode,
        onAction: @escaping @MainActor @Sendable (HotkeyAction) -> Void
    ) -> HotkeyRuntimeState {
        stop()

        let worker = HotkeyEventTapWorker(binding: binding, mode: mode, onAction: onAction)
        switch worker.start() {
        case .success:
            self.worker = worker
            return .listening
        case .failure(let message):
            return .failed(message)
        }
    }

    func stop() {
        worker?.stop()
        worker = nil
    }
}

private final class HotkeyEventTapWorker: @unchecked Sendable {
    private let state: HotkeyEventTapState
    private var thread: Thread?
    private var runLoop: CFRunLoop?

    init(
        binding: HotkeyBinding,
        mode: HotkeyMode,
        onAction: @escaping @MainActor @Sendable (HotkeyAction) -> Void
    ) {
        self.state = HotkeyEventTapState(binding: binding, mode: mode, onAction: onAction)
    }

    func start() -> HotkeyEventTapStartResult {
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedStartResult()

        let thread = Thread { [weak self] in
            self?.run(semaphore: semaphore, result: result)
        }
        thread.name = "VocoHotkeyEventTap"
        self.thread = thread
        thread.start()

        if semaphore.wait(timeout: .now() + 2) == .timedOut {
            stop()
            return .failure("hotkey event tap startup timed out")
        }

        return result.value
    }

    func stop() {
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        runLoop = nil
        thread = nil
    }

    private func run(semaphore: DispatchSemaphore, result: LockedStartResult) {
        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let state = Unmanaged<HotkeyEventTapState>.fromOpaque(userInfo).takeUnretainedValue()
            state.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        let userInfo = Unmanaged.passUnretained(state).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: userInfo
        ) else {
            result.value = .failure("CGEventTapCreate returned nil; grant Accessibility and Input Monitoring")
            semaphore.signal()
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            result.value = .failure("failed to create hotkey event tap run loop source")
            semaphore.signal()
            return
        }

        let currentRunLoop = CFRunLoopGetCurrent()
        runLoop = currentRunLoop
        CFRunLoopAddSource(currentRunLoop, source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        result.value = .success
        semaphore.signal()
        CFRunLoopRun()

        CGEvent.tapEnable(tap: eventTap, enable: false)
        CFRunLoopRemoveSource(currentRunLoop, source, .commonModes)
    }
}

private final class HotkeyEventTapState: @unchecked Sendable {
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

    func handle(type: CGEventType, event: CGEvent) {
        guard let kind = HotkeyInputEventKind(type: type) else {
            return
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue
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
    init?(type: CGEventType) {
        switch type {
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

private enum HotkeyEventTapStartResult {
    case success
    case failure(String)
}

private final class LockedStartResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: HotkeyEventTapStartResult = .failure("hotkey event tap did not start")

    var value: HotkeyEventTapStartResult {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}
