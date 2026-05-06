import Foundation

public enum OnboardingStepID: String, CaseIterable, Identifiable, Sendable {
    case microphone
    case accessibility
    case inputMonitoring
    case asrSetup
    case launchAtLogin
    case hotkeyTest

    public static let ordered: [OnboardingStepID] = [
        .microphone,
        .accessibility,
        .asrSetup,
        .launchAtLogin,
        .hotkeyTest
    ]

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .microphone:
            "麦克风权限"
        case .accessibility:
            "辅助功能权限"
        case .inputMonitoring:
            "输入监控权限"
        case .asrSetup:
            "ASR 凭证"
        case .launchAtLogin:
            "登录时启动"
        case .hotkeyTest:
            "快捷键测试"
        }
    }

    public var systemImage: String {
        switch self {
        case .microphone:
            "mic"
        case .accessibility:
            "accessibility"
        case .inputMonitoring:
            "keyboard"
        case .asrSetup:
            "key"
        case .launchAtLogin:
            "power"
        case .hotkeyTest:
            "keyboard.badge.ellipsis"
        }
    }
}

public enum OnboardingStepStatus: Equatable, Sendable {
    case complete
    case actionNeeded
    case blocked
    case skipped

    public var title: String {
        switch self {
        case .complete:
            "已完成"
        case .actionNeeded:
            "需要设置"
        case .blocked:
            "需要处理"
        case .skipped:
            "已跳过"
        }
    }

    public var systemImage: String {
        switch self {
        case .complete:
            "checkmark.circle.fill"
        case .actionNeeded:
            "exclamationmark.triangle.fill"
        case .blocked:
            "xmark.octagon.fill"
        case .skipped:
            "minus.circle.fill"
        }
    }

    public var allowsCompletion: Bool {
        switch self {
        case .complete, .skipped:
            true
        case .actionNeeded, .blocked:
            false
        }
    }
}

public struct OnboardingAction: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let settingsURLString: String?

    public init(
        id: String,
        title: String,
        systemImage: String,
        settingsURLString: String? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.settingsURLString = settingsURLString
    }
}

public struct OnboardingStepSnapshot: Equatable, Identifiable, Sendable {
    public let id: OnboardingStepID
    public let title: String
    public let detail: String
    public let systemImage: String
    public let status: OnboardingStepStatus
    public let statusDetail: String
    public let isRequired: Bool
    public let retryAction: OnboardingAction?
    public let recoveryAction: OnboardingAction?

    public init(
        id: OnboardingStepID,
        title: String? = nil,
        detail: String,
        systemImage: String? = nil,
        status: OnboardingStepStatus,
        statusDetail: String,
        isRequired: Bool,
        retryAction: OnboardingAction? = nil,
        recoveryAction: OnboardingAction? = nil
    ) {
        self.id = id
        self.title = title ?? id.title
        self.detail = detail
        self.systemImage = systemImage ?? id.systemImage
        self.status = status
        self.statusDetail = statusDetail
        self.isRequired = isRequired
        self.retryAction = retryAction
        self.recoveryAction = recoveryAction
    }

    public var isCompleteForOnboarding: Bool {
        !isRequired || status.allowsCompletion
    }
}

public struct OnboardingSnapshot: Equatable, Sendable {
    public let steps: [OnboardingStepSnapshot]

    public init(steps: [OnboardingStepSnapshot]) {
        self.steps = steps
    }

    public static func make(
        permissions: [PermissionSnapshot],
        transcriptionCredentials: TranscriptionCredentialSnapshot,
        launchAtLoginState: LaunchAtLoginState,
        hasSkippedLaunchAtLogin: Bool,
        hotkeyRuntimeState: HotkeyRuntimeState,
        hotkeyBinding: HotkeyBinding,
        hotkeyMode: HotkeyMode,
        hasVerifiedHotkey: Bool
    ) -> OnboardingSnapshot {
        let permissionSteps = [
            permissionStep(for: .microphone, permissions: permissions),
            permissionStep(for: .accessibility, permissions: permissions)
        ]

        return OnboardingSnapshot(
            steps: permissionSteps + [
                asrStep(credentials: transcriptionCredentials),
                launchAtLoginStep(state: launchAtLoginState, hasSkipped: hasSkippedLaunchAtLogin),
                hotkeyStep(
                    permissions: permissions,
                    runtimeState: hotkeyRuntimeState,
                    binding: hotkeyBinding,
                    mode: hotkeyMode,
                    hasVerifiedHotkey: hasVerifiedHotkey
                )
            ]
        )
    }

    public var isComplete: Bool {
        steps.allSatisfy(\.isCompleteForOnboarding)
    }

    public func step(id: OnboardingStepID) -> OnboardingStepSnapshot? {
        steps.first { $0.id == id }
    }

    private static func permissionStep(
        for kind: PermissionKind,
        permissions: [PermissionSnapshot]
    ) -> OnboardingStepSnapshot {
        let permission = permissions.first { $0.kind == kind } ?? PermissionSnapshot(
            kind: kind,
            state: .unknown,
            isRequired: true
        )
        let status: OnboardingStepStatus
        let statusDetail: String

        switch permission.state {
        case .granted:
            status = .complete
            statusDetail = "\(kind.title)权限已允许。"
        case .notDetermined:
            status = .actionNeeded
            statusDetail = "\(kind.title)权限尚未决定。"
        case .denied:
            status = .blocked
            statusDetail = "\(kind.title)权限已被拒绝，请在 System Settings 中恢复。"
        case .restricted:
            status = .blocked
            statusDetail = "\(kind.title)权限受系统限制。"
        case .unknown:
            status = .actionNeeded
            statusDetail = "\(kind.title)权限状态未知，请重新检查。"
        }

        let retryAction: OnboardingAction?
        let recoveryAction: OnboardingAction?
        if permission.state.isGranted {
            retryAction = nil
            recoveryAction = nil
        } else {
            retryAction = OnboardingAction(
                id: "retry-\(kind.id)",
                title: kind == .microphone ? "请求麦克风权限" : "重新检查权限",
                systemImage: kind == .microphone ? "mic.badge.plus" : "arrow.clockwise"
            )
            recoveryAction = OnboardingAction(
                id: "settings-\(kind.id)",
                title: kind.recoveryActionTitle,
                systemImage: "gear",
                settingsURLString: kind.settingsURLString
            )
        }

        return OnboardingStepSnapshot(
            id: stepID(for: kind),
            detail: kind.description,
            systemImage: kind.systemImage,
            status: status,
            statusDetail: statusDetail,
            isRequired: permission.isRequired,
            retryAction: retryAction,
            recoveryAction: recoveryAction
        )
    }

    private static func asrStep(credentials: TranscriptionCredentialSnapshot) -> OnboardingStepSnapshot {
        let status: OnboardingStepStatus
        let statusDetail: String

        if let message = credentials.lastErrorMessage {
            status = .blocked
            statusDetail = message
        } else if credentials.hasCredential {
            status = .complete
            statusDetail = credentials.maskedCredential ?? credentials.storageDetail
        } else {
            status = .actionNeeded
            statusDetail = credentials.storageDetail
        }

        return OnboardingStepSnapshot(
            id: .asrSetup,
            detail: "保存 Doubao 凭证后，Voco 才能完成本地录音后的云端转写。",
            systemImage: credentials.hasCredential ? "key.fill" : "key",
            status: status,
            statusDetail: statusDetail,
            isRequired: true,
            retryAction: OnboardingAction(id: "save-asr-key", title: "保存 API Key", systemImage: "key")
        )
    }

    private static func launchAtLoginStep(
        state: LaunchAtLoginState,
        hasSkipped: Bool
    ) -> OnboardingStepSnapshot {
        let status: OnboardingStepStatus
        let statusDetail: String

        switch state {
        case .enabled:
            status = .complete
            statusDetail = state.detail
        case .disabled:
            status = hasSkipped ? .skipped : .actionNeeded
            statusDetail = hasSkipped ? "可以稍后在设置中重新开启登录时启动。" : state.detail
        case .requiresApproval:
            status = .actionNeeded
            statusDetail = state.detail
        case .unavailable:
            status = .blocked
            statusDetail = state.detail
        case .failed(let message):
            status = .blocked
            statusDetail = message
        }

        return OnboardingStepSnapshot(
            id: .launchAtLogin,
            detail: "选择是否让 Voco 登录 macOS 后自动在菜单栏中启动。",
            status: status,
            statusDetail: statusDetail,
            isRequired: false,
            retryAction: OnboardingAction(id: "toggle-launch-at-login", title: "开启登录时启动", systemImage: "power"),
            recoveryAction: OnboardingAction(id: "skip-launch-at-login", title: "暂时跳过", systemImage: "forward")
        )
    }

    private static func hotkeyStep(
        permissions: [PermissionSnapshot],
        runtimeState: HotkeyRuntimeState,
        binding: HotkeyBinding,
        mode: HotkeyMode,
        hasVerifiedHotkey: Bool
    ) -> OnboardingStepSnapshot {
        let hasRequiredHotkeyPermissions = [PermissionKind.accessibility].allSatisfy { kind in
            permissions.first(where: { $0.kind == kind && $0.isRequired })?.state.isGranted == true
        }
        let status: OnboardingStepStatus
        let statusDetail: String

        if !hasRequiredHotkeyPermissions {
            status = .blocked
            statusDetail = "需要辅助功能权限才能测试 \(binding.displayName)。"
        } else {
            switch runtimeState {
            case .listening:
                status = hasVerifiedHotkey ? .complete : .actionNeeded
                statusDetail = hasVerifiedHotkey
                    ? "\(binding.displayName) · \(mode.title) 已确认。"
                    : "按下 \(binding.displayName) 以确认 \(mode.title) 快捷键可用。"
            case .inactive:
                status = .actionNeeded
                statusDetail = "快捷键监听尚未启动，请重新检查。"
            case .permissionNeeded:
                status = .blocked
                statusDetail = runtimeState.detail
            case .failed(let message):
                status = .blocked
                statusDetail = message
            }
        }

        return OnboardingStepSnapshot(
            id: .hotkeyTest,
            detail: "确认全局快捷键可以在不聚焦 Voco 的情况下触发录音。",
            status: status,
            statusDetail: statusDetail,
            isRequired: true,
            retryAction: OnboardingAction(id: "verify-hotkey", title: "我已测试快捷键", systemImage: "checkmark")
        )
    }

    private static func stepID(for kind: PermissionKind) -> OnboardingStepID {
        switch kind {
        case .microphone:
            .microphone
        case .accessibility:
            .accessibility
        case .inputMonitoring:
            .inputMonitoring
        }
    }
}

public struct OnboardingCompletionResolution: Equatable, Sendable {
    public let hasCompletedOnboarding: Bool
    public let valueToPersist: Bool?

    public init(hasCompletedOnboarding: Bool, valueToPersist: Bool?) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.valueToPersist = valueToPersist
    }
}

public enum OnboardingCompletionMigration {
    public static func resolvedCompletion(
        storedValue: Bool?,
        permissions: [PermissionSnapshot],
        transcriptionCredentials: TranscriptionCredentialSnapshot
    ) -> Bool {
        resolution(
            storedValue: storedValue,
            permissions: permissions,
            transcriptionCredentials: transcriptionCredentials
        ).hasCompletedOnboarding
    }

    public static func resolution(
        storedValue: Bool?,
        permissions: [PermissionSnapshot],
        transcriptionCredentials: TranscriptionCredentialSnapshot
    ) -> OnboardingCompletionResolution {
        if let storedValue {
            return OnboardingCompletionResolution(
                hasCompletedOnboarding: storedValue,
                valueToPersist: nil
            )
        }

        let inferredCompletion = PermissionSummary(snapshots: permissions).allRequiredGranted &&
            transcriptionCredentials.hasCredential
        return OnboardingCompletionResolution(
            hasCompletedOnboarding: inferredCompletion,
            valueToPersist: inferredCompletion ? true : nil
        )
    }
}
