import Foundation

public enum SettingsWorkbenchSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case voiceInput
    case transcription
    case permissionsAndInput
    case diagnosticsAndPrivacy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview:
            "总览"
        case .voiceInput:
            "语音输入"
        case .transcription:
            "转写服务"
        case .permissionsAndInput:
            "权限与输入"
        case .diagnosticsAndPrivacy:
            "诊断与隐私"
        }
    }

    public var summary: String {
        switch self {
        case .overview:
            "当前状态"
        case .voiceInput:
            "快捷键、音频、HUD"
        case .transcription:
            "Doubao 和 Keychain"
        case .permissionsAndInput:
            "macOS 权限、插入策略"
        case .diagnosticsAndPrivacy:
            "记录、导出、脱敏"
        }
    }
}

public enum SettingsWorkbenchSectionStatus: Equatable, Sendable {
    case ok
    case needsAttention
    case warning
    case neutral

    public var systemImage: String {
        "circle.fill"
    }
}

public struct SettingsWorkbenchOverviewSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let primaryActionTitle: String
    public let secondaryActionTitle: String

    public init(
        title: String,
        detail: String,
        primaryActionTitle: String,
        secondaryActionTitle: String = "重新检查"
    ) {
        self.title = title
        self.detail = detail
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
    }
}

public enum VoiceInputChainStepAction: Equatable, Sendable {
    case viewDetails
    case checkHotkey
    case startTestRecording
    case testTranscription
    case openTranscription
    case openPermissionsAndInput

    public var title: String {
        switch self {
        case .viewDetails:
            "查看详情"
        case .checkHotkey:
            "检查快捷键"
        case .startTestRecording:
            "开始测试录音"
        case .testTranscription:
            "测试连接"
        case .openTranscription:
            "前往转写服务"
        case .openPermissionsAndInput:
            "修复输入权限"
        }
    }
}

public struct VoiceInputChainStepSnapshot: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let status: SettingsWorkbenchSectionStatus
    public let action: VoiceInputChainStepAction

    public var actionTitle: String {
        action.title
    }

    public init(
        id: String,
        title: String,
        detail: String,
        status: SettingsWorkbenchSectionStatus,
        action: VoiceInputChainStepAction
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.action = action
    }
}

public struct SettingsWorkbenchSnapshot: Equatable, Sendable {
    public let statusTitle: String
    public let overview: SettingsWorkbenchOverviewSnapshot
    public let sectionStatuses: [SettingsWorkbenchSection: SettingsWorkbenchSectionStatus]
    public let recentChain: [VoiceInputChainStepSnapshot]

    public init(
        statusTitle: String,
        overview: SettingsWorkbenchOverviewSnapshot,
        sectionStatuses: [SettingsWorkbenchSection: SettingsWorkbenchSectionStatus],
        recentChain: [VoiceInputChainStepSnapshot]
    ) {
        self.statusTitle = statusTitle
        self.overview = overview
        self.sectionStatuses = sectionStatuses
        self.recentChain = recentChain
    }

    public func status(for section: SettingsWorkbenchSection) -> SettingsWorkbenchSectionStatus {
        sectionStatuses[section] ?? .neutral
    }

    public static func make(
        statusTitle: String,
        permissions: [PermissionSnapshot],
        hotkeyState: HotkeyRuntimeState,
        hotkeyBinding: HotkeyBinding,
        hotkeyMode: HotkeyMode,
        asrStatus: TranscriptionProviderStatus,
        credentials: TranscriptionCredentialSnapshot,
        audio: CapturedAudioSnapshot?,
        transcript: TranscriptSnapshot?,
        injection: TextInjectionSnapshot?,
        lastErrorMessage: String?,
        transcriptionErrorMessage: String? = nil
    ) -> SettingsWorkbenchSnapshot {
        let requiredMissing = permissions.first { permission in
            permission.isRequired && !permission.state.isGranted
        }
        let inputNeedsAttention = injection.map { !$0.succeeded } ?? false
        let transcriptionErrorMessage = transcriptionErrorMessage?.nonEmpty

        let overview: SettingsWorkbenchOverviewSnapshot
        if let requiredMissing {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: "\(requiredMissing.kind.title)权限缺失",
                detail: requiredMissing.kind == .accessibility
                    ? "Voco 可以录音，但不能稳定插入当前输入框。"
                    : "\(requiredMissing.kind.title)权限缺失，语音输入链路无法完成。",
                primaryActionTitle: requiredMissing.kind.recoveryActionTitle
            )
        } else if !credentials.hasCredential || credentials.lastErrorMessage != nil {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: credentials.lastErrorMessage == nil ? "Doubao 凭证未保存" : "Doubao 凭证读取失败",
                detail: credentials.storageDetail,
                primaryActionTitle: "前往转写服务"
            )
        } else if let transcriptionErrorMessage {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: "Doubao 转写失败",
                detail: transcriptionErrorMessage,
                primaryActionTitle: "前往转写服务"
            )
        } else if asrStatus.isWorkbenchAttention {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: asrStatus.workbenchIssueTitle,
                detail: asrStatus.detail,
                primaryActionTitle: "前往转写服务"
            )
        } else if let injection, !injection.succeeded {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: "文本输入失败",
                detail: injection.detail,
                primaryActionTitle: "前往权限与输入"
            )
        } else if let lastErrorMessage, !lastErrorMessage.isEmpty {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: "最近一次操作失败",
                detail: lastErrorMessage,
                primaryActionTitle: "查看诊断与隐私"
            )
        } else {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: "Voco 已就绪",
                detail: "Right Command 可以触发录音、转写和文本输入。",
                primaryActionTitle: "开始测试录音"
            )
        }

        let hasRequiredPermissionProblem = requiredMissing != nil
        let transcriptionNeedsAttention = !credentials.hasCredential ||
            credentials.lastErrorMessage != nil ||
            transcriptionErrorMessage != nil ||
            asrStatus.isWorkbenchAttention
        let recentChain = makeRecentChain(
            hotkeyState: hotkeyState,
            hotkeyBinding: hotkeyBinding,
            hotkeyMode: hotkeyMode,
            asrStatus: asrStatus,
            audio: audio,
            transcript: transcript,
            injection: injection,
            transcriptionErrorMessage: transcriptionErrorMessage
        )

        return SettingsWorkbenchSnapshot(
            statusTitle: statusTitle,
            overview: overview,
            sectionStatuses: [
                .overview: hasRequiredPermissionProblem || transcriptionNeedsAttention || inputNeedsAttention
                    ? .needsAttention
                    : .ok,
                .voiceInput: hasRequiredPermissionProblem || hotkeyState != .listening ? .warning : .ok,
                .transcription: transcriptionNeedsAttention ? .needsAttention : .ok,
                .permissionsAndInput: hasRequiredPermissionProblem || inputNeedsAttention ? .needsAttention : .ok,
                .diagnosticsAndPrivacy: lastErrorMessage == nil ? .neutral : .needsAttention
            ],
            recentChain: recentChain
        )
    }

    private static func makeRecentChain(
        hotkeyState: HotkeyRuntimeState,
        hotkeyBinding: HotkeyBinding,
        hotkeyMode: HotkeyMode,
        asrStatus: TranscriptionProviderStatus,
        audio: CapturedAudioSnapshot?,
        transcript: TranscriptSnapshot?,
        injection: TextInjectionSnapshot?,
        transcriptionErrorMessage: String?
    ) -> [VoiceInputChainStepSnapshot] {
        [
            VoiceInputChainStepSnapshot(
                id: "command",
                title: "Command",
                detail: "\(hotkeyBinding.displayName) · \(hotkeyMode.title)",
                status: hotkeyState == .listening ? .ok : .warning,
                action: hotkeyState == .listening ? .viewDetails : .checkHotkey
            ),
            VoiceInputChainStepSnapshot(
                id: "audio",
                title: "录音",
                detail: audio.map(audioDetail) ?? "尚无近期录音",
                status: audio == nil ? .neutral : .ok,
                action: audio == nil ? .startTestRecording : .viewDetails
            ),
            VoiceInputChainStepSnapshot(
                id: "doubao",
                title: "Doubao",
                detail: doubaoDetail(
                    transcript: transcript,
                    asrStatus: asrStatus,
                    transcriptionErrorMessage: transcriptionErrorMessage
                ),
                status: doubaoStatus(
                    transcript: transcript,
                    asrStatus: asrStatus,
                    transcriptionErrorMessage: transcriptionErrorMessage
                ),
                action: doubaoAction(
                    transcript: transcript,
                    asrStatus: asrStatus,
                    transcriptionErrorMessage: transcriptionErrorMessage
                )
            ),
            VoiceInputChainStepSnapshot(
                id: "input",
                title: "输入",
                detail: injection.map(inputDetail) ?? "尚无近期输入",
                status: injection.map { $0.succeeded ? .ok : .needsAttention } ?? .neutral,
                action: injection.map { $0.succeeded ? .viewDetails : .openPermissionsAndInput } ?? .viewDetails
            )
        ]
    }

    private static func audioDetail(_ audio: CapturedAudioSnapshot) -> String {
        String(format: "%.2fs · %.0f Hz · peak %.2f", audio.durationSeconds, audio.sampleRate, audio.peakAmplitude)
    }

    private static func transcriptDetail(_ transcript: TranscriptSnapshot) -> String {
        let latency = transcript.latencyMilliseconds.map { " · \($0) ms" } ?? ""
        return "\(transcript.finalText.count) 字符 · \(transcript.partials.count) 个 partial\(latency)"
    }

    private static func inputDetail(_ injection: TextInjectionSnapshot) -> String {
        "\(injection.targetAppName ?? "当前 App") · \(injection.strategy.title)"
    }

    private static func doubaoDetail(
        transcript: TranscriptSnapshot?,
        asrStatus: TranscriptionProviderStatus,
        transcriptionErrorMessage: String?
    ) -> String {
        if asrStatus.isWorkbenchAttention {
            return asrStatus.detail
        }

        if let transcriptionErrorMessage {
            return transcriptionErrorMessage
        }

        if let transcript {
            return transcriptDetail(transcript)
        }

        return "尚无近期转写"
    }

    private static func doubaoStatus(
        transcript: TranscriptSnapshot?,
        asrStatus: TranscriptionProviderStatus,
        transcriptionErrorMessage: String?
    ) -> SettingsWorkbenchSectionStatus {
        if asrStatus.isWorkbenchAttention {
            return .needsAttention
        }

        if transcriptionErrorMessage != nil {
            return .needsAttention
        }

        return transcript == nil ? .neutral : .ok
    }

    private static func doubaoAction(
        transcript: TranscriptSnapshot?,
        asrStatus: TranscriptionProviderStatus,
        transcriptionErrorMessage: String?
    ) -> VoiceInputChainStepAction {
        if asrStatus.isWorkbenchAttention || transcriptionErrorMessage != nil {
            return .openTranscription
        }

        return transcript == nil ? .testTranscription : .viewDetails
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension TranscriptionProviderStatus {
    var isWorkbenchAttention: Bool {
        switch self {
        case .ready:
            false
        case .notConfigured, .authenticationRequired, .offline, .failed:
            true
        }
    }

    var workbenchIssueTitle: String {
        switch self {
        case .notConfigured:
            "转写服务未配置"
        case .ready(let providerName):
            "\(providerName) 已就绪"
        case .authenticationRequired(let providerName):
            "\(providerName) 需要认证"
        case .offline(let providerName):
            "\(providerName) 离线"
        case .failed(let providerName, _):
            "\(providerName) 转写失败"
        }
    }
}
