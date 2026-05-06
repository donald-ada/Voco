import Combine
import Foundation

public enum AppRuntimeStatus: Equatable, Sendable {
    case launching
    case needsOnboarding
    case ready
    case recording
    case transcribing
    case permissionNeeded
    case providerOffline
    case error
}

public enum TranscriptionCompletionResult: Equatable, Sendable {
    case success
    case failure(String)
}

public struct MenuBarSnapshot: Equatable, Sendable {
    public let status: AppRuntimeStatus
    public let title: String
    public let systemImage: String
    public let templateIconResourceName: String
    public let isRecordingActionEnabled: Bool
    public let canOpenSettings: Bool

    public init(
        status: AppRuntimeStatus,
        title: String,
        systemImage: String,
        templateIconResourceName: String,
        isRecordingActionEnabled: Bool,
        canOpenSettings: Bool
    ) {
        self.status = status
        self.title = title
        self.systemImage = systemImage
        self.templateIconResourceName = templateIconResourceName
        self.isRecordingActionEnabled = isRecordingActionEnabled
        self.canOpenSettings = canOpenSettings
    }
}

@MainActor
public final class AppCoordinator: ObservableObject {
    @Published public private(set) var status: AppRuntimeStatus
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var launchAtLoginEnabled: Bool
    @Published public private(set) var permissions: [PermissionSnapshot]

    private let hasCompletedOnboarding: Bool
    private let permissionProvider: any PermissionProviding

    public init(
        hasCompletedOnboarding: Bool = false,
        launchAtLoginEnabled: Bool = false,
        permissionProvider: any PermissionProviding = StaticPermissionProvider.allGranted
    ) {
        self.status = .launching
        self.lastErrorMessage = nil
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.permissionProvider = permissionProvider
        self.permissions = permissionProvider.currentSnapshots()
    }

    public var snapshot: MenuBarSnapshot {
        MenuBarSnapshot(
            status: status,
            title: status.menuBarTitle,
            systemImage: status.systemImage,
            templateIconResourceName: "VocoMenuBarIconTemplate",
            isRecordingActionEnabled: status == .ready,
            canOpenSettings: true
        )
    }

    public var isRecording: Bool {
        status == .recording
    }

    public var permissionSummary: PermissionSummary {
        PermissionSummary(snapshots: permissions)
    }

    public func finishLaunching() {
        lastErrorMessage = nil
        permissions = permissionProvider.currentSnapshots()
        status = hasCompletedOnboarding && permissionSummary.allRequiredGranted ? .ready : .needsOnboarding
    }

    public func refreshPermissions() {
        let shouldUpdateRuntimeStatus = status == .ready || status == .permissionNeeded
        permissions = permissionProvider.currentSnapshots()

        guard shouldUpdateRuntimeStatus else {
            return
        }

        status = permissionSummary.allRequiredGranted ? .ready : .permissionNeeded
    }

    public func requestMicrophonePermission() async {
        let shouldUpdateRuntimeStatus = status == .ready || status == .permissionNeeded
        permissions = await permissionProvider.requestMicrophoneAccess()

        if shouldUpdateRuntimeStatus {
            status = permissionSummary.allRequiredGranted ? .ready : .permissionNeeded
        } else {
            status = hasCompletedOnboarding && permissionSummary.allRequiredGranted ? .ready : .needsOnboarding
        }
    }

    public func toggleRecordingFromMenu() {
        switch status {
        case .ready:
            lastErrorMessage = nil
            status = .recording
        case .recording:
            status = .transcribing
        default:
            break
        }
    }

    public func finishTranscribing(result: TranscriptionCompletionResult) {
        switch result {
        case .success:
            lastErrorMessage = nil
            status = .ready
        case .failure(let message):
            fail(message)
        }
    }

    public func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginEnabled = enabled
    }

    public func fail(_ message: String) {
        lastErrorMessage = message
        status = .error
    }
}

private extension AppRuntimeStatus {
    var menuBarTitle: String {
        switch self {
        case .launching:
            "启动中"
        case .needsOnboarding:
            "需要设置"
        case .ready:
            "就绪"
        case .recording:
            "录音中"
        case .transcribing:
            "转写中"
        case .permissionNeeded:
            "需要权限"
        case .providerOffline:
            "服务离线"
        case .error:
            "错误"
        }
    }

    var systemImage: String {
        switch self {
        case .launching:
            "hourglass"
        case .needsOnboarding:
            "exclamationmark.triangle"
        case .ready:
            "waveform"
        case .recording:
            "record.circle"
        case .transcribing:
            "ellipsis.bubble"
        case .permissionNeeded:
            "lock.shield"
        case .providerOffline:
            "wifi.slash"
        case .error:
            "xmark.octagon"
        }
    }
}
