import XCTest
@testable import VocoAppCore

final class SkillSettingsModelsTests: XCTestCase {
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
}
