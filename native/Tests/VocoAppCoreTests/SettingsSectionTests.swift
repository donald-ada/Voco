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

    func testSettingsSectionsExposeSummariesForDetailRendering() {
        XCTAssertEqual(SettingsSection.audio.summary, "输入设备、电平和采样率")
        XCTAssertEqual(SettingsSection.injection.summary, "插入策略和聚焦 App 诊断")
        XCTAssertEqual(SettingsSection.hud.summary, "位置、刘海模式和转写预览")
        XCTAssertEqual(SettingsSection.privacy.summary, "Keychain、转写保留和日志策略")
    }
}
