import Foundation

public enum TranscriptionCredentialProvider: String, CaseIterable, Identifiable, Sendable {
    case volcengine

    public var id: String { rawValue }

    public var title: String {
        title(strings: VocoStrings())
    }

    public func title(strings: VocoStrings) -> String {
        switch self {
        case .volcengine:
            strings.credentials.volcengineTitle
        }
    }
}

public enum VolcengineCredentialMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case apiKey
    case appIDAccessToken

    public var id: String { rawValue }

    public var title: String {
        title(strings: VocoStrings())
    }

    public func title(strings: VocoStrings) -> String {
        switch self {
        case .apiKey:
            strings.credentials.apiKeyModeTitle
        case .appIDAccessToken:
            strings.credentials.appIDAccessTokenModeTitle
        }
    }

    public var detail: String {
        detail(strings: VocoStrings())
    }

    public func detail(strings: VocoStrings) -> String {
        switch self {
        case .apiKey:
            strings.credentials.apiKeyModeDetail
        case .appIDAccessToken:
            strings.credentials.appIDAccessTokenModeDetail
        }
    }
}

public struct TranscriptionCredential: Codable, Equatable, Sendable {
    public let mode: VolcengineCredentialMode
    public let apiKey: String?
    public let appID: String?
    public let accessToken: String?

    public init(
        mode: VolcengineCredentialMode,
        apiKey: String? = nil,
        appID: String? = nil,
        accessToken: String? = nil
    ) {
        self.mode = mode
        self.apiKey = apiKey
        self.appID = appID
        self.accessToken = accessToken
    }

    public static func volcengineAPIKey(_ apiKey: String) -> TranscriptionCredential {
        TranscriptionCredential(mode: .apiKey, apiKey: apiKey)
    }

    public static func volcengineAppIDAccessToken(
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

            return .volcengineAPIKey(trimmedAPIKey)
        case .appIDAccessToken:
            let trimmedAppID = appID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let trimmedAccessToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedAppID.isEmpty, !trimmedAccessToken.isEmpty else {
                throw TranscriptionCredentialError.emptyAppIDAccessToken
            }

            return .volcengineAppIDAccessToken(
                appID: trimmedAppID,
                accessToken: trimmedAccessToken
            )
        }
    }
}

public struct TranscriptionCredentialSnapshot: Equatable, Sendable {
    public let provider: TranscriptionCredentialProvider
    public let hasCredential: Bool
    public let mode: VolcengineCredentialMode?
    public let maskedCredential: String?
    public let hasAPIKey: Bool
    public let maskedAPIKey: String?
    public let storageDetail: String
    public let lastErrorMessage: String?

    public var statusTitle: String {
        statusTitle(strings: VocoStrings())
    }

    public func statusTitle(strings: VocoStrings) -> String {
        strings.credentials.statusTitle(
            provider: provider,
            hasCredential: hasCredential,
            lastErrorMessage: lastErrorMessage
        )
    }

    public static func missing(
        provider: TranscriptionCredentialProvider,
        strings: VocoStrings = VocoStrings()
    ) -> TranscriptionCredentialSnapshot {
        return TranscriptionCredentialSnapshot(
            provider: provider,
            hasCredential: false,
            mode: nil,
            maskedCredential: nil,
            hasAPIKey: false,
            maskedAPIKey: nil,
            storageDetail: strings.credentials.missingStorageDetail,
            lastErrorMessage: nil
        )
    }

    public static func stored(
        provider: TranscriptionCredentialProvider,
        apiKey: String,
        strings: VocoStrings = VocoStrings()
    ) -> TranscriptionCredentialSnapshot {
        stored(provider: provider, credential: .volcengineAPIKey(apiKey), strings: strings)
    }

    public static func stored(
        provider: TranscriptionCredentialProvider,
        credential: TranscriptionCredential,
        strings: VocoStrings = VocoStrings()
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
            storageDetail: strings.credentials.storedStorageDetail(mode: mode),
            lastErrorMessage: nil
        )
    }

    public static func failed(
        provider: TranscriptionCredentialProvider,
        message: String,
        strings: VocoStrings = VocoStrings()
    ) -> TranscriptionCredentialSnapshot {
        TranscriptionCredentialSnapshot(
            provider: provider,
            hasCredential: false,
            mode: nil,
            maskedCredential: nil,
            hasAPIKey: false,
            maskedAPIKey: nil,
            storageDetail: strings.credentials.failedStorageDetail(message: message),
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
            "火山引擎 App ID 和 Access Token 不能为空。"
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
    func loadCurrentSnapshot() async -> TranscriptionCredentialSnapshot
    func saveCredential(
        _ credential: TranscriptionCredential,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot
    func deleteCredentials(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredentialSnapshot
    func credential(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredential?
}

public extension TranscriptionCredentialStoring {
    func loadCurrentSnapshot() async -> TranscriptionCredentialSnapshot {
        currentSnapshot()
    }

    func saveAPIKey(
        _ apiKey: String,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot {
        try await saveCredential(.volcengineAPIKey(apiKey), for: provider)
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
        provider: TranscriptionCredentialProvider = .volcengine,
        apiKey: String? = nil,
        credential: TranscriptionCredential? = nil
    ) {
        self.provider = provider
        self.storedCredential = credential ?? apiKey.map(TranscriptionCredential.volcengineAPIKey)
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
