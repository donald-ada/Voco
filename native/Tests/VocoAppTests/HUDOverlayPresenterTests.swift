import XCTest
import VocoAppCore
@testable import VocoApp

final class HUDOverlayPresenterTests: XCTestCase {
    func testAutoHiddenSnapshotDoesNotPresentAgainUntilSnapshotChanges() {
        var state = HUDOverlayPresentationState()
        let success = successSnapshot(text: "hello from Voco")

        XCTAssertEqual(state.presentationDecision(for: success), .show)

        state.markAutoHidden(success)

        XCTAssertEqual(state.presentationDecision(for: success), .ignore)

        let recording = HUDSnapshot(
            status: .recording,
            lastTranscript: nil,
            lastInjection: nil,
            lastErrorMessage: nil
        )
        XCTAssertEqual(state.presentationDecision(for: recording), .show)
    }

    private func successSnapshot(text: String) -> HUDSnapshot {
        HUDSnapshot(
            status: .ready,
            lastTranscript: TranscriptSnapshot(
                finalText: text,
                partials: [],
                providerName: "Fake ASR",
                latencyMilliseconds: 42
            ),
            lastInjection: TextInjectionSnapshot(
                targetAppName: "Notes",
                strategy: .clipboardFallback,
                succeeded: true,
                detail: "Inserted"
            ),
            lastErrorMessage: nil
        )
    }
}
