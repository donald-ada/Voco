import CoreGraphics
import XCTest
@testable import VocoApp
@testable import VocoAppCore

final class HUDOverlayChromeTests: XCTestCase {
    func testNotchIslandUsesLatestTopLayoutTokens() {
        XCTAssertEqual(HUDOverlayChrome.Layout.waveformWidth, 48)
        XCTAssertEqual(HUDOverlayChrome.Layout.waveformHeight, 30)
        XCTAssertEqual(HUDOverlayChrome.Layout.waveformRefreshInterval, 1.0 / 30.0)
        XCTAssertEqual(HUDOverlayChrome.Layout.waveformBarWidth, 2.4)
        XCTAssertEqual(HUDOverlayChrome.Layout.waveformBarSpacing, 3)
        XCTAssertEqual(HUDOverlayChrome.Layout.waveformBarCount, 7)
        XCTAssertEqual(HUDOverlayChrome.Layout.contentSpacing, 12)
        XCTAssertEqual(HUDOverlayChrome.Layout.notchCollapsedWidth, 320)
        XCTAssertEqual(HUDOverlayChrome.Layout.notchCollapsedHeight, 44)
        XCTAssertEqual(HUDOverlayChrome.Layout.notchExpandedWidth, 520)
        XCTAssertEqual(HUDOverlayChrome.Layout.notchExpandedHeight, 86)
        XCTAssertEqual(HUDOverlayChrome.Layout.notchShadowPadding, 24)
        XCTAssertEqual(HUDOverlayChrome.Layout.panelSize.width, 568)
        XCTAssertEqual(HUDOverlayChrome.Layout.panelSize.height, 134)
        XCTAssertEqual(HUDOverlayChrome.Layout.notchTopOffset, -1)
        XCTAssertEqual(HUDOverlayChrome.Layout.transcriptStatusFontSize, 13)
        XCTAssertEqual(HUDOverlayChrome.Layout.transcriptFontSize, 17)
        XCTAssertEqual(HUDOverlayChrome.Layout.transcriptLineLimit, 1)
        XCTAssertEqual(HUDOverlayChrome.Layout.transcriptRevealOffsetY, -5)
    }

    func testHUDOverlayChromeStatusLabelIsLocalized() {
        XCTAssertEqual(HUDOverlayChrome.Layout.statusLabelText(strings: VocoStrings(language: .zhHans)), "语音输入")
        XCTAssertEqual(HUDOverlayChrome.Layout.statusLabelText(strings: VocoStrings(language: .en)), "Voice Input")
    }

    func testNotchIslandUsesLatestBlackYellowGreenTokens() {
        XCTAssertEqual(HUDOverlayChrome.ColorToken.notchCapsule.hex, "#000000")
        XCTAssertEqual(HUDOverlayChrome.ColorToken.notchCapsule.opacity, 1.0)
        XCTAssertEqual(HUDOverlayChrome.ColorToken.notchCapsuleBorder.hex, "#000000")
        XCTAssertEqual(HUDOverlayChrome.ColorToken.notchCapsuleBorder.opacity, 0.0)
        XCTAssertEqual(HUDOverlayChrome.ColorToken.recordingMic.hex, "#FFCC4D")
        XCTAssertEqual(HUDOverlayChrome.ColorToken.waveform.hex, "#32D67A")
        XCTAssertEqual(HUDOverlayChrome.ColorToken.transcriptStable.hex, "#F8F1D4")
        XCTAssertEqual(HUDOverlayChrome.ColorToken.transcriptLive.hex, "#8DFFB5")
        XCTAssertEqual(HUDOverlayChrome.ColorToken.error.hex, "#FF5E57")
    }

    func testWaveformAnimationIsDisabledWhenHUDIsHidden() {
        XCTAssertFalse(HUDOverlayChrome.waveformAnimates(for: .hidden))
        XCTAssertTrue(HUDOverlayChrome.waveformAnimates(for: .recording))
        XCTAssertTrue(HUDOverlayChrome.waveformAnimates(for: .transcribing))
        XCTAssertTrue(HUDOverlayChrome.waveformAnimates(for: .error))
    }

    func testNotchIslandPanelIsTopCenteredAndBleedsPastScreenTop() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let visibleFrame = CGRect(x: 0, y: 74, width: 1728, height: 1006)

        let origin = HUDOverlayChrome.panelOrigin(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )
        let capsuleTopY = origin.y
            + HUDOverlayChrome.Layout.panelSize.height
            - HUDOverlayChrome.Layout.notchShadowPadding

        XCTAssertEqual(origin.x, visibleFrame.midX - HUDOverlayChrome.Layout.panelSize.width / 2)
        XCTAssertEqual(
            origin.y,
            screenFrame.maxY
                - HUDOverlayChrome.Layout.panelSize.height
                + HUDOverlayChrome.Layout.notchShadowPadding
                - HUDOverlayChrome.Layout.notchTopOffset
        )
        XCTAssertEqual(capsuleTopY, screenFrame.maxY + 1)
    }
}
