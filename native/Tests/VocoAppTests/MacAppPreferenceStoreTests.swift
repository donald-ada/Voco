import XCTest
@testable import VocoApp

@MainActor
final class MacAppPreferenceStoreTests: XCTestCase {
    func testSilentLaunchPreferenceRoundTripsThroughUserDefaults() throws {
        let suiteName = "VocoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = MacAppPreferenceStore(defaults: defaults)

        XCTAssertFalse(store.silentLaunchEnabled)

        store.saveSilentLaunchEnabled(true)
        XCTAssertTrue(MacAppPreferenceStore(defaults: defaults).silentLaunchEnabled)

        store.saveSilentLaunchEnabled(false)
        XCTAssertFalse(MacAppPreferenceStore(defaults: defaults).silentLaunchEnabled)
    }

    func testDisplayInDockPreferenceRoundTripsThroughUserDefaults() throws {
        let suiteName = "VocoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = MacAppPreferenceStore(defaults: defaults)

        XCTAssertFalse(store.displayInDockEnabled)

        store.saveDisplayInDockEnabled(true)
        XCTAssertTrue(MacAppPreferenceStore(defaults: defaults).displayInDockEnabled)

        store.saveDisplayInDockEnabled(false)
        XCTAssertFalse(MacAppPreferenceStore(defaults: defaults).displayInDockEnabled)
    }

    func testVoiceInputSessionHistoryPreferenceRoundTripsThroughUserDefaults() throws {
        let suiteName = "VocoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = MacAppPreferenceStore(defaults: defaults)

        XCTAssertTrue(store.voiceInputSessionHistoryEnabled)
        XCTAssertEqual(store.voiceInputSessionRetentionPolicy, .last1000)

        store.saveVoiceInputSessionHistoryEnabled(false)
        store.saveVoiceInputSessionRetentionPolicy(.forever)

        let reloadedStore = MacAppPreferenceStore(defaults: defaults)
        XCTAssertFalse(reloadedStore.voiceInputSessionHistoryEnabled)
        XCTAssertEqual(reloadedStore.voiceInputSessionRetentionPolicy, .forever)
    }
}
