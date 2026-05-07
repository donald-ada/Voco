import XCTest
import VocoAppCore
@testable import VocoApp

@MainActor
final class MacVoiceInputPreferenceStoreTests: XCTestCase {
    func testVoiceInputPreferencesRoundTripThroughUserDefaults() throws {
        let suiteName = "VocoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = MacVoiceInputPreferenceStore(defaults: defaults)
        store.saveHotkeyPreset(.capsLock)
        store.saveHotkeyMode(.pressAndHold)
        store.saveAudioInputDevice(.device(id: "studio-mic", title: "Studio Mic"))

        let reloadedStore = MacVoiceInputPreferenceStore(defaults: defaults)

        XCTAssertEqual(reloadedStore.hotkeyPreset, .capsLock)
        XCTAssertEqual(reloadedStore.hotkeyMode, .pressAndHold)
        XCTAssertEqual(reloadedStore.audioInputDevice, .device(id: "studio-mic", title: "Studio Mic"))
    }
}
