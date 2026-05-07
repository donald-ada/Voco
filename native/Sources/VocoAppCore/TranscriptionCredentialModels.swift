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

public enum DoubaoCredentialMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case apiKey
    case appIDAccessToken

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .apiKey:
            "新网关 API Key"
        case .appIDAccessToken:
            "旧控制台 App ID + Token"
        }
    }

    public var detail: String {
        switch self {
        case .apiKey:
            "使用 Authorization: Bearer 连接新网关 Realtime ASR。"
        case .appIDAccessToken:
            "使用 X-Api-App-Key 和 X-Api-Access-Key 连接 OpenSpeech 流式 ASR。"
        }
    }
}

public struct TranscriptionCredential: Codable, Equatable, Sendable {
    public let mode: DoubaoCredentialMode
    public let apiKey: String?
    public let appID: String?
    public let accessToken: String?

    public init(
        mode: DoubaoCredentialMode,
        apiKey: String? = nil,
        appID: String? = nil,
        accessToken: String? = nil
    ) {
        self.mode = mode
        self.apiKey = apiKey
        self.appID = appID
        self.accessToken = accessToken
    }

    public static func doubaoAPIKey(_ apiKey: String) -> TranscriptionCredential {
        TranscriptionCredential(mode: .apiKey, apiKey: apiKey)
    }

    public static func doubaoAppIDAccessToken(
        appID: String,
        accessToken: String
    ) -> TranscriptionCredential {
        TranscriptionCredential(
            mode: .appIDAccessToken,
            appID: appID,
            accessToken: accessToken
        )
    }

    public func normalized() throws -> TranscriptionCredential {
        switch mode {
        case .apiKey:
            let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedAPIKey.isEmpty else {
                throw TranscriptionCredentialError.emptyAPIKey
            }

            return .doubaoAPIKey(trimmedAPIKey)
        case .appIDAccessToken:
            let trimmedAppID = appID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let trimmedAccessToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedAppID.isEmpty, !trimmedAccessToken.isEmpty else {
                throw TranscriptionCredentialError.emptyAppIDAccessToken
            }

            return .doubaoAppIDAccessToken(
                appID: trimmedAppID,
                accessToken: trimmedAccessToken
            )
        }
    }
}

public struct TranscriptionCredentialSnapshot: Equatable, Sendable {
    public let provider: TranscriptionCredentialProvider
    public let hasCredential: Bool
    public let mode: DoubaoCredentialMode?
    public let maskedCredential: String?
    public let hasAPIKey: Bool
    public let maskedAPIKey: String?
    public let storageDetail: String
    public let lastErrorMessage: String?

    public var statusTitle: String {
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            "\(provider.title) 凭证读取失败"
        } else if hasCredential {
            "\(provider.title) 凭证已保存"
        } else {
            "\(provider.title) 凭证未保存"
        }
    }

    public static func missing(provider: TranscriptionCredentialProvider) -> TranscriptionCredentialSnapshot {
        return TranscriptionCredentialSnapshot(
            provider: provider,
            hasCredential: false,
            mode: nil,
            maskedCredential: nil,
            hasAPIKey: false,
            maskedAPIKey: nil,
            storageDetail: "Keychain 中没有保存 Doubao 凭证。",
            lastErrorMessage: nil
        )
    }

    public static func stored(
        provider: TranscriptionCredentialProvider,
        apiKey: String
    ) -> TranscriptionCredentialSnapshot {
        stored(provider: provider, credential: .doubaoAPIKey(apiKey))
    }

    public static func stored(
        provider: TranscriptionCredentialProvider,
        credential: TranscriptionCredential
    ) -> TranscriptionCredentialSnapshot {
        let normalizedCredential = (try? credential.normalized()) ?? credential
        let mode = normalizedCredential.mode
        let maskedCredential = maskCredential(normalizedCredential)

        return TranscriptionCredentialSnapshot(
            provider: provider,
            hasCredential: true,
            mode: mode,
            maskedCredential: maskedCredential,
            hasAPIKey: mode == .apiKey,
            maskedAPIKey: mode == .apiKey ? maskedCredential : nil,
            storageDetail: "\(mode.title) 已安全保存在 Keychain。",
            lastErrorMessage: nil
        )
    }

    public static func failed(
        provider: TranscriptionCredentialProvider,
        message: String
    ) -> TranscriptionCredentialSnapshot {
        TranscriptionCredentialSnapshot(
            provider: provider,
            hasCredential: false,
            mode: nil,
            maskedCredential: nil,
            hasAPIKey: false,
            maskedAPIKey: nil,
            storageDetail: "Keychain 访问失败：\(message)",
            lastErrorMessage: message
        )
    }
}

public enum TranscriptionCredentialError: LocalizedError, Equatable, Sendable {
    case emptyAPIKey
    case emptyAppIDAccessToken
    case readFailed(message: String)
    case storeFailed(message: String)
    case deleteFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            "ASR API Key 不能为空。"
        case .emptyAppIDAccessToken:
            "Doubao App ID 和 Access Token 不能为空。"
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
    func saveCredential(
        _ credential: TranscriptionCredential,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot
    func deleteCredentials(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredentialSnapshot
    func credential(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredential?
}

public extension TranscriptionCredentialStoring {
    func saveAPIKey(
        _ apiKey: String,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot {
        try await saveCredential(.doubaoAPIKey(apiKey), for: provider)
    }

    func apiKey(for provider: TranscriptionCredentialProvider) async throws -> String? {
        guard let credential = try await credential(for: provider), credential.mode == .apiKey else {
            return nil
        }

        return try credential.normalized().apiKey
    }
}

@MainActor
public final class InMemoryTranscriptionCredentialStore: TranscriptionCredentialStoring {
    private let provider: TranscriptionCredentialProvider
    private var storedCredential: TranscriptionCredential?

    public init(
        provider: TranscriptionCredentialProvider = .doubao,
        apiKey: String? = nil,
        credential: TranscriptionCredential? = nil
    ) {
        self.provider = provider
        self.storedCredential = credential ?? apiKey.map(TranscriptionCredential.doubaoAPIKey)
    }

    public func currentSnapshot() -> TranscriptionCredentialSnapshot {
        guard let storedCredential else {
            return .missing(provider: provider)
        }

        return .stored(provider: provider, credential: storedCredential)
    }

    public func saveCredential(
        _ credential: TranscriptionCredential,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot {
        let normalizedCredential = try credential.normalized()

        self.storedCredential = normalizedCredential
        return .stored(provider: provider, credential: normalizedCredential)
    }

    public func deleteCredentials(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredentialSnapshot {
        storedCredential = nil
        return .missing(provider: provider)
    }

    public func credential(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredential? {
        storedCredential
    }
}

private func maskCredential(_ credential: TranscriptionCredential) -> String? {
    switch credential.mode {
    case .apiKey:
        return credential.apiKey.map(maskSecret)
    case .appIDAccessToken:
        let appID = credential.appID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let accessToken = credential.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !appID.isEmpty, !accessToken.isEmpty else {
            return nil
        }

        return "App ID \(maskSecret(appID)) · Token \(maskSecret(accessToken))"
    }
}

private func maskSecret(_ secret: String) -> String {
    let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 8 else {
        return String(repeating: "•", count: max(trimmed.count, 4))
    }

    return "\(trimmed.prefix(4))...\(trimmed.suffix(4))"
}
