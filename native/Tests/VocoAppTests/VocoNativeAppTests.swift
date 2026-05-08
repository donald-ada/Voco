import XCTest
@testable import VocoApp
@testable import VocoAppCore

@MainActor
final class VocoNativeAppTests: XCTestCase {
    func testNativeAppMenuTitlesComeFromLocalizedStrings() {
        XCTAssertEqual(VocoStrings(language: .zhHans).app.showSettingsMenuTitle, "显示 Voco")
        XCTAssertEqual(VocoStrings(language: .en).app.showSettingsMenuTitle, "Show Voco")
        XCTAssertEqual(VocoStrings(language: .zhHans).app.quitMenuTitle, "退出")
        XCTAssertEqual(VocoStrings(language: .en).app.quitMenuTitle, "Quit")
    }
}
