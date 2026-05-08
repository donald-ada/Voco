import CoreGraphics
import SwiftUI

enum HUDOverlayChrome {
    enum Layout {
        static let statusLabelText = "语音输入"
        static let waveformWidth: CGFloat = 48
        static let waveformHeight: CGFloat = 30
        static let waveformRefreshInterval = 1.0 / 30.0
        static let waveformBarWidth: CGFloat = 2.4
        static let waveformBarSpacing: CGFloat = 3
        static let waveformBarCount = 7
        static let contentSpacing: CGFloat = 12
        static let notchCollapsedWidth: CGFloat = 320
        static let notchCollapsedHeight: CGFloat = 44
        static let notchExpandedWidth: CGFloat = 520
        static let notchExpandedHeight: CGFloat = 86
        static let notchShadowPadding: CGFloat = 24
        static let panelSize = CGSize(
            width: notchExpandedWidth + notchShadowPadding * 2,
            height: notchExpandedHeight + notchShadowPadding * 2
        )
        static let notchTopOffset: CGFloat = -1
        static let transcriptFontSize: CGFloat = 17
        static let transcriptStatusFontSize: CGFloat = 13
        static let transcriptLineLimit = 1
        static let transcriptRevealOffsetY: CGFloat = -5
    }

    struct ColorToken: Equatable, Sendable {
        let hex: String
        let red: Double
        let green: Double
        let blue: Double
        let opacity: Double

        var color: Color {
            Color(red: red, green: green, blue: blue).opacity(opacity)
        }

        static let notchCapsule = ColorToken(
            hex: "#000000",
            red: 0.0,
            green: 0.0,
            blue: 0.0,
            opacity: 1.0
        )
        static let notchCapsuleBorder = ColorToken(
            hex: "#000000",
            red: 0.0,
            green: 0.0,
            blue: 0.0,
            opacity: 0.0
        )
        static let recordingMic = ColorToken(
            hex: "#FFCC4D",
            red: 255.0 / 255.0,
            green: 204.0 / 255.0,
            blue: 77.0 / 255.0,
            opacity: 1.0
        )
        static let waveform = ColorToken(
            hex: "#32D67A",
            red: 50.0 / 255.0,
            green: 214.0 / 255.0,
            blue: 122.0 / 255.0,
            opacity: 1.0
        )
        static let transcriptStable = ColorToken(
            hex: "#F8F1D4",
            red: 248.0 / 255.0,
            green: 241.0 / 255.0,
            blue: 212.0 / 255.0,
            opacity: 1.0
        )
        static let transcriptLive = ColorToken(
            hex: "#8DFFB5",
            red: 141.0 / 255.0,
            green: 255.0 / 255.0,
            blue: 181.0 / 255.0,
            opacity: 1.0
        )
        static let error = ColorToken(
            hex: "#FF5E57",
            red: 255.0 / 255.0,
            green: 94.0 / 255.0,
            blue: 87.0 / 255.0,
            opacity: 1.0
        )
    }

    static func panelOrigin(screenFrame: CGRect, visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: visibleFrame.midX - Layout.panelSize.width / 2,
            y: screenFrame.maxY
                - Layout.panelSize.height
                + Layout.notchShadowPadding
                - Layout.notchTopOffset
        )
    }
}
