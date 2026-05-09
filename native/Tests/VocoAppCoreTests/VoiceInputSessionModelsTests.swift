import XCTest
@testable import VocoAppCore

final class VoiceInputSessionModelsTests: XCTestCase {
    func testVoiceInputSessionPageUsesEnglishRangeTitle() {
        let page = VoiceInputSessionPage(sessions: [], page: 1)

        XCTAssertEqual(page.visibleRangeTitle(strings: VocoStrings(language: .en)), "0 / 0 items")
    }

    func testVoiceInputSessionStoreErrorsCanRenderEnglishDescription() {
        let strings = VocoStrings(language: .en)

        XCTAssertEqual(
            VoiceInputSessionStoreError.loadFailed(message: "database unavailable")
                .localizedDescription(strings: strings),
            "Unable to load session history: database unavailable"
        )
        XCTAssertEqual(
            VoiceInputSessionStoreError.saveFailed(message: "disk full")
                .localizedDescription(strings: strings),
            "Unable to save session history: disk full"
        )
        XCTAssertEqual(
            VoiceInputSessionStoreError.loadFailed(message: "database unavailable").localizedDescription,
            "无法加载会话记录：database unavailable"
        )
    }

    func testSessionStoreErrorsCanRenderKnownAppGeneratedDetailsInEnglish() {
        let strings = VocoStrings(language: .en)

        XCTAssertEqual(
            VoiceInputSessionStoreError.loadFailed(message: "无法定位 Application Support 目录。")
                .localizedDescription(strings: strings),
            "Unable to load session history: Unable to locate the Application Support directory."
        )
        XCTAssertEqual(
            VoiceInputSessionStoreError.loadFailed(message: "数据库中存在格式无效的会话记录。")
                .localizedDescription(strings: strings),
            "Unable to load session history: The database contains an invalid session record."
        )
    }

    func testSessionSnapshotUsesProcessedTextAndKeepsRawTranscriptAndDiagnostics() {
        let result = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 2, sampleRate: 16_000, peakAmplitude: 0.2),
            transcript: TranscriptSnapshot(finalText: "嗯今天开始", partials: [], providerName: "TestProvider", latencyMilliseconds: 10),
            postProcessing: TranscriptPostProcessingResult(
                originalText: "嗯今天开始",
                processedText: "今天开始",
                diagnostics: [
                    TranscriptPostProcessingDiagnostic(
                        skillID: FillerCleanupSkill.skillID,
                        ruleID: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                        ruleDisplayName: "删除嗯",
                        matchedText: "嗯",
                        replacementText: "",
                        matchCount: 1
                    )
                ]
            ),
            injection: .success(targetAppName: "Notes", strategy: .clipboardFallback)
        )

        let session = VoiceInputSessionSnapshot(result: result)

        XCTAssertEqual(session.transcriptText, "今天开始")
        XCTAssertEqual(session.rawTranscriptText, "嗯今天开始")
        XCTAssertEqual(session.postProcessingDiagnostics.first?.ruleDisplayName, "删除嗯")
        XCTAssertEqual(session.wordCount, 4)
    }

    func testSessionSnapshotUsesRawTranscriptPreviewWithoutGeneratedTitle() {
        let session = VoiceInputSessionSnapshot(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            transcriptText: "把总览改成主页。右侧的语音输入流程不要再占四大行，改成一行表达。",
            wordCount: 34,
            durationSeconds: 42,
            createdAt: Date(timeIntervalSince1970: 1_714_800_000),
            targetAppName: "Codex",
            providerName: "火山引擎"
        )

        XCTAssertEqual(session.previewText(maxLength: 24), "把总览改成主页。右侧的语音输入流程不要再占四大行...")
        XCTAssertFalse(session.previewText(maxLength: 24).contains("产品原型修改说明"))
        XCTAssertEqual(session.durationTitle, "42s")
    }

    func testSessionPageDefaultsToTenRowsAndReportsVisibleRange() {
        let sessions = (1...12).map { index in
            VoiceInputSessionSnapshot(
                id: UUID(),
                transcriptText: "第 \(index) 条原始转写内容",
                wordCount: index,
                durationSeconds: Double(index),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                targetAppName: nil,
                providerName: "Fake ASR"
            )
        }

        let firstPage = VoiceInputSessionPage(sessions: sessions, page: 1)
        let secondPage = VoiceInputSessionPage(sessions: sessions, page: 2)

        XCTAssertEqual(firstPage.pageSize, 10)
        XCTAssertEqual(firstPage.entries.count, 10)
        XCTAssertEqual(firstPage.visibleRangeTitle, "1-10 / 12 条")
        XCTAssertEqual(secondPage.entries.count, 2)
        XCTAssertEqual(secondPage.visibleRangeTitle, "11-12 / 12 条")
    }
}
