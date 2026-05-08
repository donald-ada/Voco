import Foundation

public enum SettingsWorkbenchSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case model
    case statistics
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview:
            "主页"
        case .model:
            "模型"
        case .statistics:
            "统计"
        case .settings:
            "设置"
        }
    }

    public var summary: String {
        switch self {
        case .overview:
            "当前状态"
        case .model:
            "火山引擎和 Keychain"
        case .statistics:
            "使用趋势和分布"
        case .settings:
            "快捷键、麦克风、系统"
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

public struct SettingsWorkbenchIssueItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String

    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct SettingsWorkbenchSnapshot: Equatable, Sendable {
    public let statusTitle: String
    public let overview: SettingsWorkbenchOverviewSnapshot
    public let sectionStatuses: [SettingsWorkbenchSection: SettingsWorkbenchSectionStatus]
    public let homeIssueItems: [SettingsWorkbenchIssueItem]

    public init(
        statusTitle: String,
        overview: SettingsWorkbenchOverviewSnapshot,
        sectionStatuses: [SettingsWorkbenchSection: SettingsWorkbenchSectionStatus],
        homeIssueItems: [SettingsWorkbenchIssueItem] = []
    ) {
        self.statusTitle = statusTitle
        self.overview = overview
        self.sectionStatuses = sectionStatuses
        self.homeIssueItems = homeIssueItems
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
        let missingRequiredPermissions = permissions.filter { permission in
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
        let homeIssueItems = makeHomeIssueItems(
            missingRequiredPermissions: missingRequiredPermissions,
            credentials: credentials,
            asrStatus: asrStatus,
            transcriptionErrorMessage: transcriptionErrorMessage,
            injection: injection,
            lastErrorMessage: lastErrorMessage
        )

        return SettingsWorkbenchSnapshot(
            statusTitle: statusTitle,
            overview: overview,
            sectionStatuses: [
                .overview: hasRequiredPermissionProblem || transcriptionNeedsAttention || inputNeedsAttention || hasRuntimeError
                    ? .needsAttention
                    : .ok,
                .model: transcriptionNeedsAttention ? .needsAttention : .ok,
                .statistics: .ok,
                .settings: settingsStatus,
            ],
            homeIssueItems: homeIssueItems
        )
    }

    private static func makeHomeIssueItems(
        missingRequiredPermissions: [PermissionSnapshot],
        credentials: TranscriptionCredentialSnapshot,
        asrStatus: TranscriptionProviderStatus,
        transcriptionErrorMessage: String?,
        injection: TextInjectionSnapshot?,
        lastErrorMessage: String?
    ) -> [SettingsWorkbenchIssueItem] {
        var items = missingRequiredPermissions.map { permission in
            SettingsWorkbenchIssueItem(
                id: "permission-\(permission.kind.rawValue)",
                title: "\(permission.kind.title)权限缺失",
                detail: permission.kind == .accessibility
                    ? "允许后才能稳定插入当前输入框。"
                    : "允许后才能完成录音链路。"
            )
        }

        if !credentials.hasCredential || credentials.lastErrorMessage != nil {
            items.append(
                SettingsWorkbenchIssueItem(
                    id: "transcription-credential",
                    title: credentials.lastErrorMessage == nil ? "火山引擎凭证未保存" : "火山引擎凭证读取失败",
                    detail: credentials.storageDetail
                )
            )
        } else if let transcriptionErrorMessage {
            items.append(
                SettingsWorkbenchIssueItem(
                    id: "transcription-error",
                    title: "火山引擎转写失败",
                    detail: transcriptionErrorMessage
                )
            )
        } else if asrStatus.isWorkbenchAttention {
            items.append(
                SettingsWorkbenchIssueItem(
                    id: "transcription-provider",
                    title: asrStatus.workbenchIssueTitle,
                    detail: asrStatus.detail
                )
            )
        }

        if let injection, !injection.succeeded {
            items.append(
                SettingsWorkbenchIssueItem(
                    id: "text-injection",
                    title: "文本输入失败",
                    detail: injection.detail
                )
            )
        } else if let lastErrorMessage = lastErrorMessage?.nonEmpty, items.isEmpty {
            items.append(
                SettingsWorkbenchIssueItem(
                    id: "runtime-error",
                    title: "最近一次操作失败",
                    detail: lastErrorMessage
                )
            )
        }

        return items
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
