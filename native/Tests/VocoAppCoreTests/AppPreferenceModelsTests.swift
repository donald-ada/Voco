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

    func testAppLanguageDefaultsToChineseAndExposesDisplayNames() {
        XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), ["zh-Hans", "en"])
        XCTAssertEqual(AppLanguage.default, .zhHans)
        XCTAssertEqual(AppLanguage.zhHans.displayName, "中文")
        XCTAssertEqual(AppLanguage.en.displayName, "English")
    }

    func testNoOpAppPreferenceStoreDefaultsToChineseLanguage() {
        XCTAssertEqual(NoOpAppPreferenceStore().appLanguage, .zhHans)
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

    func testVoiceInputSessionRetentionPolicyUsesEnglishCopy() {
        let strings = VocoStrings(language: .en)

        XCTAssertEqual(
            VoiceInputSessionRetentionPolicy.allCases.map { $0.title(strings: strings) },
            ["Last 100", "Last 1000", "Keep Forever"]
        )
        XCTAssertEqual(
            VoiceInputSessionRetentionPolicy.last100.detail(strings: strings),
            "Keep only the most recent 100 sessions."
        )
        XCTAssertEqual(
            VoiceInputSessionRetentionPolicy.forever.detail(strings: strings),
            "Do not automatically clean up old sessions."
        )
    }
}
