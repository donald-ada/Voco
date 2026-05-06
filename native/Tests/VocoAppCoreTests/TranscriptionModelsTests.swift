import XCTest
@testable import VocoAppCore

final class TranscriptionModelsTests: XCTestCase {
    func testProviderStatusHasUserVisibleMetadata() {
        XCTAssertEqual(TranscriptionProviderStatus.notConfigured.title, "未配置")
        XCTAssertEqual(TranscriptionProviderStatus.notConfigured.systemImage, "exclamationmark.triangle")
        XCTAssertFalse(TranscriptionProviderStatus.notConfigured.isUsable)

        XCTAssertEqual(TranscriptionProviderStatus.ready(providerName: "Doubao").title, "Doubao")
        XCTAssertEqual(TranscriptionProviderStatus.ready(providerName: "Doubao").detail, "转写服务已配置")
        XCTAssertTrue(TranscriptionProviderStatus.ready(providerName: "Doubao").isUsable)

        XCTAssertEqual(TranscriptionProviderStatus.authenticationRequired(providerName: "Doubao").title, "Doubao 需要认证")
        XCTAssertFalse(TranscriptionProviderStatus.authenticationRequired(providerName: "Doubao").isUsable)
    }

    func testProviderErrorsAreLocalizedAndClassified() {
        XCTAssertEqual(
            TranscriptionProviderError.notConfigured.localizedDescription,
            "转写服务未配置：请先在设置中配置 ASR provider。"
        )
        XCTAssertEqual(
            TranscriptionProviderError.authentication(providerName: "Doubao", message: "invalid token").localizedDescription,
            "Doubao 认证失败：invalid token"
        )
        XCTAssertTrue(TranscriptionProviderError.transport(providerName: "Doubao", message: "timeout", retryable: true).isRetryable)
        XCTAssertFalse(TranscriptionProviderError.authentication(providerName: "Doubao", message: "invalid token").isRetryable)
    }

    func testTranscriptSnapshotAppendsNonEmptyPartials() {
        let base = TranscriptSnapshot(
            finalText: "",
            partials: [],
            providerName: "Doubao",
            latencyMilliseconds: nil
        )

        let updated = base.appendingPartial(
            TranscriptPartialSnapshot(text: "你好", stablePrefixLength: 0, providerName: "Doubao")
        )

        XCTAssertEqual(updated.finalText, "")
        XCTAssertEqual(updated.partials, ["你好"])
        XCTAssertEqual(updated.providerName, "Doubao")
    }

    func testTranscriptSnapshotIgnoresBlankPartials() {
        let base = TranscriptSnapshot(
            finalText: "",
            partials: ["你好"],
            providerName: "Doubao",
            latencyMilliseconds: nil
        )

        let updated = base.appendingPartial(
            TranscriptPartialSnapshot(text: " \n ", stablePrefixLength: 0, providerName: "Doubao")
        )

        XCTAssertEqual(updated.partials, ["你好"])
    }
}
