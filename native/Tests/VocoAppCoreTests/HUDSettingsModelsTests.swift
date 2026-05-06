import XCTest
@testable import VocoAppCore

final class HUDSettingsModelsTests: XCTestCase {
    func testDefaultHUDSettingsDescribeLegacyBottomCapsule() {
        let snapshot = HUDSettingsSnapshot()

        XCTAssertEqual(snapshot.position.title, "底部居中")
        XCTAssertEqual(snapshot.position.detail, "HUD 使用旧版 compact 胶囊，固定在屏幕底部中央。")
        XCTAssertEqual(snapshot.notchMode.title, "胶囊模式")
        XCTAssertEqual(snapshot.notchMode.detail, "使用已调试的黑色胶囊 UI，不贴近 Dynamic Island。")
        XCTAssertEqual(snapshot.transcriptPreview.title, "不显示转写预览")
        XCTAssertEqual(snapshot.transcriptPreview.detail, "胶囊只显示语音输入状态和声波，避免展开成卡片。")
        XCTAssertFalse(snapshot.transcriptPreview.isVisible)
    }
}
