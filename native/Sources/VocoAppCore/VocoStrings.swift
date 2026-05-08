import Foundation

public struct VocoStrings: Sendable {
    public let language: AppLanguage

    public init(language: AppLanguage = .default) {
        self.language = language
    }

    public var app: AppStrings { AppStrings(language: language) }
    public var permissions: PermissionStrings { PermissionStrings(language: language) }
    public var hotkeys: HotkeyStrings { HotkeyStrings(language: language) }
    public var runtime: RuntimeStrings { RuntimeStrings(language: language) }
    public var settings: SettingsStrings { SettingsStrings(language: language) }
}

public struct AppStrings: Sendable {
    let language: AppLanguage

    public var showSettingsMenuTitle: String {
        switch language {
        case .zhHans:
            "显示 Voco"
        case .en:
            "Show Voco"
        }
    }

    public var quitMenuTitle: String {
        switch language {
        case .zhHans:
            "退出"
        case .en:
            "Quit"
        }
    }

    public var settingsWindowTitle: String {
        switch language {
        case .zhHans:
            "Voco 设置"
        case .en:
            "Voco Settings"
        }
    }
}

public struct PermissionStrings: Sendable {
    let language: AppLanguage

    public func title(for kind: PermissionKind) -> String {
        switch (language, kind) {
        case (.zhHans, .microphone):
            "麦克风"
        case (.zhHans, .accessibility):
            "辅助功能"
        case (.en, .microphone):
            "Microphone"
        case (.en, .accessibility):
            "Accessibility"
        }
    }

    public func description(for kind: PermissionKind) -> String {
        switch (language, kind) {
        case (.zhHans, .microphone):
            "用于录制语音并生成转写文本。"
        case (.zhHans, .accessibility):
            "用于把转写文本插入当前正在输入的 App。"
        case (.en, .microphone):
            "Used to record voice and create transcribed text."
        case (.en, .accessibility):
            "Used to insert transcribed text into the active app."
        }
    }

    public func recoveryActionTitle(for kind: PermissionKind) -> String {
        switch (language, kind) {
        case (.zhHans, .microphone):
            "打开麦克风设置"
        case (.zhHans, .accessibility):
            "打开辅助功能设置"
        case (.en, .microphone):
            "Open Microphone Settings"
        case (.en, .accessibility):
            "Open Accessibility Settings"
        }
    }

    public func title(for state: PermissionGrantState) -> String {
        switch (language, state) {
        case (.zhHans, .notDetermined):
            "未决定"
        case (.zhHans, .granted):
            "已允许"
        case (.zhHans, .denied):
            "已拒绝"
        case (.zhHans, .restricted):
            "受限制"
        case (.zhHans, .unknown):
            "未知"
        case (.en, .notDetermined):
            "Not Determined"
        case (.en, .granted):
            "Allowed"
        case (.en, .denied):
            "Denied"
        case (.en, .restricted):
            "Restricted"
        case (.en, .unknown):
            "Unknown"
        }
    }
}

public struct HotkeyStrings: Sendable {
    let language: AppLanguage

    public func title(for mode: HotkeyMode) -> String {
        switch (language, mode) {
        case (.zhHans, .toggle):
            "切换录音"
        case (.zhHans, .pressAndHold):
            "按住录音"
        case (.en, .toggle):
            "Toggle Recording"
        case (.en, .pressAndHold):
            "Press and Hold"
        }
    }

    public func title(for state: HotkeyRuntimeState) -> String {
        switch (language, state) {
        case (.zhHans, .inactive):
            "未监听"
        case (.zhHans, .listening):
            "监听中"
        case (.zhHans, .permissionNeeded):
            "需要权限"
        case (.zhHans, .failed):
            "出错"
        case (.en, .inactive):
            "Inactive"
        case (.en, .listening):
            "Listening"
        case (.en, .permissionNeeded):
            "Permission Needed"
        case (.en, .failed):
            "Error"
        }
    }

    public func detail(for state: HotkeyRuntimeState) -> String {
        switch (language, state) {
        case (.zhHans, .inactive):
            "快捷键监听未启动。"
        case (.zhHans, .listening):
            "Voco 正在监听全局快捷键。"
        case (.zhHans, .permissionNeeded):
            "需要辅助功能权限才能监听全局快捷键。"
        case (.zhHans, .failed(let message)):
            message
        case (.en, .inactive):
            "Hotkey listening is not running."
        case (.en, .listening):
            "Voco is listening for the global hotkey."
        case (.en, .permissionNeeded):
            "Accessibility permission is required to listen for the global hotkey."
        case (.en, .failed(let message)):
            message
        }
    }
}

public struct RuntimeStrings: Sendable {
    let language: AppLanguage
}

public struct SettingsStrings: Sendable {
    let language: AppLanguage
}
