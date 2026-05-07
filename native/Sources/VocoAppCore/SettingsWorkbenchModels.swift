import Foundation

public enum SettingsWorkbenchSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case model
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview:
            "总览"
        case .settings:
            "设置"
        case .model:
            "模型"
        }
    }

    public var summary: String {
        switch self {
        case .overview:
            "当前状态"
        case .settings:
            "快捷键、麦克风、系统"
        case .model:
            "火山引擎和 Keychain"
        }
    }
}

public enum SettingsWorkbenchActionTitle {
    public static let checkMicrophone = "检查麦克风"
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

public struct SettingsWorkbenchSnapshot: Equatable, Sendable {
    public let statusTitle: String
    public let overview: SettingsWorkbenchOverviewSnapshot
    public let sectionStatuses: [SettingsWorkbenchSection: SettingsWorkbenchSectionStatus]

    public init(
        statusTitle: String,
        overview: SettingsWorkbenchOverviewSnapshot,
        sectionStatuses: [SettingsWorkbenchSection: SettingsWorkbenchSectionStatus]
    ) {
        self.statusTitle = statusTitle
        self.overview = overview
        self.sectionStatuses = sectionStatuses
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
                primaryActionTitle: requiredMissing.kind == .microphone
                    ? SettingsWorkbenchActionTitle.checkMicrophone
                    : requiredMissing.kind.recoveryActionTitle
            )
        } else if !credentials.hasCredential || credentials.lastErrorMessage != nil {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: credentials.lastErrorMessage == nil ? "火山引擎凭证未保存" : "火山引擎凭证读取失败",
                detail: credentials.storageDetail,
                primaryActionTitle: "前往模型"
            )
        } else if let transcriptionErrorMessage {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: "火山引擎转写失败",
                detail: transcriptionErrorMessage,
                primaryActionTitle: "前往模型"
            )
        } else if asrStatus.isWorkbenchAttention {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: asrStatus.workbenchIssueTitle,
                detail: asrStatus.detail,
                primaryActionTitle: "前往模型"
            )
        } else if let injection, !injection.succeeded {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: "文本输入失败",
                detail: injection.detail,
                primaryActionTitle: "前往设置"
            )
        } else if let lastErrorMessage, !lastErrorMessage.isEmpty {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: "最近一次操作失败",
                detail: lastErrorMessage,
                primaryActionTitle: "重新检查"
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
        let hasRuntimeError = lastErrorMessage?.nonEmpty != nil
        let settingsStatus: SettingsWorkbenchSectionStatus
        if hasRequiredPermissionProblem || inputNeedsAttention {
            settingsStatus = .needsAttention
        } else if hotkeyState != .listening {
            settingsStatus = .warning
        } else {
            settingsStatus = .ok
        }

        return SettingsWorkbenchSnapshot(
            statusTitle: statusTitle,
            overview: overview,
            sectionStatuses: [
                .overview: hasRequiredPermissionProblem || transcriptionNeedsAttention || inputNeedsAttention || hasRuntimeError
                    ? .needsAttention
                    : .ok,
                .settings: settingsStatus,
                .model: transcriptionNeedsAttention ? .needsAttention : .ok
            ]
        )
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
            "模型未配置"
        case .ready(let providerName):
            "\(providerName)已就绪"
        case .authenticationRequired(let providerName):
            "\(providerName)需要认证"
        case .offline(let providerName):
            "\(providerName)离线"
        case .failed(let providerName, _):
            "\(providerName)转写失败"
        }
    }
}
