import XCTest
import VocoAppCore
@testable import VocoApp

@MainActor
final class SettingsOverviewPrimaryActionResolverTests: XCTestCase {
    func testMicrophoneActionRequestsPermissionPrompt() {
        XCTAssertEqual(
            SettingsOverviewPrimaryActionResolver.resolve(title: SettingsWorkbenchActionTitle.checkMicrophone),
            .requestMicrophonePermission
        )
    }

    func testAccessibilityActionStillOpensSystemSettings() {
        XCTAssertEqual(
            SettingsOverviewPrimaryActionResolver.resolve(title: PermissionKind.accessibility.recoveryActionTitle),
            .openAccessibilitySettings
        )
    }
}
