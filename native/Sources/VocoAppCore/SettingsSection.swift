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

    public var summary: String {
        switch self {
        case .general:
            "启动和基础状态"
        case .hotkey:
            "快捷键监听和触发模式"
        case .audio:
            "输入设备、电平和采样率"
        case .transcription:
            "ASR provider 和凭证"
        case .injection:
            "插入策略和聚焦 App 诊断"
        case .hud:
            "位置、刘海模式和转写预览"
        case .privacy:
            "Keychain、转写保留和日志策略"
        case .diagnostics:
            "最近录音、转写和错误"
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
