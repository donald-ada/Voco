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
        XCTAssertTrue(NoOpAppPreferenceStore().voiceInputSessionHistoryEnabled)
        XCTAssertEqual(NoOpAppPreferenceStore().voiceInputSessionRetentionPolicy, .last1000)
    }

    func testVoiceInputSessionRetentionPolicyExposesCustomerChoices() {
        XCTAssertEqual(
            VoiceInputSessionRetentionPolicy.allCases.map(\.title),
            ["最近 100 条", "最近 1000 条", "永久保留"]
        )
        XCTAssertEqual(VoiceInputSessionRetentionPolicy.last100.loadLimit, 100)
        XCTAssertEqual(VoiceInputSessionRetentionPolicy.last1000.loadLimit, 1000)
        XCTAssertNil(VoiceInputSessionRetentionPolicy.forever.limit)
    }
}
