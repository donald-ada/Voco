import XCTest
@testable import VocoAppCore

final class AppCoordinatorTests: XCTestCase {
    @MainActor
    func testFinishingLaunchWithoutOnboardingShowsSetupState() {
        let coordinator = AppCoordinator(hasCompletedOnboarding: false)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.status, .needsOnboarding)
        XCTAssertEqual(coordinator.snapshot.title, "需要设置")
        XCTAssertEqual(coordinator.snapshot.systemImage, "exclamationmark.triangle")
        XCTAssertEqual(coordinator.snapshot.templateIconResourceName, "VocoMenuBarIconTemplate")
        XCTAssertTrue(coordinator.snapshot.canOpenSettings)
    }

    @MainActor
    func testFinishingLaunchWithOnboardingShowsReadyState() {
        let hotkeyProvider = FakeHotkeyProvider(startState: .listening)
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, hotkeyProvider: hotkeyProvider)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(coordinator.hotkeyRuntimeState, .listening)
        XCTAssertEqual(hotkeyProvider.startRequests.count, 1)
        XCTAssertEqual(coordinator.snapshot.title, "就绪")
        XCTAssertEqual(coordinator.snapshot.systemImage, "waveform")
        XCTAssertTrue(coordinator.snapshot.isRecordingActionEnabled)
    }

    @MainActor
    func testMenuRecordingToggleMovesThroughRecordingWorkflow() async {
        let coordinator = AppCoordinator(hasCompletedOnboarding: true)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .recording)
        XCTAssertEqual(coordinator.snapshot.title, "录音中")
        XCTAssertEqual(coordinator.snapshot.systemImage, "record.circle")

        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(coordinator.snapshot.title, "就绪")
        XCTAssertEqual(coordinator.snapshot.systemImage, "waveform")
    }

    @MainActor
    func testTranscriptionCompletionReturnsToReadyOrError() {
        let coordinator = AppCoordinator(hasCompletedOnboarding: true)
        coordinator.finishLaunching()
        coordinator.toggleRecordingFromMenu()
        coordinator.toggleRecordingFromMenu()

        coordinator.finishTranscribing(result: .success)

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertNil(coordinator.lastErrorMessage)

        coordinator.fail("provider offline")

        XCTAssertEqual(coordinator.status, .error)
        XCTAssertEqual(coordinator.lastErrorMessage, "provider offline")
        XCTAssertEqual(coordinator.snapshot.title, "错误")
        XCTAssertEqual(coordinator.snapshot.systemImage, "xmark.octagon")
    }

    @MainActor
    func testLaunchAtLoginToggleUsesProviderState() async {
        let launchProvider = FakeLaunchAtLoginProvider(initialState: .disabled)
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, launchAtLoginProvider: launchProvider)

        XCTAssertFalse(coordinator.launchAtLoginEnabled)
        XCTAssertEqual(coordinator.launchAtLoginState, .disabled)

        await coordinator.setLaunchAtLoginEnabled(true)

        XCTAssertTrue(coordinator.launchAtLoginEnabled)
        XCTAssertEqual(coordinator.launchAtLoginState, .enabled)
        XCTAssertEqual(launchProvider.requests, [true])

        await coordinator.setLaunchAtLoginEnabled(false)

        XCTAssertFalse(coordinator.launchAtLoginEnabled)
        XCTAssertEqual(coordinator.launchAtLoginState, .disabled)
        XCTAssertEqual(launchProvider.requests, [true, false])
    }

    @MainActor
    func testLaunchAtLoginFailureSurfacesErrorAndRestoresProviderState() async {
        let launchProvider = FakeLaunchAtLoginProvider(initialState: .disabled)
        launchProvider.error = LaunchAtLoginTestError.failed
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, launchAtLoginProvider: launchProvider)

        await coordinator.setLaunchAtLoginEnabled(true)

        XCTAssertFalse(coordinator.launchAtLoginEnabled)
        XCTAssertEqual(coordinator.launchAtLoginState, .failed("failed"))
        XCTAssertEqual(coordinator.lastErrorMessage, "登录时启动设置失败：failed")
    }

    @MainActor
    func testFinishingLaunchWithMissingPermissionShowsOnboarding() {
        let provider = FakePermissionProvider(
            current: [
                .microphone(.denied),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ]
        )
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, permissionProvider: provider)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.status, .needsOnboarding)
        XCTAssertEqual(coordinator.permissionSummary.missingRequiredPermissions, [.microphone])
        XCTAssertFalse(coordinator.snapshot.isRecordingActionEnabled)
    }

    @MainActor
    func testRefreshingPermissionsMovesReadyAppToPermissionNeeded() {
        let provider = FakePermissionProvider(
            current: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ]
        )
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, permissionProvider: provider)
        coordinator.finishLaunching()
        XCTAssertEqual(coordinator.status, .ready)

        provider.current = [
            .microphone(.granted),
            .accessibility(.denied),
            .inputMonitoring(.granted)
        ]
        coordinator.refreshPermissions()

        XCTAssertEqual(coordinator.status, .permissionNeeded)
        XCTAssertEqual(coordinator.snapshot.title, "需要权限")
        XCTAssertEqual(coordinator.permissionSummary.missingRequiredPermissions, [.accessibility])
    }

    @MainActor
    func testRequestingMicrophonePermissionRefreshesPermissionsAndRestoresReady() async {
        let provider = FakePermissionProvider(
            current: [
                .microphone(.notDetermined),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ]
        )
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, permissionProvider: provider)
        coordinator.finishLaunching()
        XCTAssertEqual(coordinator.status, .needsOnboarding)

        await coordinator.requestMicrophonePermission()

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(coordinator.permissions, provider.requested)
        XCTAssertTrue(coordinator.permissionSummary.allRequiredGranted)
    }

    @MainActor
    func testPreparingSettingsPresentationRefreshesPermissionSnapshot() {
        let provider = FakePermissionProvider(
            current: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ]
        )
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, permissionProvider: provider)
        coordinator.finishLaunching()

        provider.current = [
            .microphone(.granted),
            .accessibility(.denied),
            .inputMonitoring(.denied)
        ]

        coordinator.prepareForSettingsPresentation()

        XCTAssertEqual(coordinator.permissions, provider.current)
        XCTAssertEqual(coordinator.status, .permissionNeeded)
    }

    @MainActor
    func testRefreshingPermissionsAfterCompletedOnboardingRestoresReadyAndHotkey() {
        let permissionProvider = FakePermissionProvider(
            current: [
                .microphone(.granted),
                .accessibility(.denied),
                .inputMonitoring(.granted)
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ]
        )
        let hotkeyProvider = FakeHotkeyProvider(startState: .listening)
        let coordinator = AppCoordinator(
            hasCompletedOnboarding: true,
            permissionProvider: permissionProvider,
            hotkeyProvider: hotkeyProvider
        )
        coordinator.finishLaunching()
        XCTAssertEqual(coordinator.status, .needsOnboarding)
        XCTAssertEqual(coordinator.hotkeyRuntimeState, .permissionNeeded)

        permissionProvider.current = [
            .microphone(.granted),
            .accessibility(.granted),
            .inputMonitoring(.granted)
        ]
        coordinator.refreshPermissions()

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(coordinator.hotkeyRuntimeState, .listening)
        XCTAssertEqual(hotkeyProvider.startRequests.count, 1)
    }

    @MainActor
    func testHotkeyToggleMovesThroughRecordingWorkflow() async {
        let hotkeyProvider = FakeHotkeyProvider(startState: .listening)
        let recordingWorkflow = FakeRecordingWorkflow()
        let coordinator = AppCoordinator(
            hasCompletedOnboarding: true,
            recordingWorkflow: recordingWorkflow,
            hotkeyProvider: hotkeyProvider
        )
        coordinator.finishLaunching()

        hotkeyProvider.emit(.toggleRecording)
        await Task.yield()

        XCTAssertEqual(coordinator.status, .recording)
        XCTAssertEqual(recordingWorkflow.startCount, 1)

        hotkeyProvider.emit(.toggleRecording)
        await Task.yield()

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(recordingWorkflow.stopCount, 1)
    }

    @MainActor
    func testHotkeyPressAndHoldActionsStartAndStopRecording() async {
        let hotkeyProvider = FakeHotkeyProvider(startState: .listening)
        let recordingWorkflow = FakeRecordingWorkflow()
        let coordinator = AppCoordinator(
            hasCompletedOnboarding: true,
            recordingWorkflow: recordingWorkflow,
            hotkeyProvider: hotkeyProvider
        )
        coordinator.finishLaunching()

        hotkeyProvider.emit(.startRecording)
        await Task.yield()

        XCTAssertEqual(coordinator.status, .recording)
        XCTAssertEqual(recordingWorkflow.startCount, 1)

        hotkeyProvider.emit(.stopRecording)
        await Task.yield()

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(recordingWorkflow.stopCount, 1)
    }

    @MainActor
    func testRecordingWorkflowStartMovesToRecording() async {
        let recordingWorkflow = FakeRecordingWorkflow()
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .recording)
        XCTAssertEqual(recordingWorkflow.startCount, 1)
        XCTAssertEqual(recordingWorkflow.stopCount, 0)
    }

    @MainActor
    func testRecordingWorkflowStopStoresDiagnosticsAndReturnsReady() async {
        let result = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 1.1, sampleRate: 16_000, peakAmplitude: 0.61),
            transcript: TranscriptSnapshot(finalText: "hello", partials: ["he"], providerName: "Fake ASR", latencyMilliseconds: 33),
            injection: TextInjectionSnapshot(
                targetAppName: "TextEdit",
                strategy: .unicodeEvent,
                succeeded: true,
                detail: "Inserted through unicode events"
            )
        )
        let recordingWorkflow = FakeRecordingWorkflow(result: result)
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(recordingWorkflow.startCount, 1)
        XCTAssertEqual(recordingWorkflow.stopCount, 1)
        XCTAssertEqual(coordinator.lastTranscript, result.transcript)
        XCTAssertEqual(coordinator.lastInjection, result.injection)
    }

    @MainActor
    func testRecordingWorkflowStartFailureSurfacesError() async {
        let recordingWorkflow = FakeRecordingWorkflow(startError: RecordingWorkflowError("microphone unavailable"))
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .error)
        XCTAssertEqual(coordinator.lastErrorMessage, "microphone unavailable")
    }

    @MainActor
    func testRecordingWorkflowStopFailureSurfacesError() async {
        let recordingWorkflow = FakeRecordingWorkflow(stopError: RecordingWorkflowError("provider offline"))
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .error)
        XCTAssertEqual(coordinator.lastErrorMessage, "provider offline")
    }

    @MainActor
    func testMissingHotkeyPermissionsDoNotInstallHotkey() {
        let permissionProvider = FakePermissionProvider(
            current: [
                .microphone(.granted),
                .accessibility(.denied),
                .inputMonitoring(.granted)
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
                .inputMonitoring(.granted)
            ]
        )
        let hotkeyProvider = FakeHotkeyProvider(startState: .listening)
        let coordinator = AppCoordinator(
            hasCompletedOnboarding: true,
            permissionProvider: permissionProvider,
            hotkeyProvider: hotkeyProvider
        )

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.hotkeyRuntimeState, .permissionNeeded)
        XCTAssertTrue(hotkeyProvider.startRequests.isEmpty)
    }
}

private final class FakePermissionProvider: PermissionProviding {
    var current: [PermissionSnapshot]
    let requested: [PermissionSnapshot]

    init(current: [PermissionSnapshot], requested: [PermissionSnapshot]) {
        self.current = current
        self.requested = requested
    }

    func currentSnapshots() -> [PermissionSnapshot] {
        current
    }

    func requestMicrophoneAccess() async -> [PermissionSnapshot] {
        requested
    }
}

private final class FakeLaunchAtLoginProvider: LaunchAtLoginProviding {
    var state: LaunchAtLoginState
    var error: Error?
    private(set) var requests: [Bool] = []

    init(initialState: LaunchAtLoginState) {
        self.state = initialState
    }

    func currentState() -> LaunchAtLoginState {
        state
    }

    func setEnabled(_ enabled: Bool) async throws -> LaunchAtLoginState {
        requests.append(enabled)

        if let error {
            throw error
        }

        state = enabled ? .enabled : .disabled
        return state
    }
}

private enum LaunchAtLoginTestError: LocalizedError {
    case failed

    var errorDescription: String? {
        "failed"
    }
}

private final class FakeHotkeyProvider: HotkeyProviding {
    struct StartRequest: Equatable {
        let binding: HotkeyBinding
        let mode: HotkeyMode
    }

    let startState: HotkeyRuntimeState
    private(set) var startRequests: [StartRequest] = []
    private(set) var stopCount: Int = 0
    private var onAction: (@MainActor @Sendable (HotkeyAction) -> Void)?

    init(startState: HotkeyRuntimeState) {
        self.startState = startState
    }

    func start(
        binding: HotkeyBinding,
        mode: HotkeyMode,
        onAction: @escaping @MainActor @Sendable (HotkeyAction) -> Void
    ) -> HotkeyRuntimeState {
        startRequests.append(StartRequest(binding: binding, mode: mode))
        self.onAction = onAction
        return startState
    }

    func stop() {
        stopCount += 1
    }

    func emit(_ action: HotkeyAction) {
        onAction?(action)
    }
}

private final class FakeRecordingWorkflow: RecordingWorkflowing {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    let result: RecordingWorkflowResult
    let startError: Error?
    let stopError: Error?

    init(
        result: RecordingWorkflowResult = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 0.4, sampleRate: 16_000, peakAmplitude: 0.5),
            transcript: TranscriptSnapshot(finalText: "", partials: [], providerName: "Fake ASR", latencyMilliseconds: nil),
            injection: .skippedEmpty
        ),
        startError: Error? = nil,
        stopError: Error? = nil
    ) {
        self.result = result
        self.startError = startError
        self.stopError = stopError
    }

    func startRecording() async throws {
        startCount += 1

        if let startError {
            throw startError
        }
    }

    func stopRecording() async throws -> RecordingWorkflowResult {
        stopCount += 1

        if let stopError {
            throw stopError
        }

        return result
    }
}
