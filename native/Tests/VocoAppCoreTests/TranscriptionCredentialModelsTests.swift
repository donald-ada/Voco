import XCTest
@testable import VocoAppCore

final class TranscriptionCredentialModelsTests: XCTestCase {
    func testTranscriptionCredentialSnapshotUsesEnglishCopy() {
        let snapshot = TranscriptionCredentialSnapshot.missing(
            provider: .volcengine,
            strings: VocoStrings(language: .en)
        )

        XCTAssertEqual(snapshot.provider.title(strings: VocoStrings(language: .en)), "Volcengine")
        XCTAssertEqual(VolcengineCredentialMode.apiKey.title(strings: VocoStrings(language: .en)), "New Console API Key")
        XCTAssertEqual(
            VolcengineCredentialMode.appIDAccessToken.detail(strings: VocoStrings(language: .en)),
            "Use X-Api-App-Key and X-Api-Access-Key to connect to OpenSpeech streaming ASR."
        )
        XCTAssertEqual(snapshot.statusTitle(strings: VocoStrings(language: .en)), "Volcengine credentials not saved")
        XCTAssertEqual(snapshot.storageDetail, "No Volcengine credentials are saved in Keychain.")
    }

    func testStoredSnapshotMasksAPIKey() {
        let snapshot = TranscriptionCredentialSnapshot.stored(
            provider: .volcengine,
            apiKey: "sk-test-1234567890"
        )

        XCTAssertEqual(snapshot.provider.title, "火山引擎")
        XCTAssertTrue(snapshot.hasCredential)
        XCTAssertTrue(snapshot.hasAPIKey)
        XCTAssertEqual(snapshot.mode, .apiKey)
        XCTAssertEqual(snapshot.maskedCredential, "sk-t...7890")
        XCTAssertEqual(snapshot.maskedAPIKey, "sk-t...7890")
        XCTAssertEqual(snapshot.statusTitle, "火山引擎凭证已保存")
        XCTAssertNil(snapshot.lastErrorMessage)
    }

    func testStoredSnapshotDescribesLegacyVolcengineCredentialMode() {
        let snapshot = TranscriptionCredentialSnapshot.stored(
            provider: .volcengine,
            credential: .volcengineAppIDAccessToken(
                appID: "3145608744",
                accessToken: "legacy-token"
            )
        )

        XCTAssertTrue(snapshot.hasCredential)
        XCTAssertFalse(snapshot.hasAPIKey)
        XCTAssertEqual(snapshot.mode, .appIDAccessToken)
        XCTAssertEqual(snapshot.maskedCredential, "App ID 3145...8744 · Token lega...oken")
        XCTAssertNil(snapshot.maskedAPIKey)
        XCTAssertEqual(snapshot.statusTitle, "火山引擎凭证已保存")
        XCTAssertEqual(snapshot.storageDetail, "旧控制台 App ID + Token 已安全保存在 Keychain。")
    }

    func testMissingAndFailedSnapshotsAreUserVisible() {
        let missing = TranscriptionCredentialSnapshot.missing(provider: .volcengine)
        XCTAssertFalse(missing.hasCredential)
        XCTAssertFalse(missing.hasAPIKey)
        XCTAssertEqual(missing.statusTitle, "火山引擎凭证未保存")
        XCTAssertEqual(missing.storageDetail, "Keychain 中没有保存火山引擎凭证。")

        let failed = TranscriptionCredentialSnapshot.failed(provider: .volcengine, message: "read failed")
        XCTAssertFalse(failed.hasCredential)
        XCTAssertFalse(failed.hasAPIKey)
        XCTAssertEqual(failed.statusTitle, "火山引擎凭证读取失败")
        XCTAssertEqual(failed.lastErrorMessage, "read failed")
    }

    func testCredentialErrorsAreLocalized() {
        XCTAssertEqual(
            TranscriptionCredentialError.emptyAPIKey.localizedDescription,
            "ASR API Key 不能为空。"
        )
        XCTAssertEqual(
            TranscriptionCredentialError.emptyAppIDAccessToken.localizedDescription,
            "火山引擎 App ID 和 Access Token 不能为空。"
        )
        XCTAssertEqual(
            TranscriptionCredentialError.storeFailed(message: "OSStatus -50").localizedDescription,
            "保存 ASR 凭证失败：OSStatus -50"
        )
    }

    func testCredentialErrorsCanRenderKnownAppGeneratedDetailsInEnglish() {
        let strings = VocoStrings(language: .en)

        XCTAssertEqual(
            TranscriptionCredentialError.readFailed(message: "Keychain 返回的数据格式无效。")
                .localizedDescription(strings: strings),
            "Unable to read ASR credentials: Keychain returned data in an invalid format."
        )
        XCTAssertEqual(
            TranscriptionCredentialError.readFailed(message: "Keychain 返回的数据不是 JSON 或 UTF-8 文本。")
                .localizedDescription(strings: strings),
            "Unable to read ASR credentials: Keychain returned data that was not JSON or UTF-8 text."
        )
    }

    func testCredentialErrorsCanRenderEnglishDescription() {
        let strings = VocoStrings(language: .en)

        XCTAssertEqual(
            TranscriptionCredentialError.emptyAPIKey.localizedDescription(strings: strings),
            "ASR API Key cannot be empty."
        )
        XCTAssertEqual(
            TranscriptionCredentialError.emptyAppIDAccessToken.localizedDescription(strings: strings),
            "Volcengine App ID and Access Token cannot be empty."
        )
        XCTAssertEqual(
            TranscriptionCredentialError.readFailed(message: "read failed").localizedDescription(strings: strings),
            "Unable to read ASR credentials: read failed"
        )
        XCTAssertEqual(
            TranscriptionCredentialError.storeFailed(message: "OSStatus -50").localizedDescription(strings: strings),
            "Unable to save ASR credentials: OSStatus -50"
        )
        XCTAssertEqual(
            TranscriptionCredentialError.deleteFailed(message: "delete failed").localizedDescription(strings: strings),
            "Unable to delete ASR credentials: delete failed"
        )
        XCTAssertEqual(
            TranscriptionCredentialError.storeFailed(message: "OSStatus -50").localizedDescription,
            "保存 ASR 凭证失败：OSStatus -50"
        )
    }

    @MainActor
    func testInMemoryCredentialStoreSavesAndDeletesKey() async throws {
        let store = InMemoryTranscriptionCredentialStore()

        XCTAssertEqual(store.currentSnapshot(), .missing(provider: .volcengine))

        let stored = try await store.saveAPIKey("  sk-test-abcdef  ", for: .volcengine)
        XCTAssertTrue(stored.hasCredential)
        XCTAssertTrue(stored.hasAPIKey)
        let savedAPIKey = try await store.apiKey(for: .volcengine)
        XCTAssertEqual(savedAPIKey, "sk-test-abcdef")

        let missing = try await store.deleteCredentials(for: .volcengine)
        XCTAssertEqual(missing, .missing(provider: .volcengine))
        let deletedAPIKey = try await store.apiKey(for: .volcengine)
        XCTAssertNil(deletedAPIKey)
    }

    @MainActor
    func testInMemoryCredentialStoreSavesLegacyVolcengineCredential() async throws {
        let store = InMemoryTranscriptionCredentialStore()

        let stored = try await store.saveCredential(
            .volcengineAppIDAccessToken(
                appID: "  3145608744  ",
                accessToken: "  legacy-token  "
            ),
            for: .volcengine
        )

        XCTAssertTrue(stored.hasCredential)
        XCTAssertFalse(stored.hasAPIKey)
        XCTAssertEqual(stored.mode, .appIDAccessToken)
        let credential = try await store.credential(for: .volcengine)
        XCTAssertEqual(credential?.appID, "3145608744")
        XCTAssertEqual(credential?.accessToken, "legacy-token")
        let apiKey = try await store.apiKey(for: .volcengine)
        XCTAssertNil(apiKey)
    }
}
