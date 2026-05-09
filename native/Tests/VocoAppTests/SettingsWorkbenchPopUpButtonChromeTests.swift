import AppKit
import XCTest
@testable import VocoApp

@MainActor
final class SettingsWorkbenchPopUpButtonChromeTests: XCTestCase {
    func testTransparentOverlayPopUpButtonDoesNotDrawNativeArrows() {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)

        SettingsWorkbenchPopUpButtonChrome.apply(to: button)

        XCTAssertFalse(button.isBordered)
        XCTAssertTrue(button.isTransparent)
        XCTAssertEqual(button.focusRingType, .none)
        XCTAssertEqual((button.cell as? NSPopUpButtonCell)?.arrowPosition, .noArrow)
    }
}
