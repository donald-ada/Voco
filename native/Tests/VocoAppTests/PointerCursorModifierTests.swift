import AppKit
import XCTest
@testable import VocoApp

final class PointerCursorModifierTests: XCTestCase {
    func testInteractivePointerCursorUsesPointingHand() {
        XCTAssertIdentical(SettingsWorkbenchPointerCursor.interactive.nsCursor, NSCursor.pointingHand)
    }
}
