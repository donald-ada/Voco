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
}
