import Foundation

public enum TranscriptionCredentialProvider: String, CaseIterable, Identifiable, Sendable {
    case doubao

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .doubao:
            "Doubao"
        }
    }
}

public struct TranscriptionCredentialSnapshot: Equatable, Sendable {
    public let provider: TranscriptionCredentialProvider
    public let hasAPIKey: Bool
    public let maskedAPIKey: String?
    public let storageDetail: String
    public let lastErrorMessage: String?

    public var statusTitle: String {
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            "\(provider.title) 凭证读取失败"
        } else if hasAPIKey {
            "\(provider.title) 凭证已保存"
        } else {
            "\(provider.title) 凭证未保存"
        }
    }

    public static func missing(provider: TranscriptionCredentialProvider) -> TranscriptionCredentialSnapshot {
        TranscriptionCredentialSnapshot(
            provider: provider,
            hasAPIKey: false,
            maskedAPIKey: nil,
            storageDetail: "Keychain 中没有保存 API Key。",
            lastErrorMessage: nil
        )
    }

    public static func stored(
        provider: TranscriptionCredentialProvider,
        apiKey: String
    ) -> TranscriptionCredentialSnapshot {
        TranscriptionCredentialSnapshot(
            provider: provider,
            hasAPIKey: true,
            maskedAPIKey: maskAPIKey(apiKey),
            storageDetail: "API Key 已安全保存在 Keychain。",
            lastErrorMessage: nil
        )
    }

    public static func failed(
        provider: TranscriptionCredentialProvider,
        message: String
    ) -> TranscriptionCredentialSnapshot {
        TranscriptionCredentialSnapshot(
            provider: provider,
            hasAPIKey: false,
            maskedAPIKey: nil,
            storageDetail: "Keychain 访问失败：\(message)",
            lastErrorMessage: message
        )
    }
}

public enum TranscriptionCredentialError: LocalizedError, Equatable, Sendable {
    case emptyAPIKey
    case readFailed(message: String)
    case storeFailed(message: String)
    case deleteFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            "ASR API Key 不能为空。"
        case .readFailed(let message):
            "读取 ASR 凭证失败：\(message)"
        case .storeFailed(let message):
            "保存 ASR 凭证失败：\(message)"
        case .deleteFailed(let message):
            "删除 ASR 凭证失败：\(message)"
        }
    }
}

@MainActor
public protocol TranscriptionCredentialStoring {
    func currentSnapshot() -> TranscriptionCredentialSnapshot
    func saveAPIKey(
        _ apiKey: String,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot
    func deleteCredentials(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredentialSnapshot
    func apiKey(for provider: TranscriptionCredentialProvider) async throws -> String?
}

@MainActor
public final class InMemoryTranscriptionCredentialStore: TranscriptionCredentialStoring {
    private let provider: TranscriptionCredentialProvider
    private var storedAPIKey: String?

    public init(provider: TranscriptionCredentialProvider = .doubao, apiKey: String? = nil) {
        self.provider = provider
        self.storedAPIKey = apiKey
    }

    public func currentSnapshot() -> TranscriptionCredentialSnapshot {
        guard let storedAPIKey, !storedAPIKey.isEmpty else {
            return .missing(provider: provider)
        }

        return .stored(provider: provider, apiKey: storedAPIKey)
    }

    public func saveAPIKey(
        _ apiKey: String,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionCredentialError.emptyAPIKey
        }

        self.storedAPIKey = trimmed
        return .stored(provider: provider, apiKey: trimmed)
    }

    public func deleteCredentials(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredentialSnapshot {
        storedAPIKey = nil
        return .missing(provider: provider)
    }

    public func apiKey(for provider: TranscriptionCredentialProvider) async throws -> String? {
        storedAPIKey
    }
}

private func maskAPIKey(_ apiKey: String) -> String {
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 8 else {
        return String(repeating: "•", count: max(trimmed.count, 4))
    }

    return "\(trimmed.prefix(4))...\(trimmed.suffix(4))"
}
