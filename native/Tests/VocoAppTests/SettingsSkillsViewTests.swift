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
}
