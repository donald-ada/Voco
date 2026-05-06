import CoreGraphics
import SwiftUI

enum HUDOverlayChrome {
    enum Layout {
        static let capsuleWidth: CGFloat = 184
        static let capsuleHeight: CGFloat = 44
        static let shadowPadding: CGFloat = 22
        static let panelSize = CGSize(
            width: capsuleWidth + shadowPadding * 2,
            height: capsuleHeight + shadowPadding * 2
        )
        static let statusLabelText = "语音输入"
        static let statusLabelFontSize: CGFloat = 14
        static let waveformWidth: CGFloat = 48
        static let waveformHeight: CGFloat = 30
        static let waveformBarWidth: CGFloat = 2.4
        static let waveformBarSpacing: CGFloat = 3
        static let waveformBarCount = 7
        static let contentSpacing: CGFloat = 12
        static let panelBottomOffset: CGFloat = 96
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

        static let capsule = ColorToken(
            hex: "#050607",
            red: 5.0 / 255.0,
            green: 6.0 / 255.0,
            blue: 7.0 / 255.0,
            opacity: 0.92
        )
        static let capsuleBorder = ColorToken(
            hex: "#1B1F22",
            red: 27.0 / 255.0,
            green: 31.0 / 255.0,
            blue: 34.0 / 255.0,
            opacity: 0.95
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
        static let error = ColorToken(
            hex: "#FF5E57",
            red: 255.0 / 255.0,
            green: 94.0 / 255.0,
            blue: 87.0 / 255.0,
            opacity: 1.0
        )
    }

    static func panelOrigin(visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: visibleFrame.midX - Layout.panelSize.width / 2,
            y: visibleFrame.minY + Layout.panelBottomOffset - Layout.shadowPadding
        )
    }
}
