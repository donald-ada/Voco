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
            guard let apiKey = try readAPIKey(for: .doubao) else {
                return .missing(provider: .doubao)
            }

            return .stored(provider: .doubao, apiKey: apiKey)
        } catch {
            return .failed(provider: .doubao, message: error.localizedDescription)
        }
    }

    func saveAPIKey(
        _ apiKey: String,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionCredentialError.emptyAPIKey
        }

        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(for: provider) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return .stored(provider: provider, apiKey: trimmed)
        case errSecItemNotFound:
            var addQuery = baseQuery(for: provider)
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TranscriptionCredentialError.storeFailed(message: statusMessage(addStatus))
            }

            return .stored(provider: provider, apiKey: trimmed)
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

    func apiKey(for provider: TranscriptionCredentialProvider) async throws -> String? {
        try readAPIKey(for: provider)
    }

    private func readAPIKey(for provider: TranscriptionCredentialProvider) throws -> String? {
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
            guard let apiKey = String(data: data, encoding: .utf8) else {
                throw TranscriptionCredentialError.readFailed(message: "Keychain 返回的数据不是 UTF-8 文本。")
            }
            return apiKey
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
