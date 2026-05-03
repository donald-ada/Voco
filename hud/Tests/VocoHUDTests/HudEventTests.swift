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
