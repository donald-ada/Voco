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
    @Published public private(set) var onboarding: OnboardingSnapshot
    @Published public private(set) var installLocation: InstallLocationSnapshot
    @Published public private(set) var lastAudio: CapturedAudioSnapshot?
    @Published public private(set) var lastTranscript: TranscriptSnapshot?
    @Published public private(set) var lastInjection: TextInjectionSnapshot?

    private var hasCompletedOnboarding: Bool
    private let setHasCompletedOnboarding: @MainActor @Sendable (Bool) -> Void
    private let permissionProvider: any PermissionProviding
    private let launchAtLoginProvider: any LaunchAtLoginProviding
    private let recordingWorkflow: any RecordingWorkflowing
    private let hotkeyProvider: any HotkeyProviding
    private let transcriptionCredentialStore: any TranscriptionCredentialStoring
    private let installLocationProvider: any InstallLocationProviding
    public let hotkeyBinding: HotkeyBinding
    public let hotkeyMode: HotkeyMode
    private var hasSkippedLaunchAtLoginForOnboarding: Bool
    private var hasVerifiedHotkeyForOnboarding: Bool
    private var activeTranscriptionSessionID: UUID?

    public init(
        hasCompletedOnboarding: Bool = false,
        setHasCompletedOnboarding: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
        launchAtLoginEnabled: Bool = false,
        permissionProvider: any PermissionProviding = StaticPermissionProvider.allGranted,
        launchAtLoginProvider: any LaunchAtLoginProviding = StaticLaunchAtLoginProvider(),
        transcriptionCredentialStore: any TranscriptionCredentialStoring = InMemoryTranscriptionCredentialStore(),
        recordingWorkflow: any RecordingWorkflowing = StaticRecordingWorkflow(),
        hotkeyProvider: any HotkeyProviding = StaticHotkeyProvider(),
        installLocationProvider: any InstallLocationProviding = StaticInstallLocationProvider(),
        hotkeyBinding: HotkeyBinding = .default,
        hotkeyMode: HotkeyMode = .toggle
    ) {
        let initialPermissions = permissionProvider.currentSnapshots()
        let initialLaunchAtLoginState = launchAtLoginEnabled ? LaunchAtLoginState.enabled : launchAtLoginProvider.currentState()
        let initialTranscriptionCredentials = transcriptionCredentialStore.currentSnapshot()
        let initialInstallLocation = installLocationProvider.currentInstallLocation()

        self.status = .launching
        self.lastErrorMessage = nil
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.setHasCompletedOnboarding = setHasCompletedOnboarding
        self.permissionProvider = permissionProvider
        self.launchAtLoginProvider = launchAtLoginProvider
        self.recordingWorkflow = recordingWorkflow
        self.hotkeyProvider = hotkeyProvider
        self.transcriptionCredentialStore = transcriptionCredentialStore
        self.installLocationProvider = installLocationProvider
        self.hotkeyBinding = hotkeyBinding
        self.hotkeyMode = hotkeyMode
        self.permissions = initialPermissions
        self.launchAtLoginState = initialLaunchAtLoginState
        self.hotkeyRuntimeState = .inactive
        self.transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
        self.transcriptionCredentials = initialTranscriptionCredentials
        self.installLocation = initialInstallLocation
        self.onboarding = OnboardingSnapshot.make(
            permissions: initialPermissions,
            transcriptionCredentials: initialTranscriptionCredentials,
            launchAtLoginState: initialLaunchAtLoginState,
            hasSkippedLaunchAtLogin: false,
            hotkeyRuntimeState: .inactive,
            hotkeyBinding: hotkeyBinding,
            hotkeyMode: hotkeyMode,
            hasVerifiedHotkey: false
        )
        self.lastAudio = nil
        self.lastTranscript = nil
        self.lastInjection = nil
        self.hasSkippedLaunchAtLoginForOnboarding = false
        self.hasVerifiedHotkeyForOnboarding = false
        self.activeTranscriptionSessionID = nil
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

    public var diagnosticsSnapshot: DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            appStatusTitle: snapshot.title,
            permissions: permissions,
            audio: lastAudio,
            hotkeyState: hotkeyRuntimeState,
            hotkeyBinding: hotkeyBinding,
            hotkeyMode: hotkeyMode,
            asrStatus: transcriptionProviderStatus,
            credentials: transcriptionCredentials,
            installLocation: installLocation,
            transcript: lastTranscript,
            injection: lastInjection,
            lastErrorMessage: lastErrorMessage
        )
    }

    public func diagnosticBundle(generatedAt: Date = Date()) -> DiagnosticBundle {
        let menuSnapshot = snapshot
        let diagnosticsSnapshot = DiagnosticsSnapshot(
            appStatusTitle: menuSnapshot.title,
            permissions: permissions,
            audio: lastAudio,
            hotkeyState: hotkeyRuntimeState,
            hotkeyBinding: hotkeyBinding,
            hotkeyMode: hotkeyMode,
            asrStatus: transcriptionProviderStatus,
            credentials: transcriptionCredentials,
            installLocation: installLocation,
            transcript: lastTranscript,
            injection: lastInjection,
            lastErrorMessage: lastErrorMessage,
            generatedAt: generatedAt
        )

        return DiagnosticBundle(
            snapshot: diagnosticsSnapshot,
            redaction: DiagnosticRedactionContext(
                secrets: diagnosticSecrets,
                transcriptBodies: diagnosticTranscriptBodies
            )
        )
    }

    @discardableResult
    public func exportDiagnosticBundle(to url: URL) throws -> URL {
        try DiagnosticBundleExporter.write(bundle: diagnosticBundle(), to: url)
    }

    @discardableResult
    public func exportDiagnosticBundleToTemporaryDirectory(
        generatedAt: Date = Date(),
        id: UUID = UUID(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let exportURL = fileManager.temporaryDirectory
            .appendingPathComponent("voco-diagnostics-\(Int(generatedAt.timeIntervalSince1970))-\(id.uuidString).json")

        do {
            let writtenURL = try DiagnosticBundleExporter.write(
                bundle: diagnosticBundle(generatedAt: generatedAt),
                to: exportURL
            )
            lastErrorMessage = nil
            return writtenURL
        } catch {
            fail(error.localizedDescription)
            throw error
        }
    }

    public var audioSettingsSnapshot: AudioSettingsSnapshot {
        AudioSettingsSnapshot(lastAudio: lastAudio)
    }

    public var injectionSettingsSnapshot: InjectionSettingsSnapshot {
        InjectionSettingsSnapshot(lastInjection: lastInjection)
    }

    public var hudSettingsSnapshot: HUDSettingsSnapshot {
        HUDSettingsSnapshot()
    }

    public var privacySettingsSnapshot: PrivacySettingsSnapshot {
        PrivacySettingsSnapshot(transcriptionCredentials: transcriptionCredentials)
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

    private var diagnosticSecrets: [String] {
        [transcriptionCredentials.maskedAPIKey].compactMap { $0 }
    }

    private var diagnosticTranscriptBodies: [String] {
        guard let lastTranscript else {
            return []
        }

        return [lastTranscript.finalText] + lastTranscript.partials
    }

    public func finishLaunching() {
        lastErrorMessage = nil
        installLocation = installLocationProvider.currentInstallLocation()
        permissions = permissionProvider.currentSnapshots()
        launchAtLoginState = launchAtLoginProvider.currentState()
        transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
        refreshTranscriptionCredentials()
        status = launchStatusAfterSetupCheck()
        refreshHotkeyRuntime()
        refreshOnboardingState()
    }

    public func refreshPermissions() {
        let shouldUpdateRuntimeStatus =
            status == .ready ||
            status == .permissionNeeded ||
            (status == .needsOnboarding && hasCompletedOnboarding)
        permissions = permissionProvider.currentSnapshots()

        if shouldUpdateRuntimeStatus {
            status = permissionSummary.allRequiredGranted ? .ready : .permissionNeeded
        }

        refreshHotkeyRuntime()
        refreshOnboardingState()
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
        refreshOnboardingState()
    }

    public func requestMicrophonePermission() async {
        let shouldUpdateRuntimeStatus = status == .ready || status == .permissionNeeded
        permissions = await permissionProvider.requestMicrophoneAccess()

        if shouldUpdateRuntimeStatus {
            status = permissionSummary.allRequiredGranted ? .ready : .permissionNeeded
        } else {
            status = launchStatusAfterSetupCheck()
        }
        refreshHotkeyRuntime()
        refreshOnboardingState()
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
            refreshOnboardingState()
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
        refreshOnboardingState()
    }

    public func saveTranscriptionAPIKey(_ apiKey: String) async {
        do {
            transcriptionCredentials = try await transcriptionCredentialStore.saveAPIKey(apiKey, for: .doubao)
            transcriptionProviderStatus = recordingWorkflow.transcriptionStatus
            lastErrorMessage = nil
        } catch {
            let message = error.localizedDescription
            transcriptionCredentials = .failed(provider: .doubao, message: message)
            lastErrorMessage = message
        }
        refreshOnboardingState()
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
        refreshOnboardingState()
    }

    public func refreshOnboardingState() {
        onboarding = OnboardingSnapshot.make(
            permissions: permissions,
            transcriptionCredentials: transcriptionCredentials,
            launchAtLoginState: launchAtLoginState,
            hasSkippedLaunchAtLogin: hasSkippedLaunchAtLoginForOnboarding,
            hotkeyRuntimeState: hotkeyRuntimeState,
            hotkeyBinding: hotkeyBinding,
            hotkeyMode: hotkeyMode,
            hasVerifiedHotkey: hasVerifiedHotkeyForOnboarding
        )
    }

    public func markLaunchAtLoginSkippedForOnboarding() {
        hasSkippedLaunchAtLoginForOnboarding = true
        refreshOnboardingState()
    }

    public func markHotkeyVerifiedForOnboarding() {
        guard hotkeyRuntimeState == .listening else {
            refreshOnboardingState()
            return
        }

        hasVerifiedHotkeyForOnboarding = true
        refreshOnboardingState()
    }

    @discardableResult
    public func completeOnboardingIfReady() -> Bool {
        refreshOnboardingState()
        guard onboarding.isComplete else {
            lastErrorMessage = "首次设置尚未完成。"
            return false
        }

        hasCompletedOnboarding = true
        setHasCompletedOnboarding(true)
        lastErrorMessage = nil
        status = permissionSummary.allRequiredGranted ? .ready : .permissionNeeded
        refreshHotkeyRuntime()
        refreshOnboardingState()
        return true
    }

    public func fail(_ message: String) {
        lastErrorMessage = message
        status = .error
    }

    private func launchStatusAfterSetupCheck() -> AppRuntimeStatus {
        guard hasCompletedOnboarding else {
            return .needsOnboarding
        }

        return permissionSummary.allRequiredGranted ? .ready : .permissionNeeded
    }

    private func refreshHotkeyRuntime() {
        guard hotkeyPermissionsGranted else {
            hotkeyProvider.stop()
            hotkeyRuntimeState = .permissionNeeded
            return
        }

        guard status == .ready || status == .needsOnboarding || status == .recording || status == .transcribing else {
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
        let transcriptionSessionID = UUID()
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
        } catch {
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
        guard status == .transcribing, activeTranscriptionSessionID == sessionID else {
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
