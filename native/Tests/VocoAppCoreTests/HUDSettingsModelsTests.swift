import XCTest
@testable import VocoAppCore

final class HUDSettingsModelsTests: XCTestCase {
    func testDefaultHUDSettingsAreTopCenterNotchAwareWithPreviewEnabled() {
        let snapshot = HUDSettingsSnapshot()

        XCTAssertEqual(snapshot.position.title, "顶部居中")
        XCTAssertEqual(snapshot.position.detail, "HUD 固定显示在屏幕顶部中央。")
        XCTAssertEqual(snapshot.notchMode.title, "刘海避让")
        XCTAssertEqual(snapshot.notchMode.detail, "在带刘海屏幕上自动贴近 Dynamic Island 区域。")
        XCTAssertEqual(snapshot.transcriptPreview.title, "显示转写预览")
        XCTAssertEqual(snapshot.transcriptPreview.detail, "录音和插入过程中显示最多 80 个字符的实时文本。")
        XCTAssertTrue(snapshot.transcriptPreview.isVisible)
    }
}
