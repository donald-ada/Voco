import Foundation

public struct HUDSettingsSnapshot: Equatable, Sendable {
    public let position: HUDPositionSetting
    public let notchMode: HUDNotchModeSetting
    public let transcriptPreview: HUDTranscriptPreviewSetting

    public init(
        position: HUDPositionSetting? = nil,
        notchMode: HUDNotchModeSetting? = nil,
        transcriptPreview: HUDTranscriptPreviewSetting? = nil,
        strings: VocoStrings = VocoStrings()
    ) {
        self.position = position ?? .topCenter(strings: strings)
        self.notchMode = notchMode ?? .notchAware(strings: strings)
        self.transcriptPreview = transcriptPreview ?? .enabled(strings: strings)
    }
}

public struct HUDPositionSetting: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String

    public static var topCenter: HUDPositionSetting {
        topCenter(strings: VocoStrings())
    }

    public static func topCenter(strings: VocoStrings = VocoStrings()) -> HUDPositionSetting {
        HUDPositionSetting(
            title: strings.hud.topCenterTitle,
            detail: strings.hud.topCenterDetail,
            systemImage: "arrow.up.to.line.compact"
        )
    }
}

public struct HUDNotchModeSetting: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String

    public static var notchAware: HUDNotchModeSetting {
        notchAware(strings: VocoStrings())
    }

    public static func notchAware(strings: VocoStrings = VocoStrings()) -> HUDNotchModeSetting {
        HUDNotchModeSetting(
            title: strings.hud.notchAwareTitle,
            detail: strings.hud.notchAwareDetail,
            systemImage: "rectangle.topthird.inset.filled"
        )
    }
}

public struct HUDTranscriptPreviewSetting: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String
    public let isVisible: Bool

    public static var enabled: HUDTranscriptPreviewSetting {
        enabled(strings: VocoStrings())
    }

    public static func enabled(strings: VocoStrings = VocoStrings()) -> HUDTranscriptPreviewSetting {
        HUDTranscriptPreviewSetting(
            title: strings.hud.transcriptPreviewTitle,
            detail: strings.hud.transcriptPreviewDetail,
            systemImage: "text.bubble",
            isVisible: true
        )
    }
}
