import CoreGraphics
import XCTest
@testable import VocoApp

final class HUDOverlayChromeTests: XCTestCase {
    func testCapsuleUsesLegacyCompactLayoutTokens() {
        XCTAssertEqual(HUDOverlayChrome.Layout.capsuleWidth, 184)
        XCTAssertEqual(HUDOverlayChrome.Layout.capsuleHeight, 44)
        XCTAssertEqual(HUDOverlayChrome.Layout.shadowPadding, 22)
        XCTAssertEqual(HUDOverlayChrome.Layout.panelSize.width, 228)
        XCTAssertEqual(HUDOverlayChrome.Layout.panelSize.height, 88)
        XCTAssertEqual(HUDOverlayChrome.Layout.statusLabelText, "语音输入")
        XCTAssertEqual(HUDOverlayChrome.Layout.statusLabelFontSize, 14)
        XCTAssertEqual(HUDOverlayChrome.Layout.waveformWidth, 48)
        XCTAssertEqual(HUDOverlayChrome.Layout.waveformHeight, 30)
        XCTAssertEqual(HUDOverlayChrome.Layout.waveformBarWidth, 2.4)
        XCTAssertEqual(HUDOverlayChrome.Layout.waveformBarSpacing, 3)
        XCTAssertEqual(HUDOverlayChrome.Layout.waveformBarCount, 7)
        XCTAssertEqual(HUDOverlayChrome.Layout.contentSpacing, 12)
    }

    func testCapsuleUsesLegacyBlackYellowGreenTokens() {
        XCTAssertEqual(HUDOverlayChrome.ColorToken.capsule.hex, "#050607")
        XCTAssertEqual(HUDOverlayChrome.ColorToken.capsule.opacity, 0.92)
        XCTAssertEqual(HUDOverlayChrome.ColorToken.capsuleBorder.hex, "#1B1F22")
        XCTAssertEqual(HUDOverlayChrome.ColorToken.recordingMic.hex, "#FFCC4D")
        XCTAssertEqual(HUDOverlayChrome.ColorToken.waveform.hex, "#32D67A")
        XCTAssertEqual(HUDOverlayChrome.ColorToken.error.hex, "#FF5E57")
    }

    func testCapsulePanelIsBottomCenteredWithShadowPadding() {
        let visibleFrame = CGRect(x: 0, y: 74, width: 1728, height: 1006)

        let origin = HUDOverlayChrome.panelOrigin(visibleFrame: visibleFrame)

        XCTAssertEqual(origin.x, visibleFrame.midX - HUDOverlayChrome.Layout.panelSize.width / 2)
        XCTAssertEqual(
            origin.y,
            visibleFrame.minY
                + HUDOverlayChrome.Layout.panelBottomOffset
                - HUDOverlayChrome.Layout.shadowPadding
        )
    }
}
