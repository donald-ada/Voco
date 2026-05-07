import Foundation
import Security
import VocoAppCore

@MainActor
final class MacKeychainCredentialStore: TranscriptionCredentialStoring {
    private let service: String

    init(service: String = "com.voco.app.asr") {
        self.service = service
    }

    func currentSnapshot() -> TranscriptionCredentialSnapshot {
        do {
            guard let credential = try readCredential(for: .volcengine) else {
                return .missing(provider: .volcengine)
            }

            return .stored(provider: .volcengine, credential: credential)
        } catch {
            return .failed(provider: .volcengine, message: error.localizedDescription)
        }
    }

    func saveCredential(
        _ credential: TranscriptionCredential,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot {
        let normalizedCredential = try credential.normalized()
        let data: Data
        do {
            data = try JSONEncoder().encode(normalizedCredential)
        } catch {
            throw TranscriptionCredentialError.storeFailed(message: error.localizedDescription)
        }
        let updateStatus = SecItemUpdate(
            baseQuery(account: keychainAccount(for: provider)) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return .stored(provider: provider, credential: normalizedCredential)
        case errSecItemNotFound:
            var addQuery = baseQuery(account: keychainAccount(for: provider))
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

    func deleteCredentials(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredentialSnapshot {
        for account in keychainAccountsToRead(for: provider) {
            let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw TranscriptionCredentialError.deleteFailed(message: statusMessage(status))
            }
        }

        return .missing(provider: provider)
    }

    func credential(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredential? {
        try readCredential(for: provider)
    }

    private func readCredential(for provider: TranscriptionCredentialProvider) throws -> TranscriptionCredential? {
        for account in keychainAccountsToRead(for: provider) {
            if let credential = try readCredential(account: account) {
                return credential
            }
        }

        return nil
    }

    private func readCredential(account: String) throws -> TranscriptionCredential? {
        var query = baseQuery(account: account)
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

    private func keychainAccount(for provider: TranscriptionCredentialProvider) -> String {
        provider.rawValue
    }

    private func keychainAccountsToRead(for provider: TranscriptionCredentialProvider) -> [String] {
        switch provider {
        case .volcengine:
            ["volcengine", "doubao"]
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func statusMessage(_ status: OSStatus) -> String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "\(message) (\(status))"
    }
}
