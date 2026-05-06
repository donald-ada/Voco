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

    @MainActor
    func testStaticLaunchAtLoginProviderReturnsConfiguredState() async {
        let provider = StaticLaunchAtLoginProvider(state: .requiresApproval)

        XCTAssertEqual(provider.currentState(), .requiresApproval)
        let result = await provider.setEnabled(true)
        XCTAssertEqual(result, .requiresApproval)
    }
}
