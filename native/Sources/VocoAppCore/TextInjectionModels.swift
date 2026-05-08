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

        if supportsClipboardFallback {
            return .clipboardFallback
        }

        if supportsUnicodeEvents {
            return .unicodeEvent
        }

        if supportsDirectAccessibility {
            return .directAccessibility
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
        localizedDescription(strings: VocoStrings())
    }

    public func localizedDescription(strings: VocoStrings) -> String {
        strings.injection.errorDescription(for: self)
    }
}

@MainActor
public protocol TextInsertionClient {
    func currentContext() async -> TextInjectionContext
    func insert(_ text: String, using strategy: TextInjectionStrategy) async throws
}

public final class NativeTextInjectionProvider: TextInjectionProviding {
    private let client: any TextInsertionClient

    public init(client: any TextInsertionClient) {
        self.client = client
    }

    public func insert(_ text: String) async throws -> TextInjectionSnapshot {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return .skippedEmpty
        }

        let context = await client.currentContext()
        guard context.isAccessibilityTrusted else {
            return failedSnapshot(
                context: context,
                strategy: .unavailable,
                error: TextInjectionError.accessibilityPermissionMissing
            )
        }

        guard let strategy = context.preferredStrategy else {
            return failedSnapshot(
                context: context,
                strategy: .unavailable,
                error: TextInjectionError.noSupportedStrategy(targetAppName: context.targetAppName)
            )
        }

        do {
            try await client.insert(text, using: strategy)
            return TextInjectionSnapshot(
                targetAppName: context.targetAppName,
                strategy: strategy,
                succeeded: true,
                detail: successDetail(for: strategy)
            )
        } catch {
            return failedSnapshot(context: context, strategy: strategy, error: error)
        }
    }

    private func failedSnapshot(
        context: TextInjectionContext,
        strategy: TextInjectionStrategy,
        error: Error
    ) -> TextInjectionSnapshot {
        TextInjectionSnapshot(
            targetAppName: context.targetAppName,
            strategy: strategy,
            succeeded: false,
            detail: error.localizedDescription
        )
    }

    private func successDetail(for strategy: TextInjectionStrategy) -> String {
        switch strategy {
        case .directAccessibility:
            "已通过辅助功能直接插入文本。"
        case .unicodeEvent:
            "已通过 Unicode 事件插入文本。"
        case .clipboardFallback:
            "已通过剪贴板回退插入文本并恢复剪贴板。"
        case .unavailable:
            "没有可用的文本插入方式。"
        case .skippedEmpty:
            "Final transcript was empty; skipped text insertion."
        }
    }
}
