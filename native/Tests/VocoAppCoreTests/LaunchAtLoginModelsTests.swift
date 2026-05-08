import XCTest
@testable import VocoAppCore

final class LaunchAtLoginModelsTests: XCTestCase {
    func testLaunchAtLoginStateMapsToEnabledFlag() {
        XCTAssertTrue(LaunchAtLoginState.enabled.isEnabled)
        XCTAssertFalse(LaunchAtLoginState.disabled.isEnabled)
        XCTAssertFalse(LaunchAtLoginState.requiresApproval.isEnabled)
        XCTAssertFalse(LaunchAtLoginState.unavailable.isEnabled)
        XCTAssertFalse(LaunchAtLoginState.failed("boom").isEnabled)
    }

    func testLaunchAtLoginStateHasUserVisibleTitlesAndSymbols() {
        XCTAssertEqual(LaunchAtLoginState.enabled.title, "已开启")
        XCTAssertEqual(LaunchAtLoginState.disabled.title, "已关闭")
        XCTAssertEqual(LaunchAtLoginState.requiresApproval.title, "需要批准")
        XCTAssertEqual(LaunchAtLoginState.unavailable.title, "不可用")
        XCTAssertEqual(LaunchAtLoginState.failed("boom").title, "出错")

        XCTAssertEqual(LaunchAtLoginState.enabled.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(LaunchAtLoginState.disabled.systemImage, "minus.circle")
        XCTAssertEqual(LaunchAtLoginState.requiresApproval.systemImage, "exclamationmark.triangle.fill")
    }

    func testLaunchAtLoginStateUsesEnglishCopy() {
        let strings = VocoStrings(language: .en)

        XCTAssertEqual(LaunchAtLoginState.enabled.title(strings: strings), "Enabled")
        XCTAssertEqual(LaunchAtLoginState.disabled.title(strings: strings), "Disabled")
        XCTAssertEqual(LaunchAtLoginState.requiresApproval.title(strings: strings), "Requires Approval")
        XCTAssertEqual(LaunchAtLoginState.unavailable.title(strings: strings), "Unavailable")
        XCTAssertEqual(LaunchAtLoginState.failed("boom").title(strings: strings), "Error")

        XCTAssertEqual(LaunchAtLoginState.disabled.detail(strings: strings), "Voco will not start automatically after login.")
        XCTAssertEqual(LaunchAtLoginState.enabled.detail(strings: strings), "Voco will start automatically after you log in to macOS.")
        XCTAssertEqual(LaunchAtLoginState.requiresApproval.detail(strings: strings), "Approve Voco in System Settings > General > Login Items.")
        XCTAssertEqual(LaunchAtLoginState.unavailable.detail(strings: strings), "The current runtime location or system state does not support launch at login.")
        XCTAssertEqual(LaunchAtLoginState.failed("boom").detail(strings: strings), "boom")
    }

    @MainActor
    func testStaticLaunchAtLoginProviderReturnsConfiguredState() async {
        let provider = StaticLaunchAtLoginProvider(state: .requiresApproval)

        XCTAssertEqual(provider.currentState(), .requiresApproval)
        let result = await provider.setEnabled(true)
        XCTAssertEqual(result, .requiresApproval)
    }
}
