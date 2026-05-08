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
            currentTranscript: nil,
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
            currentTranscript: nil,
            lastInjection: nil,
            lastErrorMessage: nil
        )
        XCTAssertEqual(transcribing.phase, .transcribing)
        XCTAssertEqual(transcribing.title, "正在转写")
        XCTAssertTrue(transcribing.isVisible)
    }

    func testRecordingPreviewUsesOnlyCurrentTranscript() {
        let previousTranscript = TranscriptSnapshot(
            finalText: "old completed words",
            partials: [],
            providerName: "Fake ASR",
            latencyMilliseconds: 42
        )
        let currentTranscript = TranscriptSnapshot(
            finalText: "",
            partials: ["new live words"],
            providerName: "Fake ASR",
            latencyMilliseconds: nil
        )

        let recordingWithoutCurrentText = HUDSnapshot(
            status: .recording,
            lastTranscript: previousTranscript,
            currentTranscript: nil,
            lastInjection: nil,
            lastErrorMessage: nil
        )
        XCTAssertNil(recordingWithoutCurrentText.transcriptPreview)

        let recordingWithCurrentText = HUDSnapshot(
            status: .recording,
            lastTranscript: previousTranscript,
            currentTranscript: currentTranscript,
            lastInjection: nil,
            lastErrorMessage: nil
        )
        XCTAssertEqual(recordingWithCurrentText.transcriptPreview, "new live words")
    }

    func testLongRecordingPreviewUsesLatestTailWindowOnly() {
        let longText = String(
            repeating: "第一段内容会被新的实时转写逐渐替换第二段内容继续说话第三段内容仍在更新",
            count: 3
        )
        let currentTranscript = TranscriptSnapshot(
            finalText: "",
            partials: [longText],
            providerName: "Fake ASR",
            latencyMilliseconds: nil
        )

        let snapshot = HUDSnapshot(
            status: .recording,
            lastTranscript: nil,
            currentTranscript: currentTranscript,
            lastInjection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.transcriptPreview, String(longText.suffix(64)))
    }

    func testReadyAfterSuccessfulInsertionIsHidden() {
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

        XCTAssertEqual(snapshot.phase, .hidden)
        XCTAssertFalse(snapshot.isVisible)
        XCTAssertNil(snapshot.transcriptPreview)
        XCTAssertNil(snapshot.autoHideAfterSeconds)
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
            lastErrorMessage: "模型未配置"
        )
        XCTAssertEqual(explicitError.phase, .error)
        XCTAssertEqual(explicitError.title, "需要处理")
        XCTAssertEqual(explicitError.detail, "模型未配置")
        XCTAssertNil(explicitError.autoHideAfterSeconds)
    }
}
