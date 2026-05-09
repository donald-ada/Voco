import XCTest
@testable import VocoAppCore

final class TranscriptPostProcessingModelsTests: XCTestCase {
    func testPlainTextRuleDeletesMatchedFillerAndReportsDiagnostic() {
        let skill = FillerCleanupSkill(
            settings: FillerCleanupSettings(
                isEnabled: true,
                rules: [
                    FillerCleanupRule(
                        displayName: "删除嗯",
                        matchText: "嗯",
                        action: .delete,
                        order: 0
                    )
                ]
            )
        )

        let output = skill.process(
            "嗯今天我们开始测试",
            context: TranscriptPostProcessingContext(targetAppName: nil)
        )

        XCTAssertEqual(output.processedText, "今天我们开始测试")
        XCTAssertEqual(output.diagnostics.count, 1)
        XCTAssertEqual(output.diagnostics[0].skillID, FillerCleanupSkill.skillID)
        XCTAssertEqual(output.diagnostics[0].matchedText, "嗯")
        XCTAssertEqual(output.diagnostics[0].replacementText, "")
        XCTAssertEqual(output.diagnostics[0].matchCount, 1)
    }

    func testPlainTextRulesReplaceWithSpaceAndCustomTextInDiagnosticOrder() {
        let skill = FillerCleanupSkill(
            settings: FillerCleanupSettings(
                isEnabled: true,
                rules: [
                    FillerCleanupRule(
                        displayName: "自定义替换",
                        matchText: "那个",
                        action: .replace("这件事"),
                        order: 1
                    ),
                    FillerCleanupRule(
                        displayName: "空格替换",
                        matchText: "然后",
                        action: .replace(" "),
                        order: 0
                    )
                ]
            )
        )

        let output = skill.process(
            "然后那个我们继续",
            context: TranscriptPostProcessingContext(targetAppName: nil)
        )

        XCTAssertEqual(output.processedText, " 这件事我们继续")
        XCTAssertEqual(output.diagnostics.map(\.ruleDisplayName), ["空格替换", "自定义替换"])
        XCTAssertEqual(output.diagnostics.map(\.replacementText), [" ", "这件事"])
    }

    func testDisabledRuleDoesNotChangeText() {
        let skill = FillerCleanupSkill(
            settings: FillerCleanupSettings(
                isEnabled: true,
                rules: [
                    FillerCleanupRule(
                        displayName: "禁用删除",
                        matchText: "就是",
                        action: .delete,
                        isEnabled: false,
                        order: 0
                    )
                ]
            )
        )

        let output = skill.process(
            "就是这样",
            context: TranscriptPostProcessingContext(targetAppName: nil)
        )

        XCTAssertEqual(output.processedText, "就是这样")
        XCTAssertTrue(output.diagnostics.isEmpty)
    }

    func testRulesRunDeterministicallyByOrderThenDisplayName() {
        let skill = FillerCleanupSkill(
            settings: FillerCleanupSettings(
                isEnabled: true,
                rules: [
                    FillerCleanupRule(
                        displayName: "换今天",
                        matchText: "今天",
                        action: .replace("明天"),
                        order: 1
                    ),
                    FillerCleanupRule(
                        displayName: "删嗯",
                        matchText: "嗯",
                        action: .delete,
                        order: 0
                    )
                ]
            )
        )

        let output = skill.process(
            "嗯今天",
            context: TranscriptPostProcessingContext(targetAppName: nil)
        )

        XCTAssertEqual(output.processedText, "明天")
        XCTAssertEqual(output.diagnostics.map(\.ruleDisplayName), ["删嗯", "换今天"])
    }

    func testPipelinePreservesOriginalAndProcessedTextAndReturnsDiagnostics() {
        let pipeline = TranscriptPostProcessingPipeline(
            settings: SkillSettings(
                isEnabled: true,
                fillerCleanup: FillerCleanupSettings(
                    isEnabled: true,
                    rules: [
                        FillerCleanupRule(
                            displayName: "删除啊",
                            matchText: "啊",
                            action: .delete,
                            order: 0
                        )
                    ]
                )
            )
        )

        let result = pipeline.process(
            "啊开始",
            context: TranscriptPostProcessingContext(targetAppName: nil)
        )

        XCTAssertEqual(result.originalText, "啊开始")
        XCTAssertEqual(result.processedText, "开始")
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.diagnostics.count, 1)
        XCTAssertEqual(result.diagnostics[0].skillID, FillerCleanupSkill.skillID)
    }
}
