import XCTest
@testable import VocoAppCore

final class PrivacySettingsModelsTests: XCTestCase {
    func testMissingCredentialsShowKeychainMissingAndPrivateDefaults() {
        let snapshot = PrivacySettingsSnapshot(
            transcriptionCredentials: .missing(provider: .doubao)
        )

        XCTAssertEqual(snapshot.keychain.title, "Keychain 未保存凭证")
        XCTAssertEqual(snapshot.keychain.detail, "Keychain 中没有保存 Doubao 凭证。")
        XCTAssertEqual(snapshot.transcriptRetention.title, "不保留转写文本")
        XCTAssertEqual(snapshot.transcriptRetention.detail, "转写文本仅用于本次插入和当前运行时诊断。")
        XCTAssertEqual(snapshot.logsPolicy.title, "日志默认脱敏")
        XCTAssertEqual(snapshot.logsPolicy.detail, "诊断信息不记录完整 Doubao 凭证或完整转写正文。")
    }

    func testStoredCredentialsShowMaskedKeychainStatus() {
        let snapshot = PrivacySettingsSnapshot(
            transcriptionCredentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef")
        )

        XCTAssertEqual(snapshot.keychain.title, "Keychain 已保存凭证")
        XCTAssertEqual(snapshot.keychain.detail, "sk-t...cdef")
        XCTAssertEqual(snapshot.keychain.systemImage, "key.fill")
    }

    func testCredentialFailureShowsKeychainError() {
        let snapshot = PrivacySettingsSnapshot(
            transcriptionCredentials: .failed(provider: .doubao, message: "denied")
        )

        XCTAssertEqual(snapshot.keychain.title, "Keychain 访问失败")
        XCTAssertEqual(snapshot.keychain.detail, "Keychain 访问失败：denied")
        XCTAssertEqual(snapshot.keychain.systemImage, "exclamationmark.triangle.fill")
    }
}
