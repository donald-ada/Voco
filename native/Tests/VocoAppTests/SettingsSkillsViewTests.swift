import XCTest
@testable import VocoApp
@testable import VocoAppCore

final class SettingsSkillsViewTests: XCTestCase {
    func testReplacementPresetTitlesAreLocalized() {
        XCTAssertEqual(FillerCleanupReplacementPreset.empty.title(strings: VocoStrings(language: .zhHans)), "空字符串")
        XCTAssertEqual(FillerCleanupReplacementPreset.space.title(strings: VocoStrings(language: .en)), "Space")
        XCTAssertEqual(FillerCleanupReplacementPreset.custom.title(strings: VocoStrings(language: .en)), "Custom")
    }

    func testReplacementPresetMapsToReplacementText() {
        XCTAssertEqual(FillerCleanupReplacementPreset.empty.replacementText(customText: "x"), "")
        XCTAssertEqual(FillerCleanupReplacementPreset.space.replacementText(customText: "x"), " ")
        XCTAssertEqual(FillerCleanupReplacementPreset.custom.replacementText(customText: "x"), "x")
    }

    func testReplacementPresetBuildsCleanupAction() {
        XCTAssertEqual(FillerCleanupReplacementPreset.empty.action(customText: "x"), .delete)
        XCTAssertEqual(FillerCleanupReplacementPreset.space.action(customText: "x"), .replace(" "))
        XCTAssertEqual(FillerCleanupReplacementPreset.custom.action(customText: "x"), .replace("x"))
    }

    func testPreviewChangeSegmentDisplayMakesSpaceReplacementsVisible() {
        let insertedSpace = SkillPreviewChangeSegment(
            id: 0,
            kind: .inserted,
            text: " ",
            ruleTitle: "空格替换"
        )
        let removedWord = SkillPreviewChangeSegment(
            id: 1,
            kind: .removed,
            text: "嗯",
            ruleTitle: "删除嗯"
        )

        XCTAssertEqual(
            SkillPreviewChangeSegmentDisplay.text(for: insertedSpace, strings: VocoStrings(language: .zhHans)),
            "空格"
        )
        XCTAssertEqual(
            SkillPreviewChangeSegmentDisplay.text(for: insertedSpace, strings: VocoStrings(language: .en)),
            "Space"
        )
        XCTAssertEqual(
            SkillPreviewChangeSegmentDisplay.text(for: removedWord, strings: VocoStrings(language: .zhHans)),
            "嗯"
        )
    }
}
