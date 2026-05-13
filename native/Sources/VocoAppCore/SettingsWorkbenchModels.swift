import Foundation

public enum SettingsWorkbenchSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case model
    case skills
    case statistics
    case settings

    public var id: String { rawValue }

    public var title: String {
        title(strings: VocoStrings())
    }

    public func title(strings: VocoStrings) -> String {
        switch self {
        case .overview:
            strings.language == .zhHans ? "主页" : "Home"
        case .model:
            strings.language == .zhHans ? "模型" : "Model"
        case .skills:
            strings.skills.title
        case .statistics:
            strings.language == .zhHans ? "统计" : "Statistics"
        case .settings:
            strings.language == .zhHans ? "设置" : "Settings"
        }
    }

    public var summary: String {
        summary(strings: VocoStrings())
    }

    public func summary(strings: VocoStrings) -> String {
        switch self {
        case .overview:
            strings.language == .zhHans ? "当前状态" : "Current status"
        case .model:
            strings.language == .zhHans ? "火山引擎和 Keychain" : "Volcengine and Keychain"
        case .skills:
            strings.language == .zhHans ? "转写清理和动作" : "Transcript cleanup and actions"
        case .statistics:
            strings.language == .zhHans ? "使用趋势和分布" : "Usage trends and distribution"
        case .settings:
            strings.language == .zhHans ? "快捷键、麦克风、系统" : "Hotkey, microphone, and system"
        }
    }
}

public enum SettingsWorkbenchActionID {
    public static let checkMicrophone = "checkMicrophone"
    public static let openModel = "openModel"
    public static let openSettings = "openSettings"
    public static let openAccessibilitySettings = "openAccessibilitySettings"
    public static let refresh = "refresh"
    public static let startTestRecording = "startTestRecording"
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
    public let primaryActionID: String
    public let secondaryActionID: String
    public let primaryActionDisplayTitle: String
    public let secondaryActionDisplayTitle: String

    public init(
        title: String,
        detail: String,
        primaryActionID: String,
        secondaryActionID: String = SettingsWorkbenchActionID.refresh,
        primaryActionDisplayTitle: String,
        secondaryActionDisplayTitle: String
    ) {
        self.title = title
        self.detail = detail
        self.primaryActionID = primaryActionID
        self.secondaryActionID = secondaryActionID
        self.primaryActionDisplayTitle = primaryActionDisplayTitle
        self.secondaryActionDisplayTitle = secondaryActionDisplayTitle
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
        strings: VocoStrings = VocoStrings(),
        statusTitle: String,
        permissions: [PermissionSnapshot],
        hotkeyState: HotkeyRuntimeState,
        hotkeyBinding: HotkeyBinding,
        hotkeyMode: HotkeyMode,
        asrStatus: TranscriptionProviderStatus,
        credentials: TranscriptionCredentialSnapshot,
        injection: TextInjectionSnapshot?,
        lastErrorMessage: String?,
        modelSelection: TranscriptionModelSelection = .default,
        localModelStatus: LocalSpeechModelStatus = .notDownloaded,
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
        let workbenchStrings = strings.workbench
        let localModelIssue = localModelIssue(
            strings: workbenchStrings,
            modelSelection: modelSelection,
            localModelStatus: localModelStatus
        )
        let credentialNeedsAttention = modelSelection.providerID == .volcengine &&
            (!credentials.hasCredential || credentials.lastErrorMessage != nil)

        let overview: SettingsWorkbenchOverviewSnapshot
        if let requiredMissing {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: workbenchStrings.permissionMissingTitle(kind: requiredMissing.kind),
                detail: workbenchStrings.permissionMissingDetail(kind: requiredMissing.kind),
                primaryActionID: requiredMissing.kind == .microphone
                    ? SettingsWorkbenchActionID.checkMicrophone
                    : SettingsWorkbenchActionID.openAccessibilitySettings,
                primaryActionDisplayTitle: requiredMissing.kind == .microphone
                    ? workbenchStrings.checkMicrophoneAction
                    : workbenchStrings.openAccessibilitySettingsAction,
                secondaryActionDisplayTitle: workbenchStrings.refreshAction
            )
        } else if let localModelIssue {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: localModelIssue.title,
                detail: localModelIssue.detail,
                primaryActionID: SettingsWorkbenchActionID.openModel,
                primaryActionDisplayTitle: workbenchStrings.openModelAction,
                secondaryActionDisplayTitle: workbenchStrings.refreshAction
            )
        } else if credentialNeedsAttention {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: workbenchStrings.credentialTitle(hasError: credentials.lastErrorMessage != nil),
                detail: workbenchStrings.credentialDetail(lastErrorMessage: credentials.lastErrorMessage),
                primaryActionID: SettingsWorkbenchActionID.openModel,
                primaryActionDisplayTitle: workbenchStrings.openModelAction,
                secondaryActionDisplayTitle: workbenchStrings.refreshAction
            )
        } else if let transcriptionErrorMessage {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: workbenchStrings.transcriptionFailedTitle,
                detail: workbenchStrings.transcriptionFailureDetail(transcriptionErrorMessage),
                primaryActionID: SettingsWorkbenchActionID.openModel,
                primaryActionDisplayTitle: workbenchStrings.openModelAction,
                secondaryActionDisplayTitle: workbenchStrings.refreshAction
            )
        } else if asrStatus.isWorkbenchAttention {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: workbenchStrings.providerIssueTitle(for: asrStatus),
                detail: workbenchStrings.providerIssueDetail(for: asrStatus),
                primaryActionID: SettingsWorkbenchActionID.openModel,
                primaryActionDisplayTitle: workbenchStrings.openModelAction,
                secondaryActionDisplayTitle: workbenchStrings.refreshAction
            )
        } else if let injection, !injection.succeeded {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: workbenchStrings.textInputFailedTitle,
                detail: workbenchStrings.textInputFailureDetail(injection.detail(strings: strings)),
                primaryActionID: SettingsWorkbenchActionID.openSettings,
                primaryActionDisplayTitle: workbenchStrings.openSettingsAction,
                secondaryActionDisplayTitle: workbenchStrings.refreshAction
            )
        } else if let lastErrorMessage, !lastErrorMessage.isEmpty {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: workbenchStrings.recentOperationFailedTitle,
                detail: workbenchStrings.recentOperationFailureDetail(lastErrorMessage),
                primaryActionID: SettingsWorkbenchActionID.refresh,
                primaryActionDisplayTitle: workbenchStrings.refreshAction,
                secondaryActionDisplayTitle: workbenchStrings.refreshAction
            )
        } else {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: workbenchStrings.readyTitle,
                detail: workbenchStrings.readyDetail,
                primaryActionID: SettingsWorkbenchActionID.startTestRecording,
                primaryActionDisplayTitle: workbenchStrings.startTestRecordingAction,
                secondaryActionDisplayTitle: workbenchStrings.refreshAction
            )
        }

        let hasRequiredPermissionProblem = requiredMissing != nil
        let transcriptionNeedsAttention = localModelIssue != nil ||
            credentialNeedsAttention ||
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
            appStrings: strings,
            strings: workbenchStrings,
            missingRequiredPermissions: missingRequiredPermissions,
            credentials: credentials,
            asrStatus: asrStatus,
            modelSelection: modelSelection,
            localModelStatus: localModelStatus,
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
                .skills: .neutral,
                .statistics: .ok,
                .settings: settingsStatus,
            ],
            homeIssueItems: homeIssueItems
        )
    }

    private static func makeHomeIssueItems(
        appStrings: VocoStrings,
        strings: SettingsWorkbenchStrings,
        missingRequiredPermissions: [PermissionSnapshot],
        credentials: TranscriptionCredentialSnapshot,
        asrStatus: TranscriptionProviderStatus,
        modelSelection: TranscriptionModelSelection,
        localModelStatus: LocalSpeechModelStatus,
        transcriptionErrorMessage: String?,
        injection: TextInjectionSnapshot?,
        lastErrorMessage: String?
    ) -> [SettingsWorkbenchIssueItem] {
        var items = missingRequiredPermissions.map { permission in
            SettingsWorkbenchIssueItem(
                id: "permission-\(permission.kind.rawValue)",
                title: strings.permissionMissingTitle(kind: permission.kind),
                detail: strings.permissionIssueDetail(kind: permission.kind)
            )
        }

        if let localModelIssue = localModelIssue(
            strings: strings,
            modelSelection: modelSelection,
            localModelStatus: localModelStatus
        ) {
            items.append(localModelIssue)
        } else if modelSelection.providerID == .volcengine &&
            (!credentials.hasCredential || credentials.lastErrorMessage != nil) {
            items.append(
                SettingsWorkbenchIssueItem(
                    id: "transcription-credential",
                    title: strings.credentialTitle(hasError: credentials.lastErrorMessage != nil),
                    detail: strings.credentialDetail(lastErrorMessage: credentials.lastErrorMessage)
                )
            )
        } else if let transcriptionErrorMessage {
            items.append(
                SettingsWorkbenchIssueItem(
                    id: "transcription-error",
                    title: strings.transcriptionFailedTitle,
                    detail: strings.transcriptionFailureDetail(transcriptionErrorMessage)
                )
            )
        } else if asrStatus.isWorkbenchAttention {
            items.append(
                SettingsWorkbenchIssueItem(
                    id: "transcription-provider",
                    title: strings.providerIssueTitle(for: asrStatus),
                    detail: strings.providerIssueDetail(for: asrStatus)
                )
            )
        }

        if let injection, !injection.succeeded {
            items.append(
                SettingsWorkbenchIssueItem(
                    id: "text-injection",
                    title: strings.textInputFailedTitle,
                    detail: strings.textInputFailureDetail(injection.detail(strings: appStrings))
                )
            )
        } else if let lastErrorMessage = lastErrorMessage?.nonEmpty, items.isEmpty {
            items.append(
                SettingsWorkbenchIssueItem(
                    id: "runtime-error",
                    title: strings.recentOperationFailedTitle,
                    detail: strings.recentOperationFailureDetail(lastErrorMessage)
                )
            )
        }

        return items
    }

    private static func localModelIssue(
        strings: SettingsWorkbenchStrings,
        modelSelection: TranscriptionModelSelection,
        localModelStatus: LocalSpeechModelStatus
    ) -> SettingsWorkbenchIssueItem? {
        guard modelSelection.providerID == .localRecommended else {
            return nil
        }

        let title: String
        let detail: String

        switch (strings.language, localModelStatus) {
        case (_, .ready):
            return nil
        case (.zhHans, .notDownloaded):
            title = "本地模型未下载"
            detail = "本地模型未下载。"
        case (.en, .notDownloaded):
            title = "Local model not downloaded"
            detail = "Local model is not downloaded."
        case (.zhHans, .downloading):
            title = "本地模型下载中"
            detail = "本地模型正在下载。"
        case (.en, .downloading):
            title = "Local model downloading"
            detail = "Local model is downloading."
        case (.zhHans, .verifying):
            title = "本地模型校验中"
            detail = "本地模型正在校验。"
        case (.en, .verifying):
            title = "Local model verifying"
            detail = "Local model is verifying."
        case (.zhHans, .failed(let message)), (.zhHans, .unavailable(let message)):
            title = "本地模型不可用"
            detail = message
        case (.en, .failed(let message)), (.en, .unavailable(let message)):
            title = "Local model unavailable"
            detail = message
        }

        return SettingsWorkbenchIssueItem(
            id: "local-model",
            title: title,
            detail: detail
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
}
