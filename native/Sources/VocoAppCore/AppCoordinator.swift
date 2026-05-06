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
    @Published public private(set) var launchAtLoginState: LaunchAtLoginState
    @Published public private(set) var permissions: [PermissionSnapshot]
    @Published public private(set) var hotkeyRuntimeState: HotkeyRuntimeState

    private let hasCompletedOnboarding: Bool
    private let permissionProvider: any PermissionProviding
    private let launchAtLoginProvider: any LaunchAtLoginProviding
    private let hotkeyProvider: any HotkeyProviding
    public let hotkeyBinding: HotkeyBinding
    public let hotkeyMode: HotkeyMode

    public init(
        hasCompletedOnboarding: Bool = false,
        launchAtLoginEnabled: Bool = false,
        permissionProvider: any PermissionProviding = StaticPermissionProvider.allGranted,
        launchAtLoginProvider: any LaunchAtLoginProviding = StaticLaunchAtLoginProvider(),
        hotkeyProvider: any HotkeyProviding = StaticHotkeyProvider(),
        hotkeyBinding: HotkeyBinding = .default,
        hotkeyMode: HotkeyMode = .toggle
    ) {
        self.status = .launching
        self.lastErrorMessage = nil
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.permissionProvider = permissionProvider
        self.launchAtLoginProvider = launchAtLoginProvider
        self.hotkeyProvider = hotkeyProvider
        self.hotkeyBinding = hotkeyBinding
        self.hotkeyMode = hotkeyMode
        self.permissions = permissionProvider.currentSnapshots()
        self.launchAtLoginState = launchAtLoginEnabled ? .enabled : launchAtLoginProvider.currentState()
        self.hotkeyRuntimeState = .inactive
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

    public var launchAtLoginEnabled: Bool {
        launchAtLoginState.isEnabled
    }

    public func finishLaunching() {
        lastErrorMessage = nil
        permissions = permissionProvider.currentSnapshots()
        launchAtLoginState = launchAtLoginProvider.currentState()
        status = hasCompletedOnboarding && permissionSummary.allRequiredGranted ? .ready : .needsOnboarding
        refreshHotkeyRuntime()
    }

    public func refreshPermissions() {
        let shouldUpdateRuntimeStatus =
            status == .ready ||
            status == .permissionNeeded ||
            (status == .needsOnboarding && hasCompletedOnboarding)
        permissions = permissionProvider.currentSnapshots()

        guard shouldUpdateRuntimeStatus else {
            return
        }

        status = permissionSummary.allRequiredGranted ? .ready : .permissionNeeded
        refreshHotkeyRuntime()
    }

    public func prepareForSettingsPresentation() {
        refreshPermissions()
    }

    public func requestMicrophonePermission() async {
        let shouldUpdateRuntimeStatus = status == .ready || status == .permissionNeeded
        permissions = await permissionProvider.requestMicrophoneAccess()

        if shouldUpdateRuntimeStatus {
            status = permissionSummary.allRequiredGranted ? .ready : .permissionNeeded
        } else {
            status = hasCompletedOnboarding && permissionSummary.allRequiredGranted ? .ready : .needsOnboarding
        }
        refreshHotkeyRuntime()
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

    public func setLaunchAtLoginEnabled(_ enabled: Bool) async {
        do {
            launchAtLoginState = try await launchAtLoginProvider.setEnabled(enabled)
            lastErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            launchAtLoginState = .failed(message)
            lastErrorMessage = "登录时启动设置失败：\(message)"
        }
    }

    public func fail(_ message: String) {
        lastErrorMessage = message
        status = .error
    }

    private func refreshHotkeyRuntime() {
        guard hotkeyPermissionsGranted else {
            hotkeyProvider.stop()
            hotkeyRuntimeState = .permissionNeeded
            return
        }

        guard status == .ready || status == .recording || status == .transcribing else {
            hotkeyProvider.stop()
            hotkeyRuntimeState = .inactive
            return
        }

        if hotkeyRuntimeState == .listening {
            return
        }

        hotkeyRuntimeState = hotkeyProvider.start(
            binding: hotkeyBinding,
            mode: hotkeyMode
        ) { [weak self] action in
            self?.handleHotkeyAction(action)
        }

        if case .failed(let message) = hotkeyRuntimeState {
            lastErrorMessage = message
        }
    }

    private var hotkeyPermissionsGranted: Bool {
        for kind in [PermissionKind.accessibility, .inputMonitoring] {
            if permissions.first(where: { $0.kind == kind && $0.isRequired })?.state.isGranted != true {
                return false
            }
        }
        return true
    }

    private func handleHotkeyAction(_ action: HotkeyAction) {
        switch action {
        case .toggleRecording:
            toggleRecordingFromMenu()
        case .startRecording:
            if status == .ready {
                lastErrorMessage = nil
                status = .recording
            }
        case .stopRecording:
            if status == .recording {
                status = .transcribing
            }
        }
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
