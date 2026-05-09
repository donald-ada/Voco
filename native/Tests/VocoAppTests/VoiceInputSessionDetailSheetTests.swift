import XCTest
@testable import VocoApp
@testable import VocoAppCore

final class VoiceInputSessionDetailSheetTests: XCTestCase {
    func testSessionDetailSummaryShowsProcessedRawAndMatchedRules() {
        let session = VoiceInputSessionSnapshot(
            transcriptText: "今天开始",
            rawTranscriptText: "嗯今天开始",
            postProcessingDiagnostics: [
                TranscriptPostProcessingDiagnostic(
                    skillID: FillerCleanupSkill.skillID,
                    ruleID: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
                    ruleDisplayName: "删除嗯",
                    matchedText: "嗯",
                    replacementText: "",
                    matchCount: 1
                )
            ],
            wordCount: 4,
            durationSeconds: 2,
            targetAppName: "Notes",
            providerName: "TestProvider"
        )

        let summary = VoiceInputSessionDetailSummary(session: session, strings: VocoStrings(language: .zhHans))

        XCTAssertEqual(summary.processedTextTitle, "处理后")
        XCTAssertEqual(summary.processedText, "今天开始")
        XCTAssertEqual(summary.rawTextTitle, "原始转写")
        XCTAssertEqual(summary.rawText, "嗯今天开始")
        XCTAssertEqual(summary.matchedRulesTitle, "命中规则")
        XCTAssertEqual(summary.matchedRules, ["删除嗯：嗯 -> 空字符串 x1"])
    }
}
