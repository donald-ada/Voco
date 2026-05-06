import XCTest
@testable import VocoAppCore

final class SettingsSectionTests: XCTestCase {
    func testSettingsSectionsStayInProductOrder() {
        XCTAssertEqual(
            SettingsSection.allCases,
            [
                .general,
                .hotkey,
                .audio,
                .transcription,
                .injection,
                .hud,
                .privacy,
                .diagnostics
            ]
        )
    }

    func testSettingsSectionsHaveUserVisibleTitlesAndSymbols() {
        XCTAssertEqual(SettingsSection.general.title, "通用")
        XCTAssertEqual(SettingsSection.general.systemImage, "gearshape")
        XCTAssertEqual(SettingsSection.hotkey.title, "快捷键")
        XCTAssertEqual(SettingsSection.audio.systemImage, "mic")
        XCTAssertEqual(SettingsSection.diagnostics.title, "诊断")
        XCTAssertEqual(SettingsSection.diagnostics.systemImage, "stethoscope")
    }
}
