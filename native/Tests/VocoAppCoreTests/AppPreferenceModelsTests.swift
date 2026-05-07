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

    func testDockPresentationPolicyHidesDockIconByDefault() {
        XCTAssertEqual(
            AppDockPresentationPolicy(displayInDockEnabled: false).action,
            .hideFromDock
        )
        XCTAssertEqual(
            AppDockPresentationPolicy(displayInDockEnabled: true).action,
            .showInDock
        )
    }

    func testNoOpAppPreferenceStoreDefaultsToVisibleLaunch() {
        XCTAssertFalse(NoOpAppPreferenceStore().silentLaunchEnabled)
        XCTAssertFalse(NoOpAppPreferenceStore().displayInDockEnabled)
    }
}
