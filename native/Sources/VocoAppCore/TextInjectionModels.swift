import Foundation

public enum TextInjectionStrategy: Equatable, Sendable {
    case directAccessibility
    case unicodeEvent
    case clipboardFallback
    case unavailable
    case skippedEmpty

    public var title: String {
        switch self {
        case .directAccessibility:
            "辅助功能直接插入"
        case .unicodeEvent:
            "Unicode 事件"
        case .clipboardFallback:
            "剪贴板回退"
        case .unavailable:
            "不可用"
        case .skippedEmpty:
            "空文本跳过"
        }
    }
}

public struct TextInjectionSnapshot: Equatable, Sendable {
    public let targetAppName: String?
    public let strategy: TextInjectionStrategy
    public let succeeded: Bool
    public let detail: String

    public init(targetAppName: String?, strategy: TextInjectionStrategy, succeeded: Bool, detail: String) {
        self.targetAppName = targetAppName
        self.strategy = strategy
        self.succeeded = succeeded
        self.detail = detail
    }

    public static var skippedEmpty: TextInjectionSnapshot {
        TextInjectionSnapshot(
            targetAppName: nil,
            strategy: .skippedEmpty,
            succeeded: true,
            detail: "Final transcript was empty; skipped text insertion."
        )
    }
}

public struct TextInjectionContext: Equatable, Sendable {
    public let targetAppName: String?
    public let isAccessibilityTrusted: Bool
    public let supportsDirectAccessibility: Bool
    public let supportsUnicodeEvents: Bool
    public let supportsClipboardFallback: Bool

    public init(
        targetAppName: String?,
        isAccessibilityTrusted: Bool,
        supportsDirectAccessibility: Bool,
        supportsUnicodeEvents: Bool,
        supportsClipboardFallback: Bool
    ) {
        self.targetAppName = targetAppName
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.supportsDirectAccessibility = supportsDirectAccessibility
        self.supportsUnicodeEvents = supportsUnicodeEvents
        self.supportsClipboardFallback = supportsClipboardFallback
    }

    public var preferredStrategy: TextInjectionStrategy? {
        guard isAccessibilityTrusted else {
            return nil
        }

        if supportsDirectAccessibility {
            return .directAccessibility
        }

        if supportsUnicodeEvents {
            return .unicodeEvent
        }

        if supportsClipboardFallback {
            return .clipboardFallback
        }

        return nil
    }
}

public enum TextInjectionError: LocalizedError, Equatable, Sendable {
    case accessibilityPermissionMissing
    case noSupportedStrategy(targetAppName: String?)
    case insertionFailed(strategy: TextInjectionStrategy, message: String)
    case clipboardUnavailable(message: String)
    case clipboardRestoreFailed(message: String)
    case eventPostFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "无法插入文本：请先在系统设置中允许 Voco 使用辅助功能。"
        case .noSupportedStrategy(let targetAppName):
            "无法插入文本：\(targetAppName ?? "当前 App") 没有可用的文本插入方式。"
        case .insertionFailed(let strategy, let message):
            "\(strategy.title)失败：\(message)"
        case .clipboardUnavailable(let message):
            "剪贴板不可用：\(message)"
        case .clipboardRestoreFailed(let message):
            "剪贴板回退后恢复原剪贴板失败：\(message)"
        case .eventPostFailed(let message):
            "Unicode 事件发送失败：\(message)"
        }
    }
}
