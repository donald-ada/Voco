import Combine
import Foundation

public enum AppRuntimeStatus: Equatable, Sendable {
    case launching
    case needsOnboarding
    case ready
    case recording
    case transcribing
    case injecting
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
    @Published public private(set) var transcriptionProviderStatus: TranscriptionProviderStatus
    @Published public private(set) var transcriptionCredentials: TranscriptionCredentialSnapshot
    @Published public private(set) var lastAudio: CapturedAudioSnapshot?
    @Published public private(set) var lastTranscript: TranscriptSnapshot?
    @Published public private(set) var lastInjection: TextInjectionSnapshot?

    private let hasCompletedOnboarding: Bool
    private let permissionProvider: any PermissionProviding
    private let launchAtLoginProvider: any LaunchAtLoginProviding
    private let recordingWorkflow: any RecordingWorkflowing
    private let hotkeyProvider: any HotkeyProviding
    private let transcriptionCredentialStore: any TranscriptionCredentialStoring
    public let hotkeyBinding: HotkeyBinding
    public let hotkeyMode: HotkeyMode

    public init(
        hasCompletedOnboarding: Bool = false,
        launchAtLoginEnabled: Bool = false,
        permissionProvider: any PermissionProviding = StaticPermissionProvider.allGranted,
        launchAtLoginProvider: any LaunchAtLoginProviding = StaticLaunchAtLoginProvider(),
        transcriptionCredentialStore: any TranscriptionCredentialStoring = InMemoryTranscriptionCredentialStore(),
        recordingWorkflow: any RecordingWorkflowing = StaticRecordingWorkflow(),
        hotkeyProvider: any HotkeyProviding = StaticHotkeyProvider(),
        hotkeyBinding: HotkeyBinding = .default,
        hotkeyMode: HotkeyMode = .toggle
    ) {
        self.status = .launching
        self.lastErrorMessage = nil
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.permissionProvider = permissionProvider
        self.launchAtLoginProvider = launchAtLoginProvider
        self.recordingWorkflow = recordingWorkflow
        self.hotkeyProvider = hotkeyProvider
        self.transcriptionCredentialStore = transcriptionCredentialStore
        self.hotkeyBinding = hotkeyBinding
        self.hotkeyMode = hotkeyMode
        self.permissions = permissionProvider.currentSnapshots()
        self.launchAtLoginState = launchAtLoginEnabled ? .enabled : launchAtLoginProvider.currentState()
        self.hotkeyRuntimeState = .inactive
        self.transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
        self.transcriptionCredentials = transcriptionCredentialStore.currentSnapshot()
        self.lastAudio = nil
        self.lastTranscript = nil
        self.lastInjection = nil
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

    public var hudSnapshot: HUDSnapshot {
        HUDSnapshot(
            status: status,
            lastTranscript: lastTranscript,
            lastInjection: lastInjection,
            lastErrorMessage: lastErrorMessage
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
        transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
        refreshTranscriptionCredentials()
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
        transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
        refreshTranscriptionCredentials()
        refreshPermissions()
    }

    public func refreshTranscriptionCredentials() {
        transcriptionCredentials = transcriptionCredentialStore.currentSnapshot()
        if let message = transcriptionCredentials.lastErrorMessage {
            lastErrorMessage = message
        }
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
        Task { [weak self] in
            await self?.toggleRecordingFromUserAction()
        }
    }

    public func toggleRecordingFromUserAction() async {
        switch status {
        case .ready:
            await startRecording()
        case .recording:
            await stopRecording()
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

    public func saveTranscriptionAPIKey(_ apiKey: String) async {
        do {
            transcriptionCredentials = try await transcriptionCredentialStore.saveAPIKey(apiKey, for: .doubao)
            lastErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            transcriptionCredentials = .failed(provider: .doubao, message: message)
            lastErrorMessage = message
        }
    }

    public func clearTranscriptionCredentials() async {
        do {
            transcriptionCredentials = try await transcriptionCredentialStore.deleteCredentials(for: .doubao)
            lastErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            transcriptionCredentials = .failed(provider: .doubao, message: message)
            lastErrorMessage = message
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
            Task { [weak self] in
                await self?.toggleRecordingFromUserAction()
            }
        case .startRecording:
            Task { [weak self] in
                await self?.startRecording()
            }
        case .stopRecording:
            Task { [weak self] in
                await self?.stopRecording()
            }
        }
    }

    private func startRecording() async {
        guard status == .ready else {
            return
        }

        lastErrorMessage = nil
        lastAudio = nil
        lastTranscript = nil
        lastInjection = nil
        status = .recording

        do {
            try await recordingWorkflow.startRecording()
        } catch {
            failFromWorkflowError(error)
        }
    }

    private func stopRecording() async {
        guard status == .recording else {
            return
        }

        status = .transcribing

        do {
            let result = try await recordingWorkflow.stopRecording { [weak self] partial in
                self?.publishTranscriptPartial(partial)
            }
            lastAudio = result.audio
            lastTranscript = result.transcript
            lastInjection = result.injection

            if result.injection.strategy != .skippedEmpty {
                status = .injecting
            }

            if result.injection.succeeded {
                lastErrorMessage = nil
                status = .ready
            } else {
                fail(result.injection.detail)
            }
        } catch {
            failFromWorkflowError(error)
        }
    }

    private func failFromWorkflowError(_ error: Error) {
        lastErrorMessage = error.localizedDescription
        if error is TranscriptionProviderError {
            status = .providerOffline
        } else {
            status = .error
        }
    }

    private func publishTranscriptPartial(_ partial: TranscriptPartialSnapshot) {
        let baseTranscript = lastTranscript ?? TranscriptSnapshot(
            finalText: "",
            partials: [],
            providerName: partial.providerName,
            latencyMilliseconds: nil
        )
        lastTranscript = baseTranscript.appendingPartial(partial)
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
        case .injecting:
            "插入中"
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
        case .injecting:
            "text.cursor"
        case .permissionNeeded:
            "lock.shield"
        case .providerOffline:
            "wifi.slash"
        case .error:
            "xmark.octagon"
        }
    }
}
