import XCTest
@testable import VocoAppCore

final class HUDModelsTests: XCTestCase {
    func testReadyWithoutRecentResultIsHidden() {
        let snapshot = HUDSnapshot(
            status: .ready,
            lastTranscript: nil,
            lastInjection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.phase, .hidden)
        XCTAssertFalse(snapshot.isVisible)
    }

    func testRecordingAndTranscribingAreVisible() {
        let recording = HUDSnapshot(
            status: .recording,
            lastTranscript: nil,
            lastInjection: nil,
            lastErrorMessage: nil
        )
        XCTAssertEqual(recording.phase, .recording)
        XCTAssertEqual(recording.title, "正在听")
        XCTAssertEqual(recording.systemImage, "waveform.circle.fill")
        XCTAssertTrue(recording.isVisible)

        let transcribing = HUDSnapshot(
            status: .transcribing,
            lastTranscript: nil,
            lastInjection: nil,
            lastErrorMessage: nil
        )
        XCTAssertEqual(transcribing.phase, .transcribing)
        XCTAssertEqual(transcribing.title, "正在转写")
        XCTAssertTrue(transcribing.isVisible)
    }

    func testSuccessShowsInjectionTargetAndTranscriptPreview() {
        let transcript = TranscriptSnapshot(
            finalText: "hello from Voco",
            partials: ["hello"],
            providerName: "Fake ASR",
            latencyMilliseconds: 42
        )
        let injection = TextInjectionSnapshot(
            targetAppName: "Notes",
            strategy: .directAccessibility,
            succeeded: true,
            detail: "Inserted"
        )

        let snapshot = HUDSnapshot(
            status: .ready,
            lastTranscript: transcript,
            lastInjection: injection,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.phase, .success)
        XCTAssertEqual(snapshot.title, "已插入")
        XCTAssertEqual(snapshot.detail, "Notes · 辅助功能直接插入")
        XCTAssertEqual(snapshot.transcriptPreview, "hello from Voco")
        XCTAssertEqual(snapshot.autoHideAfterSeconds, 1.4)
    }

    func testFailureUsesErrorMessageAndFailedInjectionDetail() {
        let injection = TextInjectionSnapshot(
            targetAppName: "Terminal",
            strategy: .clipboardFallback,
            succeeded: false,
            detail: "clipboard restore failed"
        )
        let failedInjection = HUDSnapshot(
            status: .error,
            lastTranscript: nil,
            lastInjection: injection,
            lastErrorMessage: nil
        )
        XCTAssertEqual(failedInjection.phase, .error)
        XCTAssertEqual(failedInjection.detail, "clipboard restore failed")

        let explicitError = HUDSnapshot(
            status: .providerOffline,
            lastTranscript: nil,
            lastInjection: nil,
            lastErrorMessage: "转写服务未配置"
        )
        XCTAssertEqual(explicitError.phase, .error)
        XCTAssertEqual(explicitError.title, "需要处理")
        XCTAssertEqual(explicitError.detail, "转写服务未配置")
        XCTAssertNil(explicitError.autoHideAfterSeconds)
    }
}
