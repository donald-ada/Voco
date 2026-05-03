import XCTest
@testable import VocoHUDCore

final class HudEventTests: XCTestCase {
    func testDecodesStateEventWithoutMessage() throws {
        let event = try HudEvent.decodeLine(#"{"type":"state","state":"recording"}"#)
        XCTAssertEqual(event, .state(.recording, message: nil))
    }

    func testDecodesStateEventWithMessage() throws {
        let event = try HudEvent.decodeLine(#"{"type":"state","state":"error","message":"microphone unavailable"}"#)
        XCTAssertEqual(event, .state(.error, message: "microphone unavailable"))
    }

    func testDecodesAmplitudeEvent() throws {
        let event = try HudEvent.decodeLine(#"{"type":"amplitude","value":0.42}"#)
        XCTAssertEqual(event, .amplitude(0.42))
    }

    func testRejectsUnknownEventType() {
        XCTAssertThrowsError(try HudEvent.decodeLine(#"{"type":"unknown"}"#))
    }
}

@MainActor
final class HudModelTests: XCTestCase {
    func testAmplitudeIsClamped() {
        let model = HudModel()
        model.apply(.amplitude(1.8))
        XCTAssertEqual(model.amplitude, 1.0)
        model.apply(.amplitude(-0.4))
        XCTAssertEqual(model.amplitude, 0.0)
    }

    func testHiddenStateClearsVisibility() {
        let model = HudModel()
        model.apply(.state(.recording, message: nil))
        XCTAssertTrue(model.isVisible)
        model.apply(.state(.hidden, message: nil))
        XCTAssertFalse(model.isVisible)
    }

    func testHiddenStateClearsAmplitudeAndMessage() {
        let model = HudModel()
        model.apply(.amplitude(0.7))
        model.apply(.state(.error, message: "microphone unavailable"))
        model.apply(.state(.hidden, message: nil))
        XCTAssertEqual(model.amplitude, 0.0)
        XCTAssertNil(model.message)
    }

    func testVisibleStateIncrementsPresentationEpoch() {
        let model = HudModel()

        XCTAssertEqual(model.presentationEpoch, 0)
        model.apply(.state(.recording, message: nil))

        XCTAssertEqual(model.presentationEpoch, 1)
        XCTAssertTrue(model.isVisible)
    }

    func testAmplitudeDoesNotChangePresentationEpoch() {
        let model = HudModel()

        model.apply(.state(.recording, message: nil))
        model.apply(.amplitude(0.5))

        XCTAssertEqual(model.presentationEpoch, 1)
    }

    func testRecordingToTranscribingDoesNotRestartEntryAnimation() {
        let model = HudModel()

        model.apply(.state(.recording, message: nil))
        model.apply(.state(.transcribing, message: nil))

        XCTAssertEqual(model.presentationEpoch, 1)
        XCTAssertEqual(model.state, .transcribing)
    }
}

final class HudThemeTests: XCTestCase {
    func testB2CompactLayoutTokens() {
        XCTAssertEqual(HudTheme.Layout.capsuleWidth, 196)
        XCTAssertEqual(HudTheme.Layout.capsuleHeight, 48)
        XCTAssertEqual(HudTheme.Layout.micGlyphSize, 22)
        XCTAssertEqual(HudTheme.Layout.waveformWidth, 58)
        XCTAssertEqual(HudTheme.Layout.waveformBarCount, 7)
    }

    func testBlackYellowGreenColorTokens() {
        XCTAssertEqual(HudTheme.ColorToken.capsule.hex, "#050607")
        XCTAssertEqual(HudTheme.ColorToken.recordingMic.hex, "#FFCC4D")
        XCTAssertEqual(HudTheme.ColorToken.waveform.hex, "#32D67A")
    }
}
