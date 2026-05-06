import XCTest
@testable import VocoAppCore

final class TranscriptionCredentialModelsTests: XCTestCase {
    func testStoredSnapshotMasksAPIKey() {
        let snapshot = TranscriptionCredentialSnapshot.stored(
            provider: .doubao,
            apiKey: "sk-test-1234567890"
        )

        XCTAssertEqual(snapshot.provider.title, "Doubao")
        XCTAssertTrue(snapshot.hasAPIKey)
        XCTAssertEqual(snapshot.maskedAPIKey, "sk-t...7890")
        XCTAssertEqual(snapshot.statusTitle, "Doubao 凭证已保存")
        XCTAssertNil(snapshot.lastErrorMessage)
    }

    func testMissingAndFailedSnapshotsAreUserVisible() {
        let missing = TranscriptionCredentialSnapshot.missing(provider: .doubao)
        XCTAssertFalse(missing.hasAPIKey)
        XCTAssertEqual(missing.statusTitle, "Doubao 凭证未保存")
        XCTAssertEqual(missing.storageDetail, "Keychain 中没有保存 API Key。")

        let failed = TranscriptionCredentialSnapshot.failed(provider: .doubao, message: "read failed")
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
            TranscriptionCredentialError.storeFailed(message: "OSStatus -50").localizedDescription,
            "保存 ASR 凭证失败：OSStatus -50"
        )
    }

    @MainActor
    func testInMemoryCredentialStoreSavesAndDeletesKey() async throws {
        let store = InMemoryTranscriptionCredentialStore()

        XCTAssertEqual(store.currentSnapshot(), .missing(provider: .doubao))

        let stored = try await store.saveAPIKey("  sk-test-abcdef  ", for: .doubao)
        XCTAssertTrue(stored.hasAPIKey)
        let savedAPIKey = try await store.apiKey(for: .doubao)
        XCTAssertEqual(savedAPIKey, "sk-test-abcdef")

        let missing = try await store.deleteCredentials(for: .doubao)
        XCTAssertEqual(missing, .missing(provider: .doubao))
        let deletedAPIKey = try await store.apiKey(for: .doubao)
        XCTAssertNil(deletedAPIKey)
    }
}
