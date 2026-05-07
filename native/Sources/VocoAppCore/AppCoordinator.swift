import Combine
import Foundation

public enum AppRuntimeStatus: Equatable, Sendable {
    case launching
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
    @Published public private(set) var installLocation: InstallLocationSnapshot
    @Published public private(set) var legacyInstall: LegacyInstallSnapshot
    @Published public private(set) var isRemovingLegacyLaunchAgent: Bool
    @Published public private(set) var lastAudio: CapturedAudioSnapshot?
    @Published public private(set) var lastTranscript: TranscriptSnapshot?
    @Published public private(set) var lastInjection: TextInjectionSnapshot?
    @Published public private(set) var hotkeyBinding: HotkeyBinding
    @Published public private(set) var hotkeyMode: HotkeyMode
    @Published public private(set) var selectedAudioInputDevice: AudioInputDeviceSelection

    private let permissionProvider: any PermissionProviding
    private let launchAtLoginProvider: any LaunchAtLoginProviding
    private let recordingWorkflow: any RecordingWorkflowing
    private let hotkeyProvider: any HotkeyProviding
    private let transcriptionCredentialStore: any TranscriptionCredentialStoring
    private let installLocationProvider: any InstallLocationProviding
    private let legacyInstallProvider: any LegacyInstallProviding
    private let voiceInputPreferenceStore: any VoiceInputPreferenceStoring
    private var activeTranscriptionSessionID: UUID?
    private var isRecordingWorkflowTransitionActive: Bool
    private var pendingStopAfterRecordingStart: Bool

    public init(
        launchAtLoginEnabled: Bool = false,
        permissionProvider: any PermissionProviding = StaticPermissionProvider.allGranted,
        launchAtLoginProvider: any LaunchAtLoginProviding = StaticLaunchAtLoginProvider(),
        transcriptionCredentialStore: any TranscriptionCredentialStoring = InMemoryTranscriptionCredentialStore(),
        recordingWorkflow: any RecordingWorkflowing = StaticRecordingWorkflow(),
        hotkeyProvider: any HotkeyProviding = StaticHotkeyProvider(),
        installLocationProvider: any InstallLocationProviding = StaticInstallLocationProvider(),
        legacyInstallProvider: any LegacyInstallProviding = StaticLegacyInstallProvider(),
        voiceInputPreferenceStore: any VoiceInputPreferenceStoring = NoOpVoiceInputPreferenceStore(),
        hotkeyBinding: HotkeyBinding = .default,
        hotkeyMode: HotkeyMode = .toggle
    ) {
        let initialPermissions = permissionProvider.currentSnapshots()
        let initialLaunchAtLoginState = launchAtLoginEnabled ? LaunchAtLoginState.enabled : launchAtLoginProvider.currentState()
        let initialTranscriptionCredentials = transcriptionCredentialStore.currentSnapshot()
        let initialInstallLocation = installLocationProvider.currentInstallLocation()
        let initialLegacyInstall = LegacyInstallSnapshot.notFound(
            launchAgentURL: LegacyInstallSnapshot.knownLaunchAgentURL(
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
        )

        self.status = .launching
        self.lastErrorMessage = nil
        self.permissionProvider = permissionProvider
        self.launchAtLoginProvider = launchAtLoginProvider
        self.recordingWorkflow = recordingWorkflow
        self.hotkeyProvider = hotkeyProvider
        self.transcriptionCredentialStore = transcriptionCredentialStore
        self.installLocationProvider = installLocationProvider
        self.legacyInstallProvider = legacyInstallProvider
        self.voiceInputPreferenceStore = voiceInputPreferenceStore
        self.permissions = initialPermissions
        self.launchAtLoginState = initialLaunchAtLoginState
        self.hotkeyRuntimeState = .inactive
        self.transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
        self.transcriptionCredentials = initialTranscriptionCredentials
        self.installLocation = initialInstallLocation
        self.legacyInstall = initialLegacyInstall
        self.isRemovingLegacyLaunchAgent = false
        self.lastAudio = nil
        self.lastTranscript = nil
        self.lastInjection = nil
        self.hotkeyBinding = hotkeyBinding
        self.hotkeyMode = hotkeyMode
        self.selectedAudioInputDevice = recordingWorkflow.selectedAudioInputDevice
        self.activeTranscriptionSessionID = nil
        self.isRecordingWorkflowTransitionActive = false
        self.pendingStopAfterRecordingStart = false
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

    public var settingsWorkbenchSnapshot: SettingsWorkbenchSnapshot {
        SettingsWorkbenchSnapshot.make(
            statusTitle: snapshot.title,
            permissions: permissions,
            hotkeyState: hotkeyRuntimeState,
            hotkeyBinding: hotkeyBinding,
            hotkeyMode: hotkeyMode,
            asrStatus: transcriptionProviderStatus,
            credentials: transcriptionCredentials,
            injection: lastInjection,
            lastErrorMessage: lastErrorMessage,
            transcriptionErrorMessage: status == .providerOffline ? lastErrorMessage : nil
        )
    }

    public var audioSettingsSnapshot: AudioSettingsSnapshot {
        AudioSettingsSnapshot(
            lastAudio: lastAudio,
            inputDevice: selectedAudioInputDevice
        )
    }

    public var availableAudioInputDevices: [AudioInputDeviceSelection] {
        let devices = recordingWorkflow.availableAudioInputDevices
        return devices.isEmpty ? [.systemDefault] : devices
    }

    public var injectionSettingsSnapshot: InjectionSettingsSnapshot {
        InjectionSettingsSnapshot(lastInjection: lastInjection)
    }

    public var hudSettingsSnapshot: HUDSettingsSnapshot {
        HUDSettingsSnapshot()
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
        installLocation = installLocationProvider.currentInstallLocation()
        refreshLegacyInstall()
        permissions = permissionProvider.currentSnapshots()
        launchAtLoginState = launchAtLoginProvider.currentState()
        transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
        refreshTranscriptionCredentials()
        status = runtimeStatusAfterPermissionCheck()
        refreshHotkeyRuntime()
    }

    public func refreshPermissions() {
        let shouldUpdateRuntimeStatus =
            status == .ready ||
            status == .permissionNeeded
        permissions = permissionProvider.currentSnapshots()

        if shouldUpdateRuntimeStatus {
            status = permissionSummary.allRequiredGranted ? .ready : .permissionNeeded
        }

        refreshHotkeyRuntime()
    }

    public func prepareForSettingsPresentation() {
        transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
        refreshLegacyInstall()
        refreshTranscriptionCredentials()
        refreshPermissions()
    }

    public func refreshLegacyInstall() {
        legacyInstall = legacyInstallProvider.currentSnapshot()
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
            status = runtimeStatusAfterPermissionCheck()
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
        installLocation = installLocationProvider.currentInstallLocation()
        if enabled, !installLocation.allowsLaunchAtLogin {
            let message = installLocation.warningDetail ?? "当前运行位置不支持登录时启动。"
            launchAtLoginState = .unavailable
            lastErrorMessage = message
            return
        }

        do {
            launchAtLoginState = try await launchAtLoginProvider.setEnabled(enabled)
            lastErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            launchAtLoginState = .failed(message)
            lastErrorMessage = "登录时启动设置失败：\(message)"
        }
    }

    public func setHotkeyPreset(_ preset: HotkeyPreset) {
        guard hotkeyBinding != preset.binding else {
            voiceInputPreferenceStore.saveHotkeyPreset(preset)
            return
        }

        hotkeyBinding = preset.binding
        voiceInputPreferenceStore.saveHotkeyPreset(preset)
        restartHotkeyRuntime()
    }

    public func setHotkeyBinding(_ binding: HotkeyBinding) {
        guard hotkeyBinding != binding else {
            if let preset = HotkeyPreset.matching(binding) {
                voiceInputPreferenceStore.saveHotkeyPreset(preset)
            }
            return
        }

        hotkeyBinding = binding
        if let preset = HotkeyPreset.matching(binding) {
            voiceInputPreferenceStore.saveHotkeyPreset(preset)
        }
        restartHotkeyRuntime()
    }

    public func setHotkeyMode(_ mode: HotkeyMode) {
        guard hotkeyMode != mode else {
            voiceInputPreferenceStore.saveHotkeyMode(mode)
            return
        }

        hotkeyMode = mode
        voiceInputPreferenceStore.saveHotkeyMode(mode)
        restartHotkeyRuntime()
    }

    public func setAudioInputDevice(_ device: AudioInputDeviceSelection) {
        guard selectedAudioInputDevice != device else {
            voiceInputPreferenceStore.saveAudioInputDevice(device)
            return
        }

        recordingWorkflow.setAudioInputDevice(device)
        selectedAudioInputDevice = recordingWorkflow.selectedAudioInputDevice
        voiceInputPreferenceStore.saveAudioInputDevice(selectedAudioInputDevice)
        lastErrorMessage = nil
    }

    public func saveTranscriptionAPIKey(_ apiKey: String) async {
        await saveTranscriptionCredential(.doubaoAPIKey(apiKey))
    }

    public func saveDoubaoAppIDAccessToken(appID: String, accessToken: String) async {
        await saveTranscriptionCredential(
            .doubaoAppIDAccessToken(appID: appID, accessToken: accessToken)
        )
    }

    public func saveTranscriptionCredential(_ credential: TranscriptionCredential) async {
        do {
            transcriptionCredentials = try await transcriptionCredentialStore.saveCredential(credential, for: .doubao)
            transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
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
            transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
            lastErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            transcriptionCredentials = .failed(provider: .doubao, message: message)
            lastErrorMessage = message
        }
    }

    public func removeLegacyLaunchAgentFromUserAction() async {
        guard !isRemovingLegacyLaunchAgent else {
            return
        }

        isRemovingLegacyLaunchAgent = true
        defer {
            isRemovingLegacyLaunchAgent = false
        }

        do {
            legacyInstall = try await legacyInstallProvider.removeKnownLaunchAgent()
            lastErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            legacyInstall = .failed(launchAgentURL: legacyInstall.launchAgentURL, message: message)
            lastErrorMessage = message
        }
    }

    public func fail(_ message: String) {
        lastErrorMessage = message
        status = .error
    }

    private func runtimeStatusAfterPermissionCheck() -> AppRuntimeStatus {
        return permissionSummary.allRequiredGranted ? .ready : .permissionNeeded
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

    private func restartHotkeyRuntime() {
        hotkeyProvider.stop()
        hotkeyRuntimeState = .inactive
        refreshHotkeyRuntime()
    }

    private var hotkeyPermissionsGranted: Bool {
        for kind in [PermissionKind.accessibility] {
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
        guard status == .ready, !isRecordingWorkflowTransitionActive else {
            return
        }

        isRecordingWorkflowTransitionActive = true
        lastErrorMessage = nil
        lastAudio = nil
        lastTranscript = nil
        lastInjection = nil
        status = .recording
        let transcriptionSessionID = UUID()
        activeTranscriptionSessionID = transcriptionSessionID

        do {
            try await recordingWorkflow.startRecording { [weak self] partial in
                self?.publishTranscriptPartial(partial, sessionID: transcriptionSessionID)
            }
            isRecordingWorkflowTransitionActive = false

            if pendingStopAfterRecordingStart {
                pendingStopAfterRecordingStart = false
                await stopRecording()
            }
        } catch {
            isRecordingWorkflowTransitionActive = false
            pendingStopAfterRecordingStart = false
            activeTranscriptionSessionID = nil
            failFromWorkflowError(error)
        }
    }

    private func stopRecording() async {
        guard status == .recording else {
            return
        }

        if isRecordingWorkflowTransitionActive {
            pendingStopAfterRecordingStart = true
            return
        }

        isRecordingWorkflowTransitionActive = true
        status = .transcribing
        let transcriptionSessionID = activeTranscriptionSessionID ?? UUID()
        activeTranscriptionSessionID = transcriptionSessionID

        do {
            let result = try await recordingWorkflow.stopRecording { [weak self] partial in
                self?.publishTranscriptPartial(partial, sessionID: transcriptionSessionID)
            }
            activeTranscriptionSessionID = nil
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
            isRecordingWorkflowTransitionActive = false
        } catch {
            isRecordingWorkflowTransitionActive = false
            activeTranscriptionSessionID = nil
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

    private func publishTranscriptPartial(_ partial: TranscriptPartialSnapshot, sessionID: UUID) {
        guard (status == .recording || status == .transcribing), activeTranscriptionSessionID == sessionID else {
            return
        }

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
