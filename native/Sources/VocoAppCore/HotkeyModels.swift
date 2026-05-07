import Foundation

public enum HotkeyMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case toggle
    case pressAndHold

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .toggle:
            "切换录音"
        case .pressAndHold:
            "按住录音"
        }
    }
}

public enum HotkeyPreset: String, CaseIterable, Identifiable, Equatable, Sendable {
    case rightCommand
    case fn
    case capsLock

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rightCommand:
            "Right Command"
        case .fn:
            "Fn"
        case .capsLock:
            "Caps Lock"
        }
    }

    public var binding: HotkeyBinding {
        switch self {
        case .rightCommand:
            .default
        case .fn:
            HotkeyBinding(keyCode: 63, modifierFlags: HotkeyMatcher.fnFlag, displayName: title)
        case .capsLock:
            HotkeyBinding(keyCode: 57, modifierFlags: 0, displayName: title)
        }
    }

    public static func matching(_ binding: HotkeyBinding) -> HotkeyPreset? {
        allCases.first { $0.binding == binding }
    }
}

public struct HotkeyBinding: Equatable, Sendable {
    public static let commandFlag: UInt64 = 0x0010_0000
    public static let rightCommandFlag: UInt64 = commandFlag

    public static let `default` = HotkeyBinding(
        keyCode: 54,
        modifierFlags: 0,
        displayName: "Right Command"
    )

    public let keyCode: UInt16
    public let modifierFlags: UInt64
    public let displayName: String

    public init(keyCode: UInt16, modifierFlags: UInt64, displayName: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.displayName = displayName
    }
}

public enum HotkeyRuntimeState: Equatable, Sendable {
    case inactive
    case listening
    case permissionNeeded
    case failed(String)

    public var title: String {
        switch self {
        case .inactive:
            "未监听"
        case .listening:
            "监听中"
        case .permissionNeeded:
            "需要权限"
        case .failed:
            "出错"
        }
    }

    public var detail: String {
        switch self {
        case .inactive:
            "快捷键监听未启动。"
        case .listening:
            "Voco 正在监听全局快捷键。"
        case .permissionNeeded:
            "需要辅助功能权限才能监听全局快捷键。"
        case .failed(let message):
            message
        }
    }

    public var systemImage: String {
        switch self {
        case .inactive:
            "keyboard"
        case .listening:
            "keyboard.fill"
        case .permissionNeeded:
            "lock.shield"
        case .failed:
            "xmark.octagon"
        }
    }

    public var canReceiveEvents: Bool {
        self == .listening
    }
}

public enum HotkeyAction: Equatable, Sendable {
    case startRecording
    case stopRecording
    case toggleRecording
}

public enum HotkeyInputEventKind: Equatable, Sendable {
    case keyDown
    case keyUp
    case flagsChanged
}

public struct HotkeyInputEvent: Equatable, Sendable {
    public let kind: HotkeyInputEventKind
    public let keyCode: UInt16
    public let modifierFlags: UInt64

    public init(kind: HotkeyInputEventKind, keyCode: UInt16, modifierFlags: UInt64) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
}

public struct HotkeyMatcher: Sendable {
    private static let alphaShiftFlag: UInt64 = 0x0001_0000
    private static let shiftFlag: UInt64 = 0x0002_0000
    private static let controlFlag: UInt64 = 0x0004_0000
    private static let optionFlag: UInt64 = 0x0008_0000
    public static let fnFlag: UInt64 = 0x0080_0000
    private static let matchedModifierMask: UInt64 =
        shiftFlag | controlFlag | optionFlag | HotkeyBinding.commandFlag | fnFlag
    private static let activeModifierMask: UInt64 = matchedModifierMask | alphaShiftFlag

    private let binding: HotkeyBinding
    private let mode: HotkeyMode
    private var pressed: Bool

    public init(binding: HotkeyBinding, mode: HotkeyMode) {
        self.binding = binding
        self.mode = mode
        self.pressed = false
    }

    public mutating func handle(_ event: HotkeyInputEvent) -> HotkeyAction? {
        guard event.keyCode == binding.keyCode else {
            return nil
        }

        switch event.kind {
        case .keyDown:
            guard modifiersMatch(event.modifierFlags) else {
                return nil
            }
            return emitPressAction()
        case .keyUp:
            return releaseAction()
        case .flagsChanged:
            if flagsActive(event.modifierFlags) {
                return emitPressAction()
            }
            return releaseAction()
        }
    }

    private mutating func emitPressAction() -> HotkeyAction? {
        guard !pressed else {
            return nil
        }

        pressed = true
        switch mode {
        case .toggle:
            return .toggleRecording
        case .pressAndHold:
            return .startRecording
        }
    }

    private mutating func releaseAction() -> HotkeyAction? {
        guard pressed else {
            return nil
        }

        pressed = false
        switch mode {
        case .toggle:
            return nil
        case .pressAndHold:
            return .stopRecording
        }
    }

    private func modifiersMatch(_ flags: UInt64) -> Bool {
        (flags & Self.matchedModifierMask) == binding.modifierFlags
    }

    private func flagsActive(_ flags: UInt64) -> Bool {
        if binding.modifierFlags == 0 {
            return (flags & Self.activeModifierMask) != 0
        }

        return modifiersMatch(flags)
    }
}

@MainActor
public protocol HotkeyProviding: AnyObject {
    func start(
        binding: HotkeyBinding,
        mode: HotkeyMode,
        onAction: @escaping @MainActor @Sendable (HotkeyAction) -> Void
    ) -> HotkeyRuntimeState

    func stop()
}

@MainActor
public final class StaticHotkeyProvider: HotkeyProviding {
    private let state: HotkeyRuntimeState

    public init(state: HotkeyRuntimeState = .inactive) {
        self.state = state
    }

    public func start(
        binding: HotkeyBinding,
        mode: HotkeyMode,
        onAction: @escaping @MainActor @Sendable (HotkeyAction) -> Void
    ) -> HotkeyRuntimeState {
        state
    }

    public func stop() {}
}
