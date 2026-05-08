import XCTest
import VocoAppCore
@testable import VocoApp

final class HUDOverlayPresenterTests: XCTestCase {
    func testAutoHiddenSnapshotDoesNotPresentAgainUntilSnapshotChanges() {
        var state = HUDOverlayPresentationState()
        let visible = visibleSnapshot(text: "hello from Voco")

        XCTAssertEqual(state.presentationDecision(for: visible), .show)

        state.markAutoHidden(visible)

        XCTAssertEqual(state.presentationDecision(for: visible), .ignore)

        let recording = HUDSnapshot(
            status: .recording,
            lastTranscript: nil,
            lastInjection: nil,
            lastErrorMessage: nil
        )
        XCTAssertEqual(state.presentationDecision(for: recording), .show)
    }

    private func visibleSnapshot(text: String) -> HUDSnapshot {
        HUDSnapshot(
            status: .recording,
            lastTranscript: nil,
            currentTranscript: TranscriptSnapshot(
                finalText: "",
                partials: [text],
                providerName: "Fake ASR",
                latencyMilliseconds: nil
            ),
            lastInjection: nil,
            lastErrorMessage: nil
        )
    }
}
