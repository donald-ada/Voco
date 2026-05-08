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
    public var hud: HUDStrings { HUDStrings(language: language) }
    public var workbench: SettingsWorkbenchStrings { SettingsWorkbenchStrings(language: language) }
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

    public func menuBarTitle(for status: AppRuntimeStatus) -> String {
        switch (language, status) {
        case (.zhHans, .launching):
            "启动中"
        case (.zhHans, .ready):
            "就绪"
        case (.zhHans, .recording):
            "录音中"
        case (.zhHans, .transcribing):
            "转写中"
        case (.zhHans, .injecting):
            "插入中"
        case (.zhHans, .permissionNeeded):
            "需要权限"
        case (.zhHans, .providerOffline):
            "服务离线"
        case (.zhHans, .error):
            "错误"
        case (.en, .launching):
            "Launching"
        case (.en, .ready):
            "Ready"
        case (.en, .recording):
            "Recording"
        case (.en, .transcribing):
            "Transcribing"
        case (.en, .injecting):
            "Inserting"
        case (.en, .permissionNeeded):
            "Permission Needed"
        case (.en, .providerOffline):
            "Service Offline"
        case (.en, .error):
            "Error"
        }
    }
}

public struct HUDStrings: Sendable {
    let language: AppLanguage

    public var recordingTitle: String { language == .zhHans ? "正在听" : "Listening" }
    public var recordingDetail: String { language == .zhHans ? "松开或再次按下快捷键结束录音" : "Release or press the hotkey again to stop recording" }
    public var transcribingTitle: String { language == .zhHans ? "正在转写" : "Transcribing" }
    public var transcribingDetail: String { language == .zhHans ? "正在生成文字" : "Generating text" }
    public var injectingTitle: String { language == .zhHans ? "正在插入" : "Inserting" }
    public var injectingDetail: String { language == .zhHans ? "正在把转写文本插入当前 App" : "Inserting transcribed text into the active app" }
    public var errorTitle: String { language == .zhHans ? "需要处理" : "Needs Attention" }
    public var genericErrorDetail: String { language == .zhHans ? "Voco 遇到错误。" : "Voco encountered an error." }
}

public struct SettingsWorkbenchStrings: Sendable {
    let language: AppLanguage

    public var readyTitle: String { language == .zhHans ? "Voco 已就绪" : "Voco is ready" }
    public var readyDetail: String { language == .zhHans ? "Right Command 可以触发录音、转写和文本输入。" : "Right Command can trigger recording, transcription, and text insertion." }
    public var checkMicrophoneAction: String { language == .zhHans ? "检查麦克风" : "Check Microphone" }
    public var startTestRecordingAction: String { language == .zhHans ? "开始测试录音" : "Start Test Recording" }
    public var refreshAction: String { language == .zhHans ? "重新检查" : "Recheck" }
    public var openModelAction: String { language == .zhHans ? "前往模型" : "Open Model" }
    public var openSettingsAction: String { language == .zhHans ? "前往设置" : "Open Settings" }
    public var openAccessibilitySettingsAction: String { language == .zhHans ? "打开辅助功能设置" : "Open Accessibility Settings" }

    public func permissionMissingTitle(kind: PermissionKind) -> String {
        switch language {
        case .zhHans:
            "\(kind.title(strings: VocoStrings(language: .zhHans)))权限缺失"
        case .en:
            "\(kind.title(strings: VocoStrings(language: .en))) permission missing"
        }
    }

    public func permissionMissingDetail(kind: PermissionKind) -> String {
        switch (language, kind) {
        case (.zhHans, .accessibility):
            "Voco 可以录音，但不能稳定插入当前输入框。"
        case (.zhHans, .microphone):
            "\(kind.title(strings: VocoStrings(language: .zhHans)))权限缺失，语音输入链路无法完成。"
        case (.en, .accessibility):
            "Voco can record, but cannot reliably insert into the current text field."
        case (.en, .microphone):
            "\(kind.title(strings: VocoStrings(language: .en))) permission is missing, so the voice input flow cannot complete."
        }
    }

    public func permissionIssueDetail(kind: PermissionKind) -> String {
        switch (language, kind) {
        case (.zhHans, .accessibility):
            "允许后才能稳定插入当前输入框。"
        case (.zhHans, .microphone):
            "允许后才能完成录音链路。"
        case (.en, .accessibility):
            "Allow it to reliably insert into the current text field."
        case (.en, .microphone):
            "Allow it to complete the recording flow."
        }
    }

    public var credentialMissingTitle: String {
        language == .zhHans ? "火山引擎凭证未保存" : "Volcengine credentials not saved"
    }

    public var credentialReadFailedTitle: String {
        language == .zhHans ? "火山引擎凭证读取失败" : "Volcengine credentials read failed"
    }

    public var credentialMissingDetail: String {
        language == .zhHans ? "Keychain 中没有保存火山引擎凭证。" : "No Volcengine credentials are saved in Keychain."
    }

    public func credentialReadFailedDetail(message: String) -> String {
        switch language {
        case .zhHans:
            "Keychain 访问失败：\(message)"
        case .en:
            "Keychain access failed: \(message)"
        }
    }

    public var transcriptionFailedTitle: String {
        language == .zhHans ? "火山引擎转写失败" : "Volcengine transcription failed"
    }

    public var textInputFailedTitle: String {
        language == .zhHans ? "文本输入失败" : "Text input failed"
    }

    public var recentOperationFailedTitle: String {
        language == .zhHans ? "最近一次操作失败" : "Last operation failed"
    }

    public func credentialTitle(hasError: Bool) -> String {
        hasError ? credentialReadFailedTitle : credentialMissingTitle
    }

    public func credentialDetail(lastErrorMessage: String?) -> String {
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            return credentialReadFailedDetail(message: lastErrorMessage)
        }

        return credentialMissingDetail
    }

    public func providerIssueTitle(for status: TranscriptionProviderStatus) -> String {
        switch (language, status) {
        case (.zhHans, .notConfigured):
            "模型未配置"
        case (.zhHans, .ready(let providerName)):
            "\(providerName)已就绪"
        case (.zhHans, .authenticationRequired(let providerName)):
            "\(providerName)需要认证"
        case (.zhHans, .offline(let providerName)):
            "\(providerName)离线"
        case (.zhHans, .failed(let providerName, _)):
            "\(providerName)转写失败"
        case (.en, .notConfigured):
            "Model not configured"
        case (.en, .ready(let providerName)):
            "\(providerDisplayName(providerName)) ready"
        case (.en, .authenticationRequired(let providerName)):
            "\(providerDisplayName(providerName)) requires authentication"
        case (.en, .offline(let providerName)):
            "\(providerDisplayName(providerName)) offline"
        case (.en, .failed(let providerName, _)):
            "\(providerDisplayName(providerName)) transcription failed"
        }
    }

    public func providerIssueDetail(for status: TranscriptionProviderStatus) -> String {
        switch (language, status) {
        case (.zhHans, .notConfigured):
            "请先配置火山引擎凭证。"
        case (.zhHans, .ready):
            "模型已准备好。"
        case (.zhHans, .authenticationRequired):
            "请检查火山引擎凭证。"
        case (.zhHans, .offline):
            "模型暂不可用，稍后可重试。"
        case (.zhHans, .failed(_, let message)):
            message
        case (.en, .notConfigured):
            "Configure Volcengine credentials first."
        case (.en, .ready):
            "The model is ready."
        case (.en, .authenticationRequired):
            "Check Volcengine credentials."
        case (.en, .offline):
            "The model is temporarily unavailable. Try again later."
        case (.en, .failed(_, let message)):
            message
        }
    }

    public func providerDisplayName(_ providerName: String) -> String {
        switch language {
        case .zhHans:
            providerName
        case .en:
            providerName == "火山引擎" ? "Volcengine" : providerName
        }
    }

    public func transcriptionFailureDetail(_ message: String) -> String {
        message
    }

    public func textInputFailureDetail(_ detail: String) -> String {
        detail
    }

    public func recentOperationFailureDetail(_ detail: String) -> String {
        detail
    }
}

public struct SettingsStrings: Sendable {
    let language: AppLanguage
}
