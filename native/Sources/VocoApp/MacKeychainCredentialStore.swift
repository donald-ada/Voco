import Foundation
import Security
import VocoAppCore

@MainActor
final class MacKeychainCredentialStore: TranscriptionCredentialStoring {
    private let service: String
    private var cachedSnapshot: TranscriptionCredentialSnapshot?

    init(service: String = "com.voco.app.asr") {
        self.service = service
    }

    func currentSnapshot() -> TranscriptionCredentialSnapshot {
        cachedSnapshot ?? .missing(provider: .volcengine)
    }

    func loadCurrentSnapshot() async -> TranscriptionCredentialSnapshot {
        let service = service
        let snapshot = await Self.performOnCredentialQueue {
            Self.currentSnapshot(service: service)
        }
        cachedSnapshot = snapshot
        return snapshot
    }

    func saveCredential(
        _ credential: TranscriptionCredential,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot {
        let normalizedCredential = try credential.normalized()
        let service = service
        let snapshot = try await Self.performOnCredentialQueue {
            try Self.saveCredentialSync(normalizedCredential, for: provider, service: service)
        }
        cachedSnapshot = snapshot
        return snapshot
    }

    func deleteCredentials(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredentialSnapshot {
        let service = service
        let snapshot = try await Self.performOnCredentialQueue {
            try Self.deleteCredentialsSync(for: provider, service: service)
        }
        cachedSnapshot = snapshot
        return snapshot
    }

    func credential(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredential? {
        let service = service
        return try await Self.performOnCredentialQueue {
            try Self.readCredential(for: provider, service: service)
        }
    }

    private nonisolated static func currentSnapshot(service: String) -> TranscriptionCredentialSnapshot {
        do {
            guard let credential = try readCredential(for: .volcengine, service: service) else {
                return .missing(provider: .volcengine)
            }

            return .stored(provider: .volcengine, credential: credential)
        } catch {
            return .failed(provider: .volcengine, message: error.localizedDescription)
        }
    }

    private nonisolated static func saveCredentialSync(
        _ normalizedCredential: TranscriptionCredential,
        for provider: TranscriptionCredentialProvider,
        service: String
    ) throws -> TranscriptionCredentialSnapshot {
        let data: Data
        do {
            data = try JSONEncoder().encode(normalizedCredential)
        } catch {
            throw TranscriptionCredentialError.storeFailed(message: error.localizedDescription)
        }
        let updateStatus = SecItemUpdate(
            baseQuery(account: keychainAccount(for: provider), service: service) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return .stored(provider: provider, credential: normalizedCredential)
        case errSecItemNotFound:
            var addQuery = baseQuery(account: keychainAccount(for: provider), service: service)
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TranscriptionCredentialError.storeFailed(message: statusMessage(addStatus))
            }

            return .stored(provider: provider, credential: normalizedCredential)
        default:
            throw TranscriptionCredentialError.storeFailed(message: statusMessage(updateStatus))
        }
    }

    private nonisolated static func deleteCredentialsSync(
        for provider: TranscriptionCredentialProvider,
        service: String
    ) throws -> TranscriptionCredentialSnapshot {
        for account in keychainAccountsToRead(for: provider) {
            let status = SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw TranscriptionCredentialError.deleteFailed(message: statusMessage(status))
            }
        }

        return .missing(provider: provider)
    }

    private nonisolated static func readCredential(
        for provider: TranscriptionCredentialProvider,
        service: String
    ) throws -> TranscriptionCredential? {
        for account in keychainAccountsToRead(for: provider) {
            if let credential = try readCredential(account: account, service: service) {
                return credential
            }
        }

        return nil
    }

    private nonisolated static func readCredential(account: String, service: String) throws -> TranscriptionCredential? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw TranscriptionCredentialError.readFailed(message: "Keychain 返回的数据格式无效。")
            }

            if let credential = try? JSONDecoder().decode(TranscriptionCredential.self, from: data) {
                return try credential.normalized()
            }

            guard let legacyAPIKey = String(data: data, encoding: .utf8) else {
                throw TranscriptionCredentialError.readFailed(message: "Keychain 返回的数据不是 JSON 或 UTF-8 文本。")
            }
            let trimmedLegacyAPIKey = legacyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLegacyAPIKey.isEmpty else {
                return nil
            }

            return .volcengineAPIKey(trimmedLegacyAPIKey)
        case errSecItemNotFound:
            return nil
        default:
            throw TranscriptionCredentialError.readFailed(message: statusMessage(status))
        }
    }

    private nonisolated static func keychainAccount(for provider: TranscriptionCredentialProvider) -> String {
        provider.rawValue
    }

    private nonisolated static func keychainAccountsToRead(for provider: TranscriptionCredentialProvider) -> [String] {
        switch provider {
        case .volcengine:
            ["volcengine", "doubao"]
        }
    }

    private nonisolated static func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private nonisolated static func statusMessage(_ status: OSStatus) -> String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "\(message) (\(status))"
    }

    private nonisolated static func performOnCredentialQueue<T: Sendable>(
        _ operation: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: operation())
            }
        }
    }

    private nonisolated static func performOnCredentialQueue<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
