import Foundation

public struct HUDSettingsSnapshot: Equatable, Sendable {
    public let position: HUDPositionSetting
    public let notchMode: HUDNotchModeSetting
    public let transcriptPreview: HUDTranscriptPreviewSetting

    public init(
        position: HUDPositionSetting = .topCenter,
        notchMode: HUDNotchModeSetting = .notchAware,
        transcriptPreview: HUDTranscriptPreviewSetting = .enabled
    ) {
        self.position = position
        self.notchMode = notchMode
        self.transcriptPreview = transcriptPreview
    }
}

public struct HUDPositionSetting: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String

    public static var topCenter: HUDPositionSetting {
        HUDPositionSetting(
            title: "顶部居中",
            detail: "HUD 固定显示在屏幕顶部中央。",
            systemImage: "arrow.up.to.line.compact"
        )
    }
}

public struct HUDNotchModeSetting: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String

    public static var notchAware: HUDNotchModeSetting {
        HUDNotchModeSetting(
            title: "刘海避让",
            detail: "在带刘海屏幕上自动贴近 Dynamic Island 区域。",
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
        HUDTranscriptPreviewSetting(
            title: "显示转写预览",
            detail: "录音和插入过程中显示最多 80 个字符的实时文本。",
            systemImage: "text.bubble",
            isVisible: true
        )
    }
}
