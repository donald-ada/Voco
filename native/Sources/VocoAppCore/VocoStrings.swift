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
    public var audio: AudioSettingsStrings { AudioSettingsStrings(language: language) }
    public var credentials: CredentialStrings { CredentialStrings(language: language) }
    public var transcription: TranscriptionStatusStrings { TranscriptionStatusStrings(language: language) }
    public var injection: InjectionSettingsStrings { InjectionSettingsStrings(language: language) }
    public var skills: SkillStrings { SkillStrings(language: language) }
    public var statistics: StatisticsStrings { StatisticsStrings(language: language) }
    public var sessions: SessionStrings { SessionStrings(language: language) }
    public var installLocation: InstallLocationStrings { InstallLocationStrings(language: language) }
    public var legacyInstall: LegacyInstallStrings { LegacyInstallStrings(language: language) }
}

private func localizedDiagnosticDetail(_ detail: String, language: AppLanguage) -> String {
    guard language == .en else {
        return detail
    }

    switch detail {
    case "Keychain 中没有保存火山引擎凭证。":
        return "No Volcengine credentials are saved in Keychain."
    case "Keychain 中没有保存火山引擎 API Key。":
        return "No Volcengine API Key is saved in Keychain."
    case "Keychain 返回的数据格式无效。":
        return "Keychain returned data in an invalid format."
    case "Keychain 返回的数据不是 JSON 或 UTF-8 文本。":
        return "Keychain returned data that was not JSON or UTF-8 text."
    case "无法定位 Application Support 目录。":
        return "Unable to locate the Application Support directory."
    case "数据库中存在格式无效的会话记录。":
        return "The database contains an invalid session record."
    default:
        break
    }

    let handshakePrefix = "OpenSpeech WebSocket 握手被服务端拒绝。请检查火山引擎凭证，并确认 Resource ID 已开通。"
    if detail.hasPrefix(handshakePrefix) {
        let suffix = detail.dropFirst(handshakePrefix.count)
        let separator = suffix.isEmpty ? "" : " "
        return "OpenSpeech WebSocket handshake was rejected by the server. Check Volcengine credentials and confirm the Resource ID is enabled.\(separator)\(suffix)"
    }

    let shortHandshakePrefix = "OpenSpeech WebSocket 握手被服务端拒绝。"
    if detail.hasPrefix(shortHandshakePrefix) {
        let suffix = detail.dropFirst(shortHandshakePrefix.count)
        let separator = suffix.isEmpty ? "" : " "
        return "OpenSpeech WebSocket handshake was rejected by the server.\(separator)\(suffix)"
    }

    return detail
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

public struct SkillStrings: Sendable {
    let language: AppLanguage

    public var title: String {
        language == .zhHans ? "技能" : "Skills"
    }

    public var detail: String {
        language == .zhHans
            ? "清理和调整转写文本，再插入到目标 App。"
            : "Clean and adjust transcripts before inserting them into the target app."
    }

    public var fillerCleanupTitle: String {
        language == .zhHans ? "语气词清理" : "Filler Cleanup"
    }

    public var fillerCleanupDetail: String {
        language == .zhHans
            ? "删除或替换常见口语填充词。"
            : "Delete or replace common spoken filler words."
    }

    public var enabledTitle: String { language == .zhHans ? "启用技能" : "Enable Skills" }
    public var rulesTitle: String { language == .zhHans ? "规则" : "Rules" }
    public var previewTitle: String { language == .zhHans ? "测试预览" : "Preview" }
    public var originalTextTitle: String { language == .zhHans ? "原文" : "Original" }
    public var processedTextTitle: String { language == .zhHans ? "处理后" : "Processed" }
    public var matchedRulesTitle: String { language == .zhHans ? "命中规则" : "Matched Rules" }
    public var noMatchedRulesTitle: String { language == .zhHans ? "没有命中规则" : "No matched rules" }
    public var addRuleButton: String { language == .zhHans ? "新增规则" : "Add Rule" }
    public var deleteActionTitle: String { language == .zhHans ? "删除" : "Delete" }
    public var replaceActionTitle: String { language == .zhHans ? "替换" : "Replace" }
    public var replacementEmptyTitle: String { language == .zhHans ? "空字符串" : "Empty String" }
    public var replacementSpaceTitle: String { language == .zhHans ? "空格" : "Space" }
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
    public var topCenterTitle: String { language == .zhHans ? "顶部居中" : "Top Center" }
    public var topCenterDetail: String { language == .zhHans ? "HUD 固定显示在屏幕顶部中央。" : "HUD stays fixed at the top center of the screen." }
    public var notchAwareTitle: String { language == .zhHans ? "刘海避让" : "Notch Aware" }
    public var notchAwareDetail: String { language == .zhHans ? "在带刘海屏幕上自动贴近 Dynamic Island 区域。" : "On notched displays, automatically stays near the Dynamic Island area." }
    public var transcriptPreviewTitle: String { language == .zhHans ? "显示转写预览" : "Show Transcript Preview" }
    public var transcriptPreviewDetail: String { language == .zhHans ? "录音和插入过程中显示最多 80 个字符的实时文本。" : "Shows up to 80 characters of live text while recording and inserting." }
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
        let detail = localizedDiagnosticDetail(message, language: language)
        switch language {
        case .zhHans:
            return "Keychain 访问失败：\(detail)"
        case .en:
            return "Keychain access failed: \(detail)"
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
            localizedDiagnosticDetail(message, language: language)
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
        localizedDiagnosticDetail(message, language: language)
    }

    public func textInputFailureDetail(_ detail: String) -> String {
        localizedDiagnosticDetail(detail, language: language)
    }

    public func recentOperationFailureDetail(_ detail: String) -> String {
        localizedDiagnosticDetail(detail, language: language)
    }
}

public struct SettingsStrings: Sendable {
    let language: AppLanguage

    public var languageLabel: String { language == .zhHans ? "语言" : "Language" }
    public var languageDetail: String { language == .zhHans ? "切换 Voco 界面语言。" : "Switch the Voco interface language." }
    public var homeTitle: String { language == .zhHans ? "主页" : "Home" }
    public var homeDetail: String { language == .zhHans ? "查看语音输入是否可用，并浏览最近会话。" : "Check whether voice input is available and browse recent sessions." }
    public var recheckedStatusFeedback: String { language == .zhHans ? "已重新检查状态。" : "Status rechecked." }
    public var todaySessionsLabel: String { language == .zhHans ? "TODAY" : "TODAY" }
    public var wordsLabel: String { language == .zhHans ? "WORDS" : "WORDS" }
    public func sessionCountValue(_ count: Int) -> String { language == .zhHans ? "\(count) 次会话" : "\(count) sessions" }
    public func wordCountValue(_ count: Int) -> String { language == .zhHans ? "\(count) 字" : "\(count) words" }
    public func wordBadge(_ count: Int) -> String { language == .zhHans ? "\(count) 字" : "\(count) words" }
    public var voiceInputExperienceTitle: String { language == .zhHans ? "语音输入体验" : "Voice Input Experience" }
    public var voiceInputExperienceDetail: String { language == .zhHans ? "配置开始录音的按键、触发方式、麦克风输入和 macOS 权限。" : "Configure the recording key, trigger mode, microphone input, and macOS permissions." }
    public var recordingControlTitle: String { language == .zhHans ? "录音控制" : "Recording Control" }
    public var recordingControlDetail: String { language == .zhHans ? "选择快捷键、录音方式和输入设备。" : "Choose the hotkey, recording mode, and input device." }
    public var modelTitle: String { language == .zhHans ? "火山引擎模型" : "Volcengine Model" }
    public var modelDetail: String { language == .zhHans ? "选择凭证模式，并将火山引擎凭证保存到 macOS Keychain。" : "Choose a credential mode and save Volcengine credentials to macOS Keychain." }
    public var statisticsTitle: String { language == .zhHans ? "统计" : "Statistics" }
    public var statisticsDetail: String { language == .zhHans ? "查看语音输入使用趋势、应用分布和活跃时段。" : "View voice input usage trends, app distribution, and active hours." }
    public var hotkeyLabel: String { language == .zhHans ? "快捷键" : "Hotkey" }
    public var recordingModeLabel: String { language == .zhHans ? "录音模式" : "Recording Mode" }
    public var toggleModeDetail: String { language == .zhHans ? "按一次开始，再按一次提交。" : "Press once to start, then press again to submit." }
    public var pressAndHoldModeDetail: String { language == .zhHans ? "按住开始录音，松开后提交。" : "Hold to record, then release to submit." }
    public var inputDeviceLabel: String { language == .zhHans ? "输入设备" : "Input Device" }
    public var openSoundInputSettingsHelp: String { language == .zhHans ? "打开 macOS 声音输入设置" : "Open macOS sound input settings" }
    public var credentialsPanelTitle: String { language == .zhHans ? "火山引擎凭证" : "Volcengine Credentials" }
    public var credentialsPanelDetail: String { language == .zhHans ? "凭证会保存到 macOS Keychain，不会在界面中显示完整密钥。" : "Credentials are saved to macOS Keychain and full secrets are never shown in the interface." }
    public var savedCredentialsFeedback: String { language == .zhHans ? "已保存火山引擎凭证。" : "Volcengine credentials saved." }
    public var saveToKeychainButton: String { language == .zhHans ? "保存到 Keychain" : "Save to Keychain" }
    public var refreshStatusButton: String { language == .zhHans ? "刷新状态" : "Refresh Status" }
    public var refreshedVolcengineStatusFeedback: String { language == .zhHans ? "已刷新火山引擎状态。" : "Volcengine status refreshed." }
    public var clearedCredentialsFeedback: String { language == .zhHans ? "已清除火山引擎凭证。" : "Volcengine credentials cleared." }
    public var clearCredentialsButton: String { language == .zhHans ? "清除凭证" : "Clear Credentials" }
    public var permissionsTitle: String { language == .zhHans ? "权限" : "Permissions" }
    public var permissionsDetail: String { language == .zhHans ? "允许麦克风和辅助功能。" : "Allow microphone and accessibility access." }
    public var recheckedPermissionsFeedback: String { language == .zhHans ? "已重新检查权限。" : "Permissions rechecked." }
    public var recheckButton: String { language == .zhHans ? "重新检查" : "Recheck" }
    public var requestButton: String { language == .zhHans ? "请求" : "Request" }
    public var systemTitle: String { language == .zhHans ? "系统" : "System" }
    public var systemDetail: String { language == .zhHans ? "配置 Voco 的启动方式。" : "Configure how Voco starts." }
    public var silentLaunchPill: String { language == .zhHans ? "静默启动" : "Silent Launch" }
    public var showWindowOnLaunchPill: String { language == .zhHans ? "启动显示窗口" : "Show Window on Launch" }
    public var launchAtLoginLabel: String { language == .zhHans ? "开机自启动" : "Launch at Login" }
    public var enabledTitle: String { language == .zhHans ? "已开启" : "Enabled" }
    public var launchAtLoginDisabledTitle: String { language == .zhHans ? "已关闭" : "Disabled" }
    public var launchAtLoginRequiresApprovalTitle: String { language == .zhHans ? "需要批准" : "Requires Approval" }
    public var launchAtLoginUnavailableTitle: String { language == .zhHans ? "不可用" : "Unavailable" }
    public var launchAtLoginErrorTitle: String { language == .zhHans ? "出错" : "Error" }
    public var launchAtLoginDetail: String { language == .zhHans ? "启用后，Voco将在系统启动时自动运行。可在系统设置 > 通用 > 登录项中管理。" : "When enabled, Voco runs automatically at system startup. Manage it in System Settings > General > Login Items." }
    public var launchAtLoginDisabledStateDetail: String { language == .zhHans ? "Voco 不会在登录后自动启动。" : "Voco will not start automatically after login." }
    public var launchAtLoginEnabledStateDetail: String { language == .zhHans ? "Voco 会在你登录 macOS 后自动启动。" : "Voco will start automatically after you log in to macOS." }
    public var launchAtLoginApprovalDetail: String { language == .zhHans ? "请在系统设置 > 通用 > 登录项中批准 Voco。" : "Approve Voco in System Settings > General > Login Items." }
    public var launchAtLoginUnavailableStateDetail: String { language == .zhHans ? "当前运行位置或系统状态不支持登录时启动。" : "The current runtime location or system state does not support launch at login." }
    public var launchAtLoginUnsupportedDetail: String { language == .zhHans ? "当前运行位置不支持登录时启动。" : "The current runtime location does not support launch at login." }
    public func launchAtLoginSetupFailedMessage(_ message: String) -> String {
        language == .zhHans ? "登录时启动设置失败：\(message)" : "Launch at login setup failed: \(message)"
    }
    public var silentLaunchLabel: String { language == .zhHans ? "静默启动" : "Silent Launch" }
    public var trayOnlyTitle: String { language == .zhHans ? "仅在系统托盘运行" : "Run in Menu Bar Only" }
    public var showMainWindowTitle: String { language == .zhHans ? "启动时显示主窗口" : "Show Main Window on Launch" }
    public var silentLaunchDetail: String { language == .zhHans ? "启用后，应用启动时不显示主窗口，仅在系统托盘运行。可随时通过托盘图标打开主窗口。" : "When enabled, the app starts without showing the main window and runs only in the menu bar. Open the main window from the menu bar icon at any time." }
    public var dockLabel: String { language == .zhHans ? "在 Dock 中显示" : "Show in Dock" }
    public var dockShownTitle: String { language == .zhHans ? "已显示" : "Shown" }
    public var dockHiddenTitle: String { language == .zhHans ? "已隐藏" : "Hidden" }
    public var dockDetail: String { language == .zhHans ? "启用后，Voco 会出现在 Dock 和应用切换器中。" : "When enabled, Voco appears in the Dock and app switcher." }
    public var sessionHistoryLabel: String { language == .zhHans ? "保存会话记录" : "Save Session History" }
    public var sessionHistorySavedTitle: String { language == .zhHans ? "已保存" : "Saved" }
    public var sessionHistoryDisabledTitle: String { language == .zhHans ? "不保存" : "Not Saved" }
    public var sessionHistoryEnabledDetail: String { language == .zhHans ? "成功录音后写入本机 SQLite，会话列表下次启动仍可查看。" : "Successful recordings are written to local SQLite so the session list is available after relaunch." }
    public var sessionHistoryDisabledDetail: String { language == .zhHans ? "关闭后不再写入 SQLite，只保留当前运行中的临时列表。" : "When disabled, SQLite is not written and only the current in-memory list is kept." }
    public var retentionPolicyLabel: String { language == .zhHans ? "保留策略" : "Retention Policy" }
    public var removingLegacyLaunchItemTitle: String { language == .zhHans ? "正在移除..." : "Removing..." }
    public var removeLegacyLaunchItemTitle: String { language == .zhHans ? "移除旧版启动项" : "Remove Legacy Launch Item" }
    public var apiKeyPlaceholder: String { language == .zhHans ? "输入火山引擎 API Key" : "Enter Volcengine API Key" }
    public var appIDPlaceholder: String { language == .zhHans ? "输入火山引擎 App ID" : "Enter Volcengine App ID" }
    public var accessTokenPlaceholder: String { language == .zhHans ? "输入火山引擎 Access Token" : "Enter Volcengine Access Token" }
    public var handlePermissionsBeforeTestFeedback: String { language == .zhHans ? "请先处理权限后再测试录音。" : "Resolve permissions before testing recording." }
    public func cannotStartRecordingFeedback(statusTitle: String) -> String { language == .zhHans ? "当前状态不能开始录音：\(statusTitle)" : "Recording cannot start in the current state: \(statusTitle)" }
    public func hotkeyChangedFeedback(_ title: String) -> String { language == .zhHans ? "快捷键已切换为 \(title)。" : "Hotkey changed to \(title)." }
    public func recordingModeChangedFeedback(_ title: String) -> String { language == .zhHans ? "录音模式已切换为 \(title)。" : "Recording mode changed to \(title)." }
    public func inputDeviceChangedFeedback(_ title: String) -> String { language == .zhHans ? "输入设备已切换为 \(title)。" : "Input device changed to \(title)." }
    public var openSoundInputFailedMessage: String { language == .zhHans ? "无法打开 macOS 声音输入设置" : "Could not open macOS sound input settings" }
    public func invalidSettingsURLMessage(kindTitle: String) -> String { language == .zhHans ? "无法打开系统设置：\(kindTitle) 的链接无效" : "Could not open System Settings: the \(kindTitle) link is invalid" }
    public func openSettingsFailedMessage(kindTitle: String) -> String { language == .zhHans ? "无法打开系统设置：\(kindTitle)" : "Could not open System Settings: \(kindTitle)" }
    public var statusOKTitle: String { language == .zhHans ? "正常" : "OK" }
    public var statusNeedsAttentionTitle: String { language == .zhHans ? "阻塞" : "Blocked" }
    public var statusWarningTitle: String { language == .zhHans ? "注意" : "Attention" }
    public var statusNeutralTitle: String { language == .zhHans ? "等待" : "Waiting" }
    public var apiKeyFieldLabel: String { language == .zhHans ? "新控制台 API Key" : "New Console API Key" }
    public var appIDAccessTokenFieldLabel: String { language == .zhHans ? "火山引擎 App ID + Access Token" : "Volcengine App ID + Access Token" }
    public var retryBadgeTitle: String { language == .zhHans ? "自动重试" : "Auto Retry" }
    public var welcomeTitle: String { language == .zhHans ? "Welcome" : "Welcome" }
    public var needsResolutionTitle: String { language == .zhHans ? "需要解决" : "Needs Resolution" }
    public var targetAppLabel: String { language == .zhHans ? "目标 App" : "Target App" }
    public var totalSessionsUnit: String { language == .zhHans ? "次" : "sessions" }
    public var wordsPerMinuteUnit: String { language == .zhHans ? "字/分" : "wpm" }
    public var wordsDurationNote: String { language == .zhHans ? "字数 / 时长" : "Words / Duration" }
    public func appCountValue(_ count: Int) -> String { language == .zhHans ? "\(count) 个" : "\(count) apps" }
    public var deduplicatedAppsNote: String { language == .zhHans ? "应用去重" : "Deduplicated apps" }
    public var currentFilterNote: String { language == .zhHans ? "当前筛选" : "Current filter" }
    public var averageDurationNote: String { language == .zhHans ? "平均时长" : "Average duration" }
    public func trendTitle(metricTitle: String) -> String { language == .zhHans ? "\(metricTitle)趋势" : "\(metricTitle) Trend" }
    public var weekHeatmapTitle: String { language == .zhHans ? "周内热力" : "Weekly Heatmap" }
    public var usageRhythmTitle: String { language == .zhHans ? "使用节律" : "Usage Rhythm" }
    public var lengthDistributionTitle: String { language == .zhHans ? "输入长度分布" : "Input Length Distribution" }
    public func countBadge(_ count: Int) -> String { language == .zhHans ? "\(count) 次" : "\(count) times" }
    public var appContributionTitle: String { language == .zhHans ? "应用贡献" : "App Contribution" }
    public var activeHoursTitle: String { language == .zhHans ? "活跃时段" : "Active Hours" }
    public var providerSourceTitle: String { language == .zhHans ? "模型来源" : "Model Source" }
    public var usagePaceTitle: String { language == .zhHans ? "使用节奏" : "Usage Pace" }
    public var activeDaysLabel: String { language == .zhHans ? "活跃天数" : "Active Days" }
    public var busiestDayLabel: String { language == .zhHans ? "最高单日" : "Busiest Day" }
    public var peakShareLabel: String { language == .zhHans ? "高峰占比" : "Peak Share" }
    public var appConcentrationLabel: String { language == .zhHans ? "应用集中度" : "App Concentration" }
    public var periodInsightTitle: String { language == .zhHans ? "本期观察" : "Period Insights" }
    public var topTargetAppLabel: String { language == .zhHans ? "最常用目标应用" : "Most Used Target App" }
    public var currentTargetAppLabel: String { language == .zhHans ? "当前目标应用" : "Current Target App" }
    public var topHourLabel: String { language == .zhHans ? "最高频时段" : "Most Frequent Time" }
    public var mainProviderLabel: String { language == .zhHans ? "主要模型来源" : "Primary Model Source" }
    public var noRecordsTitle: String { language == .zhHans ? "暂无记录" : "No records" }
    public var sessionRecordsTitle: String { language == .zhHans ? "会话记录" : "Session Records" }
    public var sessionTableHeader: String { language == .zhHans ? "内容预览 / 字数 / 时间 / 时长" : "Preview / Words / Time / Duration" }
    public var noSessionRecordsTitle: String { language == .zhHans ? "暂无会话记录" : "No session records" }
    public var previousPageTitle: String { language == .zhHans ? "上一页" : "Previous" }
    public var nextPageTitle: String { language == .zhHans ? "下一页" : "Next" }
    public var detailsButtonTitle: String { language == .zhHans ? "详情" : "Details" }
    public var sessionDetailsTitle: String { language == .zhHans ? "会话详情" : "Session Details" }
    public var voiceInputFlowTitle: String { language == .zhHans ? "语音输入流程" : "Voice Input Flow" }
    public var voiceInputPreviewTitle: String { language == .zhHans ? "语音输入" : "Voice Input" }
    public func secondsDuration(_ seconds: Int) -> String { language == .zhHans ? "\(seconds) 秒" : "\(seconds)s" }
    public func minutesDuration(_ minutes: Int) -> String { language == .zhHans ? "\(minutes) 分" : "\(minutes)m" }
    public func minutesSecondsDuration(minutes: Int, seconds: Int) -> String { language == .zhHans ? "\(minutes)分\(seconds)秒" : "\(minutes)m \(seconds)s" }

    public func languageFeedback(_ displayName: String) -> String {
        switch language {
        case .zhHans:
            "界面语言已切换为 \(displayName)。"
        case .en:
            "Interface language changed to \(displayName)."
        }
    }
}

public struct AudioSettingsStrings: Sendable {
    let language: AppLanguage

    public var systemDefaultInputTitle: String { language == .zhHans ? "系统默认输入" : "System Default Input" }
    public var systemDefaultInputDetail: String { language == .zhHans ? "跟随 macOS 当前默认麦克风。" : "Follow the current default macOS microphone." }
    public var selectedInputDetail: String { language == .zhHans ? "已选择此麦克风用于录音。" : "This microphone is selected for recording." }
    public var noRecentSampleTitle: String { language == .zhHans ? "无近期采样" : "No Recent Sample" }
    public var noRecentSampleDetail: String { language == .zhHans ? "开始一次录音后会显示最近峰值电平。" : "The recent peak level appears after a recording." }
    public var levelNearClippingTitle: String { language == .zhHans ? "电平接近削波" : "Level Near Clipping" }
    public var levelTooLowTitle: String { language == .zhHans ? "电平偏低" : "Level Too Low" }
    public var levelNormalTitle: String { language == .zhHans ? "电平正常" : "Level Normal" }
    public var waitingSampleRateTitle: String { language == .zhHans ? "等待采样率" : "Waiting for Sample Rate" }
    public var sampleRateMatchedDetail: String { language == .zhHans ? "最近录音采样率符合目标转写输入。" : "The recent recording sample rate matches the target transcription input." }

    public func recentPeakDetail(peakPercentage: Int, durationSeconds: Double) -> String {
        let format = language == .zhHans ? "最近峰值 %d%% · %.2fs" : "Recent peak %d%% · %.2fs"
        return String(format: format, peakPercentage, durationSeconds)
    }

    public func waitingSampleRateDetail(rate: String) -> String {
        language == .zhHans
            ? "暂无最近录音；目标转写采样率为 \(rate) Hz。"
            : "No recent recording. Target transcription sample rate is \(rate) Hz."
    }

    public func sampleRateMismatchedDetail(rate: String) -> String {
        language == .zhHans
            ? "最近录音采样率与目标 \(rate) Hz 不一致。"
            : "The recent recording sample rate does not match target \(rate) Hz."
    }
}

public struct CredentialStrings: Sendable {
    let language: AppLanguage

    public var volcengineTitle: String { language == .zhHans ? "火山引擎" : "Volcengine" }
    public var apiKeyModeTitle: String { language == .zhHans ? "新控制台 API Key" : "New Console API Key" }
    public var appIDAccessTokenModeTitle: String { language == .zhHans ? "旧控制台 App ID + Token" : "Legacy Console App ID + Token" }
    public var apiKeyModeDetail: String { language == .zhHans ? "使用 X-Api-Key 连接 OpenSpeech 流式 ASR。" : "Use X-Api-Key to connect to OpenSpeech streaming ASR." }
    public var appIDAccessTokenModeDetail: String { language == .zhHans ? "使用 X-Api-App-Key 和 X-Api-Access-Key 连接 OpenSpeech 流式 ASR。" : "Use X-Api-App-Key and X-Api-Access-Key to connect to OpenSpeech streaming ASR." }
    public var missingStorageDetail: String { language == .zhHans ? "Keychain 中没有保存火山引擎凭证。" : "No Volcengine credentials are saved in Keychain." }

    public func statusTitle(provider: TranscriptionCredentialProvider, hasCredential: Bool, lastErrorMessage: String?) -> String {
        let providerTitle = provider.title(strings: VocoStrings(language: language))
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            return language == .zhHans ? "\(providerTitle)凭证读取失败" : "\(providerTitle) credentials read failed"
        }
        if hasCredential {
            return language == .zhHans ? "\(providerTitle)凭证已保存" : "\(providerTitle) credentials saved"
        }
        return language == .zhHans ? "\(providerTitle)凭证未保存" : "\(providerTitle) credentials not saved"
    }

    public func storedStorageDetail(mode: VolcengineCredentialMode) -> String {
        let title = mode.title(strings: VocoStrings(language: language))
        return language == .zhHans ? "\(title) 已安全保存在 Keychain。" : "\(title) is saved securely in Keychain."
    }

    public func failedStorageDetail(message: String) -> String {
        let detail = localizedDiagnosticDetail(message, language: language)
        return language == .zhHans ? "Keychain 访问失败：\(detail)" : "Keychain access failed: \(detail)"
    }

    public func failureMessage(_ message: String) -> String {
        localizedDiagnosticDetail(message, language: language)
    }

    public func errorDescription(for error: TranscriptionCredentialError) -> String {
        switch (language, error) {
        case (.zhHans, .emptyAPIKey):
            "ASR API Key 不能为空。"
        case (.zhHans, .emptyAppIDAccessToken):
            "火山引擎 App ID 和 Access Token 不能为空。"
        case (.zhHans, .readFailed(let message)):
            "读取 ASR 凭证失败：\(localizedDiagnosticDetail(message, language: language))"
        case (.zhHans, .storeFailed(let message)):
            "保存 ASR 凭证失败：\(localizedDiagnosticDetail(message, language: language))"
        case (.zhHans, .deleteFailed(let message)):
            "删除 ASR 凭证失败：\(localizedDiagnosticDetail(message, language: language))"
        case (.en, .emptyAPIKey):
            "ASR API Key cannot be empty."
        case (.en, .emptyAppIDAccessToken):
            "Volcengine App ID and Access Token cannot be empty."
        case (.en, .readFailed(let message)):
            "Unable to read ASR credentials: \(localizedDiagnosticDetail(message, language: language))"
        case (.en, .storeFailed(let message)):
            "Unable to save ASR credentials: \(localizedDiagnosticDetail(message, language: language))"
        case (.en, .deleteFailed(let message)):
            "Unable to delete ASR credentials: \(localizedDiagnosticDetail(message, language: language))"
        }
    }
}

public struct TranscriptionStatusStrings: Sendable {
    let language: AppLanguage

    public var notConfiguredTitle: String { language == .zhHans ? "未配置" : "Not Configured" }
    public var notConfiguredDetail: String { language == .zhHans ? "请先配置火山引擎凭证。" : "Configure Volcengine credentials first." }
    public var readyDetail: String { language == .zhHans ? "模型已配置" : "Model configured" }
    public var authenticationRequiredDetail: String { language == .zhHans ? "请检查火山引擎凭证。" : "Check Volcengine credentials." }
    public var offlineDetail: String { language == .zhHans ? "模型暂不可用，稍后可重试。" : "The model is temporarily unavailable. Try again later." }

    public func title(for status: TranscriptionProviderStatus) -> String {
        switch (language, status) {
        case (.zhHans, .notConfigured):
            notConfiguredTitle
        case (.zhHans, .ready(let providerName)):
            providerName
        case (.zhHans, .authenticationRequired(let providerName)):
            "\(providerName)需要认证"
        case (.zhHans, .offline(let providerName)):
            "\(providerName)离线"
        case (.zhHans, .failed(let providerName, _)):
            "\(providerName)错误"
        case (.en, .notConfigured):
            notConfiguredTitle
        case (.en, .ready(let providerName)):
            VocoStrings(language: language).workbench.providerDisplayName(providerName)
        case (.en, .authenticationRequired(let providerName)):
            "\(VocoStrings(language: language).workbench.providerDisplayName(providerName)) requires authentication"
        case (.en, .offline(let providerName)):
            "\(VocoStrings(language: language).workbench.providerDisplayName(providerName)) offline"
        case (.en, .failed(let providerName, _)):
            "\(VocoStrings(language: language).workbench.providerDisplayName(providerName)) error"
        }
    }

    public func detail(for status: TranscriptionProviderStatus) -> String {
        switch status {
        case .notConfigured:
            notConfiguredDetail
        case .ready:
            readyDetail
        case .authenticationRequired:
            authenticationRequiredDetail
        case .offline:
            offlineDetail
        case .failed(_, let message):
            message
        }
    }

    public func errorDescription(for error: TranscriptionProviderError) -> String {
        switch (language, error) {
        case (.zhHans, .notConfigured):
            "模型未配置：请先在设置中配置火山引擎凭证。"
        case (.zhHans, .emptyAudio):
            "转写失败：没有可用音频。"
        case (.zhHans, .authentication(let providerName, let message)):
            "\(providerName)认证失败：\(message)"
        case (.zhHans, .transport(let providerName, let message, _)):
            "\(providerName)网络错误：\(message)"
        case (.zhHans, .provider(let providerName, let message)):
            "\(providerName)转写失败：\(message)"
        case (.zhHans, .cancelled):
            "转写已取消。"
        case (.en, .notConfigured):
            "Model not configured: configure Volcengine credentials in Settings first."
        case (.en, .emptyAudio):
            "Transcription failed: no usable audio."
        case (.en, .authentication(let providerName, let message)):
            "\(providerDisplayName(providerName)) authentication failed: \(localizedDiagnosticDetail(message, language: language))"
        case (.en, .transport(let providerName, let message, _)):
            "\(providerDisplayName(providerName)) network error: \(localizedDiagnosticDetail(message, language: language))"
        case (.en, .provider(let providerName, let message)):
            "\(providerDisplayName(providerName)) transcription failed: \(localizedDiagnosticDetail(message, language: language))"
        case (.en, .cancelled):
            "Transcription cancelled."
        }
    }

    private func providerDisplayName(_ providerName: String) -> String {
        VocoStrings(language: language).workbench.providerDisplayName(providerName)
    }
}

public struct InjectionSettingsStrings: Sendable {
    let language: AppLanguage

    public var waitingToInsertTitle: String { language == .zhHans ? "等待插入" : "Waiting to Insert" }
    public var waitingToInsertDetail: String { language == .zhHans ? "完成一次转写后会显示采用的文本插入方式。" : "The text insertion method appears after a transcription completes." }
    public var noRecentTargetTitle: String { language == .zhHans ? "无近期目标" : "No Recent Target" }
    public var noRecentTargetDetail: String { language == .zhHans ? "尚未完成文本插入，无法显示最近聚焦 App。" : "No text insertion has completed, so the recent focused app is unavailable." }
    public var recentTargetDetail: String { language == .zhHans ? "最近插入目标 App。" : "Recent insertion target app." }
    public var noTargetAppTitle: String { language == .zhHans ? "无目标 App" : "No Target App" }
    public var skippedEmptyDetail: String { language == .zhHans ? "最终转写为空，已跳过文本插入。" : "Final transcript was empty; skipped text insertion." }

    public func title(for strategy: TextInjectionStrategy) -> String {
        switch (language, strategy) {
        case (.zhHans, _):
            strategy.title
        case (.en, .directAccessibility):
            "Direct Accessibility insertion"
        case (.en, .unicodeEvent):
            "Unicode event"
        case (.en, .clipboardFallback):
            "Clipboard fallback"
        case (.en, .unavailable):
            "Unavailable"
        case (.en, .skippedEmpty):
            "Empty text skipped"
        }
    }

    public func successDetail(for strategy: TextInjectionStrategy) -> String {
        switch (language, strategy) {
        case (.zhHans, .directAccessibility):
            "已通过辅助功能直接插入文本。"
        case (.zhHans, .unicodeEvent):
            "已通过 Unicode 事件插入文本。"
        case (.zhHans, .clipboardFallback):
            "已通过剪贴板回退插入文本并恢复剪贴板。"
        case (.zhHans, .unavailable):
            "没有可用的文本插入方式。"
        case (.zhHans, .skippedEmpty):
            skippedEmptyDetail
        case (.en, .directAccessibility):
            "Inserted text with Direct Accessibility."
        case (.en, .unicodeEvent):
            "Inserted text with Unicode events."
        case (.en, .clipboardFallback):
            "Inserted text with clipboard fallback and restored the clipboard."
        case (.en, .unavailable):
            "No text insertion method was available."
        case (.en, .skippedEmpty):
            skippedEmptyDetail
        }
    }

    public func errorDescription(for error: TextInjectionError) -> String {
        switch (language, error) {
        case (.zhHans, .accessibilityPermissionMissing):
            "无法插入文本：请先在系统设置中允许 Voco 使用辅助功能。"
        case (.zhHans, .noSupportedStrategy(let targetAppName)):
            "无法插入文本：\(targetAppName ?? "当前 App") 没有可用的文本插入方式。"
        case (.zhHans, .insertionFailed(let strategy, let message)):
            "\(title(for: strategy))失败：\(message)"
        case (.zhHans, .clipboardUnavailable(let message)):
            "剪贴板不可用：\(message)"
        case (.zhHans, .clipboardRestoreFailed(let message)):
            "剪贴板回退后恢复原剪贴板失败：\(message)"
        case (.zhHans, .eventPostFailed(let message)):
            "Unicode 事件发送失败：\(message)"
        case (.en, .accessibilityPermissionMissing):
            "Unable to insert text: allow Voco to use Accessibility in System Settings first."
        case (.en, .noSupportedStrategy(let targetAppName)):
            "Unable to insert text: \(targetAppName ?? "current app") has no available text insertion method."
        case (.en, .insertionFailed(let strategy, let message)):
            "\(title(for: strategy)) failed: \(message)"
        case (.en, .clipboardUnavailable(let message)):
            "Clipboard unavailable: \(message)"
        case (.en, .clipboardRestoreFailed(let message)):
            "Unable to restore original clipboard after clipboard fallback: \(message)"
        case (.en, .eventPostFailed(let message)):
            "Unicode event posting failed: \(message)"
        }
    }
}

public struct StatisticsStrings: Sendable {
    let language: AppLanguage

    public var allTitle: String { language == .zhHans ? "全部" : "All" }
    public var unknownAppTitle: String { language == .zhHans ? "未知 App" : "Unknown App" }
    public var shortTitle: String { language == .zhHans ? "短句" : "Short" }
    public var mediumTitle: String { language == .zhHans ? "中段" : "Medium" }
    public var longTitle: String { language == .zhHans ? "长段" : "Long" }
    public var shortDetail: String { language == .zhHans ? "0-18 字" : "0-18 chars" }
    public var mediumDetail: String { language == .zhHans ? "19-24 字" : "19-24 chars" }
    public var longDetail: String { language == .zhHans ? "25 字以上" : "25+ chars" }

    public func title(for period: VoiceInputSessionStatisticsPeriod) -> String {
        switch (language, period) {
        case (.zhHans, .last7Days): "近 7 天"
        case (.zhHans, .last30Days): "近 30 天"
        case (.zhHans, .all): "全部"
        case (.en, .last7Days): "Last 7 Days"
        case (.en, .last30Days): "Last 30 Days"
        case (.en, .all): "All"
        }
    }

    public func title(for metric: VoiceInputSessionStatisticsMetric) -> String {
        switch (language, metric) {
        case (.zhHans, .sessions): "会话"
        case (.zhHans, .words): "字数"
        case (.zhHans, .duration): "时长"
        case (.en, .sessions): "Sessions"
        case (.en, .words): "Words"
        case (.en, .duration): "Duration"
        }
    }

    public func weekdayTitle(calendarWeekday: Int) -> String {
        switch (language, calendarWeekday) {
        case (.zhHans, 2): "周一"
        case (.zhHans, 3): "周二"
        case (.zhHans, 4): "周三"
        case (.zhHans, 5): "周四"
        case (.zhHans, 6): "周五"
        case (.zhHans, 7): "周六"
        case (.zhHans, 1): "周日"
        case (.en, 2): "Mon"
        case (.en, 3): "Tue"
        case (.en, 4): "Wed"
        case (.en, 5): "Thu"
        case (.en, 6): "Fri"
        case (.en, 7): "Sat"
        case (.en, 1): "Sun"
        default: "--"
        }
    }
}

public struct SessionStrings: Sendable {
    let language: AppLanguage

    public func visibleRangeTitle(start: Int, end: Int, total: Int) -> String {
        if total == 0 {
            return language == .zhHans ? "0 / 0 条" : "0 / 0 items"
        }
        return language == .zhHans ? "\(start)-\(end) / \(total) 条" : "\(start)-\(end) / \(total) items"
    }

    public func loadFailureMessage(detail: String) -> String {
        let localizedDetail = localizedDiagnosticDetail(detail, language: language)
        return language == .zhHans
            ? "无法加载会话记录：\(localizedDetail)"
            : "Unable to load session history: \(localizedDetail)"
    }

    public func saveFailureMessage(detail: String) -> String {
        let localizedDetail = localizedDiagnosticDetail(detail, language: language)
        return language == .zhHans
            ? "无法保存会话记录：\(localizedDetail)"
            : "Unable to save session history: \(localizedDetail)"
    }

    public func updateRetentionFailureMessage(detail: String) -> String {
        let localizedDetail = localizedDiagnosticDetail(detail, language: language)
        return language == .zhHans
            ? "无法更新会话记录保留策略：\(localizedDetail)"
            : "Unable to update session retention policy: \(localizedDetail)"
    }

    public func storeErrorDescription(for error: VoiceInputSessionStoreError) -> String {
        switch error {
        case let .loadFailed(message):
            loadFailureMessage(detail: message)
        case let .saveFailed(message):
            saveFailureMessage(detail: message)
        }
    }
}

public struct InstallLocationStrings: Sendable {
    let language: AppLanguage

    public var unknownTitle: String { language == .zhHans ? "运行位置未知" : "Runtime Location Unknown" }
    public var unknownDetail: String { language == .zhHans ? "尚未读取 Voco.app 的运行位置。" : "The runtime location of Voco.app has not been read." }
    public var mountedImageTitle: String { language == .zhHans ? "磁盘映像" : "Disk Image" }
    public var installedTitle: String { language == .zhHans ? "已安装" : "Installed" }
    public var unconfirmedTitle: String { language == .zhHans ? "运行位置未确认" : "Runtime Location Unconfirmed" }

    public func mountedImageDetail(path: String) -> String {
        language == .zhHans ? "Voco 当前从 \(path) 运行，这不是最终安装位置。" : "Voco is running from \(path), which is not the final install location."
    }

    public var mountedImageWarningTitle: String { language == .zhHans ? "从磁盘映像运行" : "Running from Disk Image" }
    public var mountedImageWarningDetail: String {
        language == .zhHans
            ? "请先把 Voco.app 移动到 /Applications，再开启登录时启动。你仍可临时试用当前会话。"
            : "Move Voco.app to /Applications before enabling launch at login. You can still try the current session temporarily."
    }

    public func installedDetail(path: String) -> String {
        language == .zhHans ? "Voco 当前从 \(path) 运行，可用于登录时启动。" : "Voco is running from \(path) and can be used for launch at login."
    }

    public func unconfirmedDetail(path: String) -> String {
        language == .zhHans ? "Voco 当前从 \(path) 运行。建议移动到 /Applications 后再开启登录时启动。" : "Voco is running from \(path). Move it to /Applications before enabling launch at login."
    }
}

public struct LegacyInstallStrings: Sendable {
    let language: AppLanguage

    public var detectedTitle: String { language == .zhHans ? "检测到旧版后台启动项" : "Legacy background launch item detected" }
    public var notFoundTitle: String { language == .zhHans ? "未检测到旧版启动项" : "No legacy launch item detected" }
    public var removalFailedTitle: String { language == .zhHans ? "旧版启动项移除失败" : "Failed to remove legacy launch item" }

    public func detectedDetail(path: String) -> String {
        language == .zhHans
            ? "检测到旧版 LaunchAgent：\(path)。如已改用 native Voco，可在这里移除该用户级启动项；不会触碰系统级 LaunchAgents，也不需要 sudo。"
            : "Detected legacy LaunchAgent: \(path). If you now use native Voco, remove this user-level launch item here. System LaunchAgents are not touched and sudo is not required."
    }

    public func notFoundDetail(path: String) -> String {
        language == .zhHans
            ? "未发现 \(path)。native Voco 使用登录项，不会安装旧版 LaunchAgent plist。"
            : "\(path) was not found. Native Voco uses Login Items and does not install the legacy LaunchAgent plist."
    }
}
