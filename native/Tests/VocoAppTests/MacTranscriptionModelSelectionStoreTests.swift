import XCTest
@testable import VocoApp
@testable import VocoAppCore

@MainActor
final class MacTranscriptionModelSelectionStoreTests: XCTestCase {
    func testSelectionRoundTripsThroughUserDefaults() {
        let suiteName = "MacTranscriptionModelSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MacTranscriptionModelSelectionStore(defaults: defaults)

        store.saveSelection(TranscriptionModelSelection(providerID: .localRecommended))

        XCTAssertEqual(MacTranscriptionModelSelectionStore(defaults: defaults).selection.providerID, .localRecommended)
    }

    func testInvalidStoredValueFallsBackToDefault() {
        let suiteName = "MacTranscriptionModelSelectionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data([0, 1, 2]), forKey: "transcription.modelSelection")

        XCTAssertEqual(MacTranscriptionModelSelectionStore(defaults: defaults).selection, .default)
    }
}
