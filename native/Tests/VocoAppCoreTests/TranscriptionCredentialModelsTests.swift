import XCTest
@testable import VocoAppCore

final class TranscriptionCredentialModelsTests: XCTestCase {
    func testStoredSnapshotMasksAPIKey() {
        let snapshot = TranscriptionCredentialSnapshot.stored(
            provider: .doubao,
            apiKey: "sk-test-1234567890"
        )

        XCTAssertEqual(snapshot.provider.title, "Doubao")
        XCTAssertTrue(snapshot.hasCredential)
        XCTAssertTrue(snapshot.hasAPIKey)
        XCTAssertEqual(snapshot.mode, .apiKey)
        XCTAssertEqual(snapshot.maskedCredential, "sk-t...7890")
        XCTAssertEqual(snapshot.maskedAPIKey, "sk-t...7890")
        XCTAssertEqual(snapshot.statusTitle, "Doubao 凭证已保存")
        XCTAssertNil(snapshot.lastErrorMessage)
    }

    func testStoredSnapshotDescribesLegacyDoubaoCredentialMode() {
        let snapshot = TranscriptionCredentialSnapshot.stored(
            provider: .doubao,
            credential: .doubaoAppIDAccessToken(
                appID: "3145608744",
                accessToken: "legacy-token"
            )
        )

        XCTAssertTrue(snapshot.hasCredential)
        XCTAssertFalse(snapshot.hasAPIKey)
        XCTAssertEqual(snapshot.mode, .appIDAccessToken)
        XCTAssertEqual(snapshot.maskedCredential, "App ID 3145...8744 · Token lega...oken")
        XCTAssertNil(snapshot.maskedAPIKey)
        XCTAssertEqual(snapshot.statusTitle, "Doubao 凭证已保存")
        XCTAssertEqual(snapshot.storageDetail, "旧控制台 App ID + Token 已安全保存在 Keychain。")
    }

    func testMissingAndFailedSnapshotsAreUserVisible() {
        let missing = TranscriptionCredentialSnapshot.missing(provider: .doubao)
        XCTAssertFalse(missing.hasCredential)
        XCTAssertFalse(missing.hasAPIKey)
        XCTAssertEqual(missing.statusTitle, "Doubao 凭证未保存")
        XCTAssertEqual(missing.storageDetail, "Keychain 中没有保存 Doubao 凭证。")

        let failed = TranscriptionCredentialSnapshot.failed(provider: .doubao, message: "read failed")
        XCTAssertFalse(failed.hasCredential)
        XCTAssertFalse(failed.hasAPIKey)
        XCTAssertEqual(failed.statusTitle, "Doubao 凭证读取失败")
        XCTAssertEqual(failed.lastErrorMessage, "read failed")
    }

    func testCredentialErrorsAreLocalized() {
        XCTAssertEqual(
            TranscriptionCredentialError.emptyAPIKey.localizedDescription,
            "ASR API Key 不能为空。"
        )
        XCTAssertEqual(
            TranscriptionCredentialError.emptyAppIDAccessToken.localizedDescription,
            "Doubao App ID 和 Access Token 不能为空。"
        )
        XCTAssertEqual(
            TranscriptionCredentialError.storeFailed(message: "OSStatus -50").localizedDescription,
            "保存 ASR 凭证失败：OSStatus -50"
        )
    }

    @MainActor
    func testInMemoryCredentialStoreSavesAndDeletesKey() async throws {
        let store = InMemoryTranscriptionCredentialStore()

        XCTAssertEqual(store.currentSnapshot(), .missing(provider: .doubao))

        let stored = try await store.saveAPIKey("  sk-test-abcdef  ", for: .doubao)
        XCTAssertTrue(stored.hasCredential)
        XCTAssertTrue(stored.hasAPIKey)
        let savedAPIKey = try await store.apiKey(for: .doubao)
        XCTAssertEqual(savedAPIKey, "sk-test-abcdef")

        let missing = try await store.deleteCredentials(for: .doubao)
        XCTAssertEqual(missing, .missing(provider: .doubao))
        let deletedAPIKey = try await store.apiKey(for: .doubao)
        XCTAssertNil(deletedAPIKey)
    }

    @MainActor
    func testInMemoryCredentialStoreSavesLegacyDoubaoCredential() async throws {
        let store = InMemoryTranscriptionCredentialStore()

        let stored = try await store.saveCredential(
            .doubaoAppIDAccessToken(
                appID: "  3145608744  ",
                accessToken: "  legacy-token  "
            ),
            for: .doubao
        )

        XCTAssertTrue(stored.hasCredential)
        XCTAssertFalse(stored.hasAPIKey)
        XCTAssertEqual(stored.mode, .appIDAccessToken)
        let credential = try await store.credential(for: .doubao)
        XCTAssertEqual(credential?.appID, "3145608744")
        XCTAssertEqual(credential?.accessToken, "legacy-token")
        let apiKey = try await store.apiKey(for: .doubao)
        XCTAssertNil(apiKey)
    }
}
