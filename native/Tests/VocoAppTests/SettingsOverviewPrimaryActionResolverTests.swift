import XCTest
import VocoAppCore
@testable import VocoApp

@MainActor
final class SettingsOverviewPrimaryActionResolverTests: XCTestCase {
    func testOverviewPrimaryActionsResolveFromStableActionIDs() {
        XCTAssertEqual(
            SettingsOverviewPrimaryActionResolver.resolve(actionID: SettingsWorkbenchActionID.checkMicrophone),
            .requestMicrophonePermission
        )
        XCTAssertEqual(
            SettingsOverviewPrimaryActionResolver.resolve(actionID: SettingsWorkbenchActionID.openModel),
            .selectModel
        )
        XCTAssertEqual(
            SettingsOverviewPrimaryActionResolver.resolve(actionID: SettingsWorkbenchActionID.openSettings),
            .selectSettings
        )
        XCTAssertEqual(
            SettingsOverviewPrimaryActionResolver.resolve(actionID: SettingsWorkbenchActionID.openAccessibilitySettings),
            .openAccessibilitySettings
        )
        XCTAssertEqual(
            SettingsOverviewPrimaryActionResolver.resolve(actionID: SettingsWorkbenchActionID.refresh),
            .refresh
        )
        XCTAssertEqual(
            SettingsOverviewPrimaryActionResolver.resolve(actionID: SettingsWorkbenchActionID.startTestRecording),
            .startTestRecording
        )
    }

    func testMicrophoneActionRequestsPermissionPrompt() {
        XCTAssertEqual(
            SettingsOverviewPrimaryActionResolver.resolve(actionID: SettingsWorkbenchActionID.checkMicrophone),
            .requestMicrophonePermission
        )
    }

    func testAccessibilityActionStillOpensSystemSettings() {
        XCTAssertEqual(
            SettingsOverviewPrimaryActionResolver.resolve(actionID: SettingsWorkbenchActionID.openAccessibilitySettings),
            .openAccessibilitySettings
        )
    }

    func testUnknownActionIDResolvesToUnknown() {
        XCTAssertEqual(SettingsOverviewPrimaryActionResolver.resolve(actionID: "not-a-known-action"), .unknown)
    }

    func testLocalizedDisplayTitlesDoNotResolveToConcreteActions() {
        XCTAssertEqual(SettingsOverviewPrimaryActionResolver.resolve(actionID: "前往模型"), .unknown)
        XCTAssertEqual(SettingsOverviewPrimaryActionResolver.resolve(actionID: "重新检查"), .unknown)
        XCTAssertEqual(SettingsOverviewPrimaryActionResolver.resolve(actionID: "打开辅助功能设置"), .unknown)
    }
}
