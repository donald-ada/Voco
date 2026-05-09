import XCTest
@testable import VocoApp
@testable import VocoAppCore

@MainActor
final class MacSkillPreferenceStoreTests: XCTestCase {
    func testSkillSettingsRoundTripThroughUserDefaults() throws {
        let suiteName = "MacSkillPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = MacSkillPreferenceStore(defaults: defaults)
        let ruleID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let settings = SkillSettings(
            isEnabled: true,
            fillerCleanup: FillerCleanupSettings(
                isEnabled: true,
                rules: [
                    FillerCleanupRule(
                        id: ruleID,
                        displayName: "自定义",
                        matchText: "就是说",
                        action: .replace(""),
                        isEnabled: true,
                        order: 0
                    )
                ]
            )
        )

        store.saveSkillSettings(settings)

        XCTAssertEqual(MacSkillPreferenceStore(defaults: defaults).skillSettings, settings)
    }

    func testInvalidStoredSkillSettingsFallsBackToDefault() throws {
        let suiteName = "MacSkillPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: "skills.settings")

        XCTAssertEqual(MacSkillPreferenceStore(defaults: defaults).skillSettings, .default)
    }
}
