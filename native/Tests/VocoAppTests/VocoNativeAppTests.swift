import XCTest
@testable import VocoApp

@MainActor
final class VocoNativeAppTests: XCTestCase {
    func testMenuBarCommandTitlesUseShortQuitLabel() {
        XCTAssertEqual(VocoNativeApp.showSettingsMenuTitle, "显示 Voco")
        XCTAssertEqual(VocoNativeApp.quitMenuTitle, "退出")
    }
}
