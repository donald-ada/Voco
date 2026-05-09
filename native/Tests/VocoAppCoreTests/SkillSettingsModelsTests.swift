import XCTest
@testable import VocoAppCore

final class SkillSettingsModelsTests: XCTestCase {
    func testSkillSettingsSnapshotUsesChineseCopyByDefault() {
        let snapshot = SkillSettingsSnapshot(settings: .default, previewInput: "嗯测试")

        XCTAssertEqual(snapshot.title, "技能")
        XCTAssertEqual(snapshot.fillerCleanupTitle, "语气词清理")
    }

    func testSkillSettingsSnapshotUsesEnglishCopyAndPreview() {
        let settings = SkillSettings(
            isEnabled: true,
            fillerCleanup: FillerCleanupSettings(
                isEnabled: true,
                rules: [FillerCleanupRule(displayName: "删除嗯", matchText: "嗯", action: .delete, isEnabled: true, order: 0)]
            )
        )
        let snapshot = SkillSettingsSnapshot(
            settings: settings,
            previewInput: "嗯hello",
            strings: VocoStrings(language: .en)
        )

        XCTAssertEqual(snapshot.title, "Skills")
        XCTAssertEqual(snapshot.fillerCleanupTitle, "Filler Cleanup")
        XCTAssertEqual(snapshot.preview.originalText, "嗯hello")
        XCTAssertEqual(snapshot.preview.processedText, "hello")
        XCTAssertEqual(snapshot.preview.matchedRuleTitles, ["删除嗯"])
    }

    func testSkillSettingsSnapshotRulesMatchPreviewOrderWhenRuleOrderTies() {
        let settings = SkillSettings(
            isEnabled: true,
            fillerCleanup: FillerCleanupSettings(
                isEnabled: true,
                rules: [
                    FillerCleanupRule(displayName: "B rule", matchText: "beta", action: .delete, order: 0),
                    FillerCleanupRule(displayName: "A rule", matchText: "alpha", action: .delete, order: 0),
                ]
            )
        )

        let snapshot = SkillSettingsSnapshot(
            settings: settings,
            previewInput: "alpha beta",
            strings: VocoStrings(language: .en)
        )

        XCTAssertEqual(snapshot.rules.map(\.displayName), ["A rule", "B rule"])
        XCTAssertEqual(snapshot.preview.matchedRuleTitles, snapshot.rules.map(\.displayName))
    }

    func testFillerCleanupSettingsOrderedRulesForDisplayUsesProcessingTieBreakers() {
        let settings = FillerCleanupSettings(
            isEnabled: true,
            rules: [
                FillerCleanupRule(displayName: "B rule", matchText: "beta", action: .delete, order: 0),
                FillerCleanupRule(displayName: "A rule", matchText: "alpha", action: .delete, order: 0),
                FillerCleanupRule(displayName: "C rule", matchText: "gamma", action: .delete, order: 1),
            ]
        )

        XCTAssertEqual(settings.orderedRulesForDisplay.map(\.displayName), ["A rule", "B rule", "C rule"])
    }
}
