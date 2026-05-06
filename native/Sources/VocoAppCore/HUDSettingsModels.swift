import Foundation

public struct HUDSettingsSnapshot: Equatable, Sendable {
    public let position: HUDPositionSetting
    public let notchMode: HUDNotchModeSetting
    public let transcriptPreview: HUDTranscriptPreviewSetting

    public init(
        position: HUDPositionSetting = .bottomCenter,
        notchMode: HUDNotchModeSetting = .legacyCapsule,
        transcriptPreview: HUDTranscriptPreviewSetting = .hiddenInCapsule
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

    public static var bottomCenter: HUDPositionSetting {
        HUDPositionSetting(
            title: "底部居中",
            detail: "HUD 使用旧版 compact 胶囊，固定在屏幕底部中央。",
            systemImage: "arrow.down.to.line.compact"
        )
    }
}

public struct HUDNotchModeSetting: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String

    public static var legacyCapsule: HUDNotchModeSetting {
        HUDNotchModeSetting(
            title: "胶囊模式",
            detail: "使用已调试的黑色胶囊 UI，不贴近 Dynamic Island。",
            systemImage: "capsule.fill"
        )
    }
}

public struct HUDTranscriptPreviewSetting: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let systemImage: String
    public let isVisible: Bool

    public static var hiddenInCapsule: HUDTranscriptPreviewSetting {
        HUDTranscriptPreviewSetting(
            title: "不显示转写预览",
            detail: "胶囊只显示语音输入状态和声波，避免展开成卡片。",
            systemImage: "text.bubble",
            isVisible: false
        )
    }
}
