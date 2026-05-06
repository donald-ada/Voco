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
            guard let credential = try readCredential(for: .doubao) else {
                return .missing(provider: .doubao)
            }

            return .stored(provider: .doubao, credential: credential)
        } catch {
            return .failed(provider: .doubao, message: error.localizedDescription)
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
            baseQuery(for: provider) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return .stored(provider: provider, credential: normalizedCredential)
        case errSecItemNotFound:
            var addQuery = baseQuery(for: provider)
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
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TranscriptionCredentialError.deleteFailed(message: statusMessage(status))
        }

        return .missing(provider: provider)
    }

    func credential(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredential? {
        try readCredential(for: provider)
    }

    private func readCredential(for provider: TranscriptionCredentialProvider) throws -> TranscriptionCredential? {
        var query = baseQuery(for: provider)
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

            return .doubaoAPIKey(trimmedLegacyAPIKey)
        case errSecItemNotFound:
            return nil
        default:
            throw TranscriptionCredentialError.readFailed(message: statusMessage(status))
        }
    }

    private func baseQuery(for provider: TranscriptionCredentialProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
    }

    private func statusMessage(_ status: OSStatus) -> String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "\(message) (\(status))"
    }
}
