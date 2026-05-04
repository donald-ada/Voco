import CoreGraphics
import SwiftUI

public enum HudTheme {
    public enum Layout {
        public static let capsuleWidth: CGFloat = 184
        public static let capsuleHeight: CGFloat = 44
        public static let shadowPadding: CGFloat = 22
        public static let panelWidth: CGFloat = capsuleWidth + shadowPadding * 2
        public static let panelHeight: CGFloat = capsuleHeight + shadowPadding * 2
        public static let micGlyphSize: CGFloat = 22
        public static let statusLabelText = "语音输入"
        public static let statusLabelFontSize: CGFloat = 14
        public static let waveformWidth: CGFloat = 48
        public static let waveformHeight: CGFloat = 30
        public static let waveformBarWidth: CGFloat = 2.4
        public static let waveformBarSpacing: CGFloat = 3
        public static let waveformBarCount = 7
        public static let contentSpacing: CGFloat = 12
        public static let panelBottomOffset: CGFloat = 96
    }

    public struct ColorToken: Equatable, Sendable {
        public let hex: String
        public let red: Double
        public let green: Double
        public let blue: Double
        public let opacity: Double

        public var color: Color {
            Color(red: red, green: green, blue: blue).opacity(opacity)
        }

        public static let capsule = ColorToken(
            hex: "#050607",
            red: 5.0 / 255.0,
            green: 6.0 / 255.0,
            blue: 7.0 / 255.0,
            opacity: 0.92
        )
        public static let capsuleBorder = ColorToken(
            hex: "#1B1F22",
            red: 27.0 / 255.0,
            green: 31.0 / 255.0,
            blue: 34.0 / 255.0,
            opacity: 0.95
        )
        public static let recordingMic = ColorToken(
            hex: "#FFCC4D",
            red: 255.0 / 255.0,
            green: 204.0 / 255.0,
            blue: 77.0 / 255.0,
            opacity: 1.0
        )
        public static let waveform = ColorToken(
            hex: "#32D67A",
            red: 50.0 / 255.0,
            green: 214.0 / 255.0,
            blue: 122.0 / 255.0,
            opacity: 1.0
        )
        public static let error = ColorToken(
            hex: "#FF5E57",
            red: 255.0 / 255.0,
            green: 94.0 / 255.0,
            blue: 87.0 / 255.0,
            opacity: 1.0
        )
    }
}
