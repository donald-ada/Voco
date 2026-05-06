import Foundation

public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case hotkey
    case audio
    case transcription
    case injection
    case hud
    case privacy
    case diagnostics

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .general:
            "通用"
        case .hotkey:
            "快捷键"
        case .audio:
            "音频"
        case .transcription:
            "转写"
        case .injection:
            "输入"
        case .hud:
            "HUD"
        case .privacy:
            "隐私"
        case .diagnostics:
            "诊断"
        }
    }

    public var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .hotkey:
            "keyboard"
        case .audio:
            "mic"
        case .transcription:
            "text.bubble"
        case .injection:
            "text.cursor"
        case .hud:
            "rectangle.inset.filled"
        case .privacy:
            "lock"
        case .diagnostics:
            "stethoscope"
        }
    }
}
