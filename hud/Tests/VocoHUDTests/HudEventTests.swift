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

    func testDecodesTranscriptEvent() throws {
        let event = try HudEvent.decodeLine(#"{"type":"transcript","text":"你好世界","stable_prefix_len":6}"#)
        XCTAssertEqual(event, .transcript(text: "你好世界", stablePrefixLen: 6))
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

    func testTranscriptDoesNotChangePresentationEpoch() {
        let model = HudModel()

        model.apply(.state(.recording, message: nil))
        model.apply(.transcript(text: "你好世界", stablePrefixLen: 6))

        XCTAssertEqual(model.presentationEpoch, 1)
        XCTAssertEqual(model.transcriptText, "你好世界")
        XCTAssertEqual(model.stablePrefixLen, 6)
    }

    func testHiddenStateClearsTranscript() {
        let model = HudModel()

        model.apply(.state(.recording, message: nil))
        model.apply(.transcript(text: "你好世界", stablePrefixLen: 6))
        model.apply(.state(.hidden, message: nil))

        XCTAssertEqual(model.transcriptText, "")
        XCTAssertEqual(model.stablePrefixLen, 0)
    }

    func testTranscriptDisplaySplitsUtf8StablePrefix() {
        let model = HudModel()

        model.apply(.transcript(text: "你好世界", stablePrefixLen: 6))

        XCTAssertEqual(model.transcriptDisplay.stable, "你好")
        XCTAssertEqual(model.transcriptDisplay.live, "世界")
    }

    func testTranscriptDisplayFallsBackToCharacterBoundaryForInvalidUtf8Prefix() {
        let model = HudModel()

        model.apply(.transcript(text: "你好世界", stablePrefixLen: 7))

        XCTAssertEqual(model.transcriptDisplay.stable, "你好")
        XCTAssertEqual(model.transcriptDisplay.live, "世界")
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
    func testRecordingStateShowsTopHudOnly() {
        let action = HudPresentationPolicy.action(for: .state(.recording, message: nil), isVisible: true)

        XCTAssertEqual(action.topPanel, .show)
        XCTAssertFalse(action.autoHideError)
    }

    func testErrorStateShowsTopHudBeforeAutoHide() {
        let action = HudPresentationPolicy.action(
            for: .state(.error, message: "microphone unavailable"),
            isVisible: true
        )

        XCTAssertEqual(action.topPanel, .show)
        XCTAssertTrue(action.autoHideError)
    }

    func testTranscriptUpdatesShowTopHudOnlyWhenModelIsVisible() {
        XCTAssertEqual(
            HudPresentationPolicy.action(
                for: .transcript(text: "你好", stablePrefixLen: 6),
                isVisible: true
            ).topPanel,
            .show
        )
        XCTAssertEqual(
            HudPresentationPolicy.action(
                for: .transcript(text: "你好", stablePrefixLen: 6),
                isVisible: false
            ).topPanel,
            .hide
        )
    }

    func testNotchPanelUsesFullScreenFrameInsteadOfVisibleFrame() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let visibleFrame = CGRect(x: 0, y: 74, width: 1728, height: 1006)
        let panelSize = CGSize(
            width: HudTheme.Layout.notchPanelWidth,
            height: HudTheme.Layout.notchPanelHeight
        )

        let origin = HudPanelPositioning.notchOrigin(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            panelSize: panelSize
        )

        XCTAssertEqual(origin.x, screenFrame.midX - panelSize.width / 2)
        XCTAssertEqual(
            origin.y,
            screenFrame.maxY - panelSize.height + HudTheme.Layout.notchShadowPadding - HudTheme.Layout.notchTopOffset
        )
        XCTAssertNotEqual(
            origin.y,
            visibleFrame.maxY - panelSize.height + HudTheme.Layout.notchShadowPadding - HudTheme.Layout.notchTopOffset
        )
    }

    func testNotchCapsuleBleedsPastScreenTopToAvoidAntialiasGap() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let visibleFrame = CGRect(x: 0, y: 66, width: 1728, height: 1018)
        let panelSize = CGSize(
            width: HudTheme.Layout.notchPanelWidth,
            height: HudTheme.Layout.notchPanelHeight
        )

        let origin = HudPanelPositioning.notchOrigin(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            panelSize: panelSize
        )
        let capsuleTopY = origin.y + panelSize.height - HudTheme.Layout.notchShadowPadding

        XCTAssertEqual(capsuleTopY, screenFrame.maxY + 1)
    }

    func testDynamicIslandLayoutTokens() {
        XCTAssertEqual(HudTheme.Layout.statusLabelText, "语音输入")
        XCTAssertEqual(HudTheme.Layout.waveformWidth, 48)
        XCTAssertEqual(HudTheme.Layout.waveformBarWidth, 2.4)
        XCTAssertEqual(HudTheme.Layout.waveformBarSpacing, 3)
        XCTAssertEqual(HudTheme.Layout.waveformBarCount, 7)
    }

    func testNotchTranscriptIslandLayoutTokens() {
        XCTAssertEqual(HudTheme.Layout.notchCollapsedWidth, 320)
        XCTAssertEqual(HudTheme.Layout.notchCollapsedHeight, 44)
        XCTAssertEqual(HudTheme.Layout.notchExpandedWidth, 520)
        XCTAssertEqual(HudTheme.Layout.notchExpandedHeight, 86)
        XCTAssertEqual(HudTheme.Layout.notchShadowPadding, 24)
        XCTAssertEqual(
            HudTheme.Layout.notchPanelWidth,
            HudTheme.Layout.notchExpandedWidth + HudTheme.Layout.notchShadowPadding * 2
        )
        XCTAssertEqual(
            HudTheme.Layout.notchPanelHeight,
            HudTheme.Layout.notchExpandedHeight + HudTheme.Layout.notchShadowPadding * 2
        )
        XCTAssertEqual(HudTheme.Layout.notchTopOffset, -1)
        XCTAssertEqual(HudTheme.Layout.transcriptFontSize, 17)
        XCTAssertEqual(HudTheme.Layout.transcriptLineLimit, 2)
    }

    func testBlackYellowGreenColorTokens() {
        XCTAssertEqual(HudTheme.ColorToken.notchCapsule.hex, "#000000")
        XCTAssertEqual(HudTheme.ColorToken.recordingMic.hex, "#FFCC4D")
        XCTAssertEqual(HudTheme.ColorToken.waveform.hex, "#32D67A")
        XCTAssertEqual(HudTheme.ColorToken.transcriptStable.hex, "#F8F1D4")
        XCTAssertEqual(HudTheme.ColorToken.transcriptLive.hex, "#8DFFB5")
    }

    func testNotchCapsuleUsesOpaqueBlackTokens() {
        XCTAssertEqual(HudTheme.ColorToken.notchCapsule.hex, "#000000")
        XCTAssertEqual(HudTheme.ColorToken.notchCapsule.opacity, 1.0)
        XCTAssertEqual(HudTheme.ColorToken.notchCapsuleBorder.hex, "#000000")
        XCTAssertEqual(HudTheme.ColorToken.notchCapsuleBorder.opacity, 0.0)
    }
}
