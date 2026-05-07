import XCTest
@testable import VocoAppCore

@MainActor
final class AppPreferenceModelsTests: XCTestCase {
    func testLaunchPresentationPolicyShowsWindowUnlessSilentLaunchIsEnabled() {
        XCTAssertEqual(
            AppLaunchPresentationPolicy(silentLaunchEnabled: false).action,
            .showSettingsWindow
        )
        XCTAssertEqual(
            AppLaunchPresentationPolicy(silentLaunchEnabled: true).action,
            .menuBarOnly
        )
    }

    func testNoOpAppPreferenceStoreDefaultsToVisibleLaunch() {
        XCTAssertFalse(NoOpAppPreferenceStore().silentLaunchEnabled)
    }
}
