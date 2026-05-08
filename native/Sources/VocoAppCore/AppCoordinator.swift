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
    @Published public private(set) var currentTranscript: TranscriptSnapshot?
    @Published public private(set) var recentVoiceInputSessions: [VoiceInputSessionSnapshot]
    @Published public private(set) var lastInjection: TextInjectionSnapshot?
    @Published public private(set) var hotkeyBinding: HotkeyBinding
    @Published public private(set) var hotkeyMode: HotkeyMode
    @Published public private(set) var selectedAudioInputDevice: AudioInputDeviceSelection
    @Published public private(set) var silentLaunchEnabled: Bool
    @Published public private(set) var displayInDockEnabled: Bool
    @Published public private(set) var voiceInputSessionHistoryEnabled: Bool
    @Published public private(set) var voiceInputSessionRetentionPolicy: VoiceInputSessionRetentionPolicy
    @Published public private(set) var appLanguage: AppLanguage

    private let permissionProvider: any PermissionProviding
    private let launchAtLoginProvider: any LaunchAtLoginProviding
    private let recordingWorkflow: any RecordingWorkflowing
    private let hotkeyProvider: any HotkeyProviding
    private let transcriptionCredentialStore: any TranscriptionCredentialStoring
    private let installLocationProvider: any InstallLocationProviding
    private let legacyInstallProvider: any LegacyInstallProviding
    private let voiceInputPreferenceStore: any VoiceInputPreferenceStoring
    private let appPreferenceStore: any AppPreferenceStoring
    private let voiceInputSessionStore: any VoiceInputSessionStoring
    private var activeTranscriptionSessionID: UUID?
    private var isRecordingWorkflowTransitionActive: Bool
    private var pendingStopAfterRecordingStart: Bool
    private var isTranscriptionCredentialRefreshInFlight: Bool

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
        appPreferenceStore: any AppPreferenceStoring = NoOpAppPreferenceStore(),
        voiceInputSessionStore: any VoiceInputSessionStoring = InMemoryVoiceInputSessionStore(),
        hotkeyBinding: HotkeyBinding = .default,
        hotkeyMode: HotkeyMode = .toggle
    ) {
        let initialPermissions = permissionProvider.currentSnapshots()
        let initialLaunchAtLoginState = launchAtLoginEnabled ? LaunchAtLoginState.enabled : launchAtLoginProvider.currentState()
        let initialTranscriptionCredentials = transcriptionCredentialStore.currentSnapshot()
        let initialAppLanguage = appPreferenceStore.appLanguage
        let initialStrings = VocoStrings(language: initialAppLanguage)
        let initialInstallLocation = installLocationProvider.currentInstallLocation(strings: initialStrings)
        let initialVoiceInputSessionHistoryEnabled = appPreferenceStore.voiceInputSessionHistoryEnabled
        let initialVoiceInputSessionRetentionPolicy = appPreferenceStore.voiceInputSessionRetentionPolicy
        let initialLegacyInstall = legacyInstallProvider.currentSnapshot(strings: initialStrings)
        let initialSessionLoadResult: (sessions: [VoiceInputSessionSnapshot], errorMessage: String?)
        if initialVoiceInputSessionHistoryEnabled {
            do {
                initialSessionLoadResult = (
                    try voiceInputSessionStore.loadRecentSessions(limit: initialVoiceInputSessionRetentionPolicy.loadLimit),
                    nil
                )
            } catch {
                let message = Self.sessionStoreFailureMessage(kind: .load, error: error, strings: initialStrings)
                NSLog("Voco: \(message)")
                initialSessionLoadResult = ([], message)
            }
        } else {
            initialSessionLoadResult = (
                [],
                nil
            )
        }

        self.status = .launching
        self.lastErrorMessage = initialSessionLoadResult.errorMessage
        self.permissionProvider = permissionProvider
        self.launchAtLoginProvider = launchAtLoginProvider
        self.recordingWorkflow = recordingWorkflow
        self.hotkeyProvider = hotkeyProvider
        self.transcriptionCredentialStore = transcriptionCredentialStore
        self.installLocationProvider = installLocationProvider
        self.legacyInstallProvider = legacyInstallProvider
        self.voiceInputPreferenceStore = voiceInputPreferenceStore
        self.appPreferenceStore = appPreferenceStore
        self.voiceInputSessionStore = voiceInputSessionStore
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
        self.currentTranscript = nil
        self.recentVoiceInputSessions = initialSessionLoadResult.sessions
        self.lastInjection = nil
        self.hotkeyBinding = hotkeyBinding
        self.hotkeyMode = hotkeyMode
        self.selectedAudioInputDevice = recordingWorkflow.selectedAudioInputDevice
        self.silentLaunchEnabled = appPreferenceStore.silentLaunchEnabled
        self.displayInDockEnabled = appPreferenceStore.displayInDockEnabled
        self.voiceInputSessionHistoryEnabled = initialVoiceInputSessionHistoryEnabled
        self.voiceInputSessionRetentionPolicy = initialVoiceInputSessionRetentionPolicy
        self.appLanguage = initialAppLanguage
        self.activeTranscriptionSessionID = nil
        self.isRecordingWorkflowTransitionActive = false
        self.pendingStopAfterRecordingStart = false
        self.isTranscriptionCredentialRefreshInFlight = false
    }

    public var snapshot: MenuBarSnapshot {
        MenuBarSnapshot(
            status: status,
            title: strings.runtime.menuBarTitle(for: status),
            systemImage: status.systemImage,
            templateIconResourceName: "VocoMenuBarIconTemplate",
            isRecordingActionEnabled: status == .ready,
            canOpenSettings: true
        )
    }

    public var hudSnapshot: HUDSnapshot {
        HUDSnapshot(
            status: status,
            strings: strings,
            lastTranscript: lastTranscript,
            currentTranscript: currentTranscript,
            lastInjection: lastInjection,
            lastErrorMessage: lastErrorMessage
        )
    }

    public var settingsWorkbenchSnapshot: SettingsWorkbenchSnapshot {
        SettingsWorkbenchSnapshot.make(
            strings: strings,
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
            strings: strings,
            inputDevice: selectedAudioInputDevice
        )
    }

    public var availableAudioInputDevices: [AudioInputDeviceSelection] {
        let devices = recordingWorkflow.availableAudioInputDevices
        return devices.isEmpty ? [.systemDefault] : devices
    }

    public var injectionSettingsSnapshot: InjectionSettingsSnapshot {
        InjectionSettingsSnapshot(lastInjection: lastInjection, strings: strings)
    }

    public var hudSettingsSnapshot: HUDSettingsSnapshot {
        HUDSettingsSnapshot(strings: strings)
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

    public var strings: VocoStrings {
        VocoStrings(language: appLanguage)
    }

    public func finishLaunching() {
        lastErrorMessage = nil
        installLocation = installLocationProvider.currentInstallLocation(strings: strings)
        refreshLegacyInstall()
        permissions = permissionProvider.currentSnapshots()
        launchAtLoginState = launchAtLoginProvider.currentState()
        transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
        refreshTranscriptionCredentials()
        refreshTranscriptionCredentialsInBackground()
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
        refreshTranscriptionCredentialsInBackground()
        refreshPermissions()
    }

    public func refreshLegacyInstall() {
        legacyInstall = legacyInstallProvider.currentSnapshot(strings: strings)
    }

    public func refreshTranscriptionCredentials() {
        applyTranscriptionCredentialSnapshot(transcriptionCredentialStore.currentSnapshot())
    }

    public func refreshTranscriptionCredentialsInBackground() {
        guard !isTranscriptionCredentialRefreshInFlight else {
            return
        }

        isTranscriptionCredentialRefreshInFlight = true
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.refreshTranscriptionCredentialsFromStore()
            self.isTranscriptionCredentialRefreshInFlight = false
        }
    }

    public func refreshTranscriptionCredentialsFromStore() async {
        let snapshot = await transcriptionCredentialStore.loadCurrentSnapshot()
        applyTranscriptionCredentialSnapshot(snapshot)
        transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
    }

    private func applyTranscriptionCredentialSnapshot(_ snapshot: TranscriptionCredentialSnapshot) {
        transcriptionCredentials = snapshot
        if let message = snapshot.lastErrorMessage {
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
        installLocation = installLocationProvider.currentInstallLocation(strings: strings)
        if enabled, !installLocation.allowsLaunchAtLogin {
            let message = installLocation.warningDetail ?? strings.settings.launchAtLoginUnsupportedDetail
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
            lastErrorMessage = strings.settings.launchAtLoginSetupFailedMessage(message)
        }
    }

    public func setSilentLaunchEnabled(_ enabled: Bool) {
        silentLaunchEnabled = enabled
        appPreferenceStore.saveSilentLaunchEnabled(enabled)
    }

    public func setDisplayInDockEnabled(_ enabled: Bool) {
        displayInDockEnabled = enabled
        appPreferenceStore.saveDisplayInDockEnabled(enabled)
    }

    public func setVoiceInputSessionHistoryEnabled(_ enabled: Bool) {
        guard voiceInputSessionHistoryEnabled != enabled else {
            appPreferenceStore.saveVoiceInputSessionHistoryEnabled(enabled)
            return
        }

        voiceInputSessionHistoryEnabled = enabled
        appPreferenceStore.saveVoiceInputSessionHistoryEnabled(enabled)

        if enabled {
            lastErrorMessage = reloadRecentVoiceInputSessions()
        }
    }

    public func setVoiceInputSessionRetentionPolicy(_ policy: VoiceInputSessionRetentionPolicy) {
        guard voiceInputSessionRetentionPolicy != policy else {
            appPreferenceStore.saveVoiceInputSessionRetentionPolicy(policy)
            return
        }

        voiceInputSessionRetentionPolicy = policy
        appPreferenceStore.saveVoiceInputSessionRetentionPolicy(policy)
        lastErrorMessage = applyVoiceInputSessionRetentionPolicy()
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

    public func setAppLanguage(_ language: AppLanguage) {
        guard appLanguage != language else {
            appPreferenceStore.saveAppLanguage(language)
            return
        }

        appLanguage = language
        appPreferenceStore.saveAppLanguage(language)
        refreshLocalizedRuntimeSnapshots()
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
        await saveTranscriptionCredential(.volcengineAPIKey(apiKey))
    }

    public func saveVolcengineAppIDAccessToken(appID: String, accessToken: String) async {
        await saveTranscriptionCredential(
            .volcengineAppIDAccessToken(appID: appID, accessToken: accessToken)
        )
    }

    public func saveTranscriptionCredential(_ credential: TranscriptionCredential) async {
        do {
            transcriptionCredentials = try await transcriptionCredentialStore.saveCredential(credential, for: .volcengine)
            transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
            lastErrorMessage = nil
        } catch {
            let message = localizedErrorDescription(error)
            transcriptionCredentials = .failed(provider: .volcengine, message: message, strings: strings)
            lastErrorMessage = message
        }
    }

    public func clearTranscriptionCredentials() async {
        do {
            transcriptionCredentials = try await transcriptionCredentialStore.deleteCredentials(for: .volcengine)
            transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
            lastErrorMessage = nil
        } catch {
            let message = localizedErrorDescription(error)
            transcriptionCredentials = .failed(provider: .volcengine, message: message, strings: strings)
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
            legacyInstall = try await legacyInstallProvider.removeKnownLaunchAgent(strings: strings)
            lastErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            legacyInstall = .failed(launchAgentURL: legacyInstall.launchAgentURL, message: message, strings: strings)
            lastErrorMessage = message
        }
    }

    public func fail(_ message: String) {
        lastErrorMessage = message
        status = .error
    }

    private func refreshLocalizedRuntimeSnapshots() {
        installLocation = installLocationProvider.currentInstallLocation(strings: strings)
        legacyInstall = legacyInstallProvider.currentSnapshot(strings: strings)
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
        currentTranscript = nil
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
            currentTranscript = result.transcript
            lastInjection = result.injection
            let sessionPersistenceErrorMessage = appendRecentVoiceInputSession(from: result)

            if result.injection.strategy != .skippedEmpty {
                status = .injecting
            }

            if result.injection.succeeded {
                lastErrorMessage = sessionPersistenceErrorMessage
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
        lastErrorMessage = localizedErrorDescription(error)
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

        let baseTranscript = currentTranscript ?? TranscriptSnapshot(
            finalText: "",
            partials: [],
            providerName: partial.providerName,
            latencyMilliseconds: nil
        )
        let liveTranscript = baseTranscript.appendingPartial(partial)
        currentTranscript = liveTranscript
        lastTranscript = liveTranscript
    }

    private func appendRecentVoiceInputSession(from result: RecordingWorkflowResult) -> String? {
        let session = VoiceInputSessionSnapshot(result: result)
        guard !session.transcriptText.isEmpty else {
            return nil
        }

        recentVoiceInputSessions.removeAll { $0.id == session.id }
        recentVoiceInputSessions.insert(session, at: 0)
        if let limit = voiceInputSessionRetentionPolicy.limit {
            recentVoiceInputSessions = Array(recentVoiceInputSessions.prefix(limit))
        }

        guard voiceInputSessionHistoryEnabled else {
            return nil
        }

        do {
            try voiceInputSessionStore.save(session)
            try voiceInputSessionStore.trimRecentSessions(limit: voiceInputSessionRetentionPolicy.limit)
            recentVoiceInputSessions = try voiceInputSessionStore.loadRecentSessions(
                limit: voiceInputSessionRetentionPolicy.loadLimit
            )
            return nil
        } catch {
            let message = sessionStoreFailureMessage(kind: .save, error: error)
            NSLog("Voco: \(message)")
            return message
        }
    }

    private func applyVoiceInputSessionRetentionPolicy() -> String? {
        guard voiceInputSessionHistoryEnabled else {
            if let limit = voiceInputSessionRetentionPolicy.limit {
                recentVoiceInputSessions = Array(recentVoiceInputSessions.prefix(limit))
            }
            return nil
        }

        do {
            try voiceInputSessionStore.trimRecentSessions(limit: voiceInputSessionRetentionPolicy.limit)
            recentVoiceInputSessions = try voiceInputSessionStore.loadRecentSessions(
                limit: voiceInputSessionRetentionPolicy.loadLimit
            )
            return nil
        } catch {
            let message = sessionStoreFailureMessage(kind: .updateRetention, error: error)
            NSLog("Voco: \(message)")
            return message
        }
    }

    private func reloadRecentVoiceInputSessions() -> String? {
        do {
            recentVoiceInputSessions = try voiceInputSessionStore.loadRecentSessions(
                limit: voiceInputSessionRetentionPolicy.loadLimit
            )
            return nil
        } catch {
            let message = sessionStoreFailureMessage(kind: .load, error: error)
            NSLog("Voco: \(message)")
            return message
        }
    }

    private func localizedErrorDescription(_ error: Error) -> String {
        switch error {
        case let providerError as TranscriptionProviderError:
            providerError.localizedDescription(strings: strings)
        case let injectionError as TextInjectionError:
            injectionError.localizedDescription(strings: strings)
        case let credentialError as TranscriptionCredentialError:
            credentialError.localizedDescription(strings: strings)
        case let sessionStoreError as VoiceInputSessionStoreError:
            sessionStoreError.localizedDescription(strings: strings)
        default:
            error.localizedDescription
        }
    }

    private func sessionStoreFailureMessage(kind: VoiceInputSessionStoreFailureKind, error: Error) -> String {
        Self.sessionStoreFailureMessage(kind: kind, error: error, strings: strings)
    }

    private static func sessionStoreFailureMessage(
        kind: VoiceInputSessionStoreFailureKind,
        error: Error,
        strings: VocoStrings
    ) -> String {
        let detail: String
        switch error {
        case let VoiceInputSessionStoreError.loadFailed(message):
            detail = message
        case let VoiceInputSessionStoreError.saveFailed(message):
            detail = message
        default:
            detail = error.localizedDescription
        }

        switch kind {
        case .load:
            return strings.sessions.loadFailureMessage(detail: detail)
        case .save:
            return strings.sessions.saveFailureMessage(detail: detail)
        case .updateRetention:
            return strings.sessions.updateRetentionFailureMessage(detail: detail)
        }
    }

    private enum VoiceInputSessionStoreFailureKind {
        case load
        case save
        case updateRetention
    }
}

private extension AppRuntimeStatus {
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
