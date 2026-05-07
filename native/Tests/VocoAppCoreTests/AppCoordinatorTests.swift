import XCTest
@testable import VocoAppCore

final class AppCoordinatorTests: XCTestCase {
    @MainActor
    func testFinishingLaunchDoesNotGateReadyStateOnSetupCompletion() {
        let coordinator = AppCoordinator()

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(coordinator.snapshot.title, "就绪")
        XCTAssertEqual(coordinator.snapshot.systemImage, "waveform")
        XCTAssertEqual(coordinator.snapshot.templateIconResourceName, "VocoMenuBarIconTemplate")
        XCTAssertTrue(coordinator.snapshot.canOpenSettings)
    }

    @MainActor
    func testFinishingLaunchShowsReadyState() {
        let hotkeyProvider = FakeHotkeyProvider(startState: .listening)
        let coordinator = AppCoordinator(hotkeyProvider: hotkeyProvider)

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
        let coordinator = AppCoordinator()
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
        let coordinator = AppCoordinator()
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
        let coordinator = AppCoordinator(launchAtLoginProvider: launchProvider)

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
        let coordinator = AppCoordinator(launchAtLoginProvider: launchProvider)

        await coordinator.setLaunchAtLoginEnabled(true)

        XCTAssertFalse(coordinator.launchAtLoginEnabled)
        XCTAssertEqual(coordinator.launchAtLoginState, .failed("failed"))
        XCTAssertEqual(coordinator.lastErrorMessage, "登录时启动设置失败：failed")
    }

    @MainActor
    func testFinishingLaunchWithMissingPermissionUsesPermissionRecovery() {
        let provider = FakePermissionProvider(
            current: [
                .microphone(.denied),
                .accessibility(.granted),
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
            ]
        )
        let coordinator = AppCoordinator(permissionProvider: provider)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.status, .permissionNeeded)
        XCTAssertEqual(coordinator.permissionSummary.missingRequiredPermissions, [.microphone])
        XCTAssertFalse(coordinator.snapshot.isRecordingActionEnabled)
    }

    @MainActor
    func testRefreshingPermissionsMovesReadyAppToPermissionNeeded() {
        let provider = FakePermissionProvider(
            current: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
            ]
        )
        let coordinator = AppCoordinator(permissionProvider: provider)
        coordinator.finishLaunching()
        XCTAssertEqual(coordinator.status, .ready)

        provider.current = [
            .microphone(.granted),
            .accessibility(.denied),
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
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
            ]
        )
        let coordinator = AppCoordinator(permissionProvider: provider)
        coordinator.finishLaunching()
        XCTAssertEqual(coordinator.status, .permissionNeeded)

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
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
            ]
        )
        let coordinator = AppCoordinator(permissionProvider: provider)
        coordinator.finishLaunching()

        provider.current = [
            .microphone(.granted),
            .accessibility(.denied),
        ]

        coordinator.prepareForSettingsPresentation()

        XCTAssertEqual(coordinator.permissions, provider.current)
        XCTAssertEqual(coordinator.status, .permissionNeeded)
    }

    @MainActor
    func testRefreshingPermissionsRestoresReadyAndHotkey() {
        let permissionProvider = FakePermissionProvider(
            current: [
                .microphone(.granted),
                .accessibility(.denied),
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
            ]
        )
        let hotkeyProvider = FakeHotkeyProvider(startState: .listening)
        let coordinator = AppCoordinator(
            permissionProvider: permissionProvider,
            hotkeyProvider: hotkeyProvider
        )
        coordinator.finishLaunching()
        XCTAssertEqual(coordinator.status, .permissionNeeded)
        XCTAssertEqual(coordinator.hotkeyRuntimeState, .permissionNeeded)

        permissionProvider.current = [
            .microphone(.granted),
            .accessibility(.granted),
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
    func testRapidToggleDuringRecordingStartQueuesStopAfterStartCompletes() async {
        let recordingWorkflow = FakeRecordingWorkflow(pauseAfterStart: true)
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        let startTask = Task {
            await coordinator.toggleRecordingFromUserAction()
        }
        await recordingWorkflow.waitUntilStartPaused()

        XCTAssertEqual(coordinator.status, .recording)
        XCTAssertEqual(recordingWorkflow.startCount, 1)

        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(recordingWorkflow.stopCount, 0)

        recordingWorkflow.resumeStart()
        await startTask.value

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(recordingWorkflow.startCount, 1)
        XCTAssertEqual(recordingWorkflow.stopCount, 1)
    }

    @MainActor
    func testHotkeyPressAndHoldActionsStartAndStopRecording() async {
        let hotkeyProvider = FakeHotkeyProvider(startState: .listening)
        let recordingWorkflow = FakeRecordingWorkflow()
        let coordinator = AppCoordinator(
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
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
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
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(recordingWorkflow.startCount, 1)
        XCTAssertEqual(recordingWorkflow.stopCount, 1)
        XCTAssertEqual(coordinator.lastAudio, result.audio)
        XCTAssertEqual(coordinator.lastTranscript, result.transcript)
        XCTAssertEqual(coordinator.lastInjection, result.injection)
    }

    @MainActor
    func testCoordinatorPublishesPartialTranscriptToHUDWhileTranscribing() async {
        let partial = TranscriptPartialSnapshot(
            text: "live words",
            stablePrefixLength: 0,
            providerName: "Fake ASR"
        )
        let recordingWorkflow = FakeRecordingWorkflow(
            partialsToEmit: [partial],
            pauseAfterPartials: true
        )
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        let stopTask = Task {
            await coordinator.toggleRecordingFromUserAction()
        }
        await recordingWorkflow.waitUntilPartialsEmitted()

        XCTAssertEqual(coordinator.status, .transcribing)
        XCTAssertEqual(coordinator.lastTranscript?.partials, ["live words"])
        XCTAssertEqual(coordinator.hudSnapshot.transcriptPreview, "live words")

        recordingWorkflow.resumeStop()
        await stopTask.value
    }

    @MainActor
    func testCoordinatorPublishesPartialTranscriptToHUDWhileRecording() async {
        let partial = TranscriptPartialSnapshot(
            text: "recording words",
            stablePrefixLength: 0,
            providerName: "Fake ASR"
        )
        let recordingWorkflow = FakeRecordingWorkflow(partialsToEmitOnStart: [partial])
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .recording)
        XCTAssertEqual(coordinator.lastTranscript?.partials, ["recording words"])
        XCTAssertEqual(coordinator.hudSnapshot.transcriptPreview, "recording words")
    }

    @MainActor
    func testLatePartialAfterStopCompletionDoesNotChangeTranscriptOrHUD() async {
        let result = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 1.1, sampleRate: 16_000, peakAmplitude: 0.61),
            transcript: TranscriptSnapshot(
                finalText: "",
                partials: ["final partial"],
                providerName: "Fake ASR",
                latencyMilliseconds: 33
            ),
            injection: TextInjectionSnapshot(
                targetAppName: "TextEdit",
                strategy: .unicodeEvent,
                succeeded: true,
                detail: "Inserted through unicode events"
            )
        )
        let recordingWorkflow = FakeRecordingWorkflow(
            result: result,
            partialsToEmit: [
                TranscriptPartialSnapshot(
                    text: "live partial",
                    stablePrefixLength: 0,
                    providerName: "Fake ASR"
                )
            ]
        )
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()
        let transcriptAfterCompletion = coordinator.lastTranscript
        let hudAfterCompletion = coordinator.hudSnapshot

        recordingWorkflow.emitStoredPartial(
            TranscriptPartialSnapshot(
                text: "late partial",
                stablePrefixLength: 0,
                providerName: "Fake ASR"
            )
        )

        XCTAssertEqual(coordinator.lastTranscript, transcriptAfterCompletion)
        XCTAssertEqual(coordinator.hudSnapshot, hudAfterCompletion)
    }

    @MainActor
    func testRecordingWorkflowStartFailureSurfacesError() async {
        let recordingWorkflow = FakeRecordingWorkflow(startError: RecordingWorkflowError("microphone unavailable"))
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .error)
        XCTAssertEqual(coordinator.lastErrorMessage, "microphone unavailable")
    }

    @MainActor
    func testRecordingWorkflowStopFailureSurfacesError() async {
        let recordingWorkflow = FakeRecordingWorkflow(stopError: RecordingWorkflowError("provider offline"))
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .error)
        XCTAssertEqual(coordinator.lastErrorMessage, "provider offline")
        XCTAssertEqual(coordinator.settingsWorkbenchSnapshot.recentChain[2].detail, "尚无近期转写")
        XCTAssertEqual(coordinator.settingsWorkbenchSnapshot.recentChain[2].status, .neutral)
    }

    @MainActor
    func testCoordinatorPublishesTranscriptionProviderStatus() {
        let recordingWorkflow = FakeRecordingWorkflow(transcriptionStatus: .authenticationRequired(providerName: "Doubao"))
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.transcriptionProviderStatus, .authenticationRequired(providerName: "Doubao"))
    }

    @MainActor
    func testCoordinatorPublishesTranscriptionCredentialSnapshot() {
        let credentialStore = InMemoryTranscriptionCredentialStore(apiKey: "sk-test-abcdef")
        let coordinator = AppCoordinator(transcriptionCredentialStore: credentialStore)

        coordinator.finishLaunching()

        XCTAssertTrue(coordinator.transcriptionCredentials.hasAPIKey)
        XCTAssertEqual(coordinator.transcriptionCredentials.maskedAPIKey, "sk-t...cdef")
    }

    @MainActor
    func testCoordinatorSavesAndClearsTranscriptionCredentials() async throws {
        let credentialStore = InMemoryTranscriptionCredentialStore()
        let coordinator = AppCoordinator(transcriptionCredentialStore: credentialStore)

        await coordinator.saveTranscriptionAPIKey("sk-test-abcdef")

        XCTAssertTrue(coordinator.transcriptionCredentials.hasAPIKey)
        XCTAssertEqual(coordinator.transcriptionCredentials.maskedAPIKey, "sk-t...cdef")
        XCTAssertNil(coordinator.lastErrorMessage)
        let savedAPIKey = try await credentialStore.apiKey(for: .doubao)
        XCTAssertEqual(savedAPIKey, "sk-test-abcdef")

        await coordinator.clearTranscriptionCredentials()

        XCTAssertFalse(coordinator.transcriptionCredentials.hasAPIKey)
        XCTAssertNil(coordinator.lastErrorMessage)
        let clearedAPIKey = try await credentialStore.apiKey(for: .doubao)
        XCTAssertNil(clearedAPIKey)
    }

    @MainActor
    func testCoordinatorSavesLegacyDoubaoCredentialMode() async throws {
        let credentialStore = InMemoryTranscriptionCredentialStore()
        let coordinator = AppCoordinator(transcriptionCredentialStore: credentialStore)

        await coordinator.saveDoubaoAppIDAccessToken(
            appID: "3145608744",
            accessToken: "legacy-token"
        )

        XCTAssertTrue(coordinator.transcriptionCredentials.hasCredential)
        XCTAssertFalse(coordinator.transcriptionCredentials.hasAPIKey)
        XCTAssertEqual(coordinator.transcriptionCredentials.mode, .appIDAccessToken)
        let credential = try await credentialStore.credential(for: .doubao)
        XCTAssertEqual(credential?.appID, "3145608744")
        XCTAssertEqual(credential?.accessToken, "legacy-token")
    }

    @MainActor
    func testSavingTranscriptionCredentialRefreshesProviderStatus() async {
        let credentialStore = InMemoryTranscriptionCredentialStore()
        let recordingWorkflow = FakeRecordingWorkflow(
            transcriptionStatus: .authenticationRequired(providerName: "Doubao")
        )
        let coordinator = AppCoordinator(
            transcriptionCredentialStore: credentialStore,
            recordingWorkflow: recordingWorkflow
        )
        coordinator.finishLaunching()
        XCTAssertEqual(coordinator.transcriptionProviderStatus, .authenticationRequired(providerName: "Doubao"))

        recordingWorkflow.transcriptionStatus = .ready(providerName: "Doubao")
        await coordinator.saveTranscriptionAPIKey("sk-test-abcdef")

        XCTAssertEqual(coordinator.transcriptionProviderStatus, .ready(providerName: "Doubao"))
    }

    @MainActor
    func testClearingTranscriptionCredentialRefreshesProviderStatus() async {
        let credentialStore = InMemoryTranscriptionCredentialStore(apiKey: "sk-test-abcdef")
        let recordingWorkflow = FakeRecordingWorkflow(
            transcriptionStatus: .ready(providerName: "Doubao")
        )
        let coordinator = AppCoordinator(
            transcriptionCredentialStore: credentialStore,
            recordingWorkflow: recordingWorkflow
        )
        coordinator.finishLaunching()
        XCTAssertEqual(coordinator.transcriptionProviderStatus, .ready(providerName: "Doubao"))

        recordingWorkflow.transcriptionStatus = .authenticationRequired(providerName: "Doubao")
        await coordinator.clearTranscriptionCredentials()

        XCTAssertEqual(coordinator.transcriptionProviderStatus, .authenticationRequired(providerName: "Doubao"))
    }

    @MainActor
    func testCredentialStoreFailureSurfacesError() async {
        let credentialStore = FakeTranscriptionCredentialStore(
            saveError: TranscriptionCredentialError.storeFailed(message: "Keychain denied")
        )
        let coordinator = AppCoordinator(transcriptionCredentialStore: credentialStore)

        await coordinator.saveTranscriptionAPIKey("sk-test-abcdef")

        XCTAssertEqual(coordinator.transcriptionCredentials.statusTitle, "Doubao 凭证读取失败")
        XCTAssertEqual(coordinator.transcriptionCredentials.lastErrorMessage, "保存 ASR 凭证失败：Keychain denied")
        XCTAssertEqual(coordinator.lastErrorMessage, "保存 ASR 凭证失败：Keychain denied")
    }

    @MainActor
    func testCoordinatorPublishesRecordingHUDSnapshot() async {
        let coordinator = AppCoordinator()
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.hudSnapshot.phase, .recording)
        XCTAssertTrue(coordinator.hudSnapshot.isVisible)
    }

    @MainActor
    func testCoordinatorPublishesFailureHUDSnapshot() async {
        let recordingWorkflow = FakeRecordingWorkflow(stopError: TranscriptionProviderError.notConfigured)
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.hudSnapshot.phase, .error)
        XCTAssertEqual(coordinator.hudSnapshot.detail, "转写服务未配置：请先在设置中配置 ASR provider。")
    }

    @MainActor
    func testCoordinatorPublishesDefaultSettingsSnapshots() {
        let coordinator = AppCoordinator()

        XCTAssertEqual(coordinator.audioSettingsSnapshot.inputDevice.title, "系统默认输入")
        XCTAssertEqual(coordinator.injectionSettingsSnapshot.strategy.title, "等待插入")
        XCTAssertEqual(coordinator.hudSettingsSnapshot.position.title, "顶部居中")
        XCTAssertEqual(coordinator.privacySettingsSnapshot.transcriptRetention.title, "不保留转写文本")
    }

    @MainActor
    func testCoordinatorSettingsSnapshotsReflectRecentRuntimeState() async {
        let result = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 1.2, sampleRate: 16_000, peakAmplitude: 0.64),
            transcript: TranscriptSnapshot(
                finalText: "hello",
                partials: [],
                providerName: "Fake ASR",
                latencyMilliseconds: 10
            ),
            injection: TextInjectionSnapshot(
                targetAppName: "TextEdit",
                strategy: .unicodeEvent,
                succeeded: true,
                detail: "已通过 Unicode 事件插入文本。"
            )
        )
        let coordinator = AppCoordinator(
            transcriptionCredentialStore: InMemoryTranscriptionCredentialStore(apiKey: "sk-test-abcdef"),
            recordingWorkflow: FakeRecordingWorkflow(result: result)
        )
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.audioSettingsSnapshot.levelMeter.title, "电平正常")
        XCTAssertEqual(coordinator.audioSettingsSnapshot.sampleRate.title, "16,000 Hz")
        XCTAssertEqual(coordinator.injectionSettingsSnapshot.focusedApp.title, "TextEdit")
        XCTAssertEqual(coordinator.privacySettingsSnapshot.keychain.detail, "sk-t...cdef")
    }

    @MainActor
    func testUnavailableTranscriptionFailureSurfacesProviderMessage() async {
        let recordingWorkflow = FakeRecordingWorkflow(stopError: TranscriptionProviderError.notConfigured)
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .providerOffline)
        XCTAssertEqual(coordinator.lastErrorMessage, "转写服务未配置：请先在设置中配置 ASR provider。")
    }

    @MainActor
    func testWorkbenchMarksRecentDoubaoStepFailedAfterTranscriptionError() async {
        let recordingWorkflow = FakeRecordingWorkflow(
            transcriptionStatus: .ready(providerName: "Doubao"),
            stopError: TranscriptionProviderError.provider(
                providerName: "Doubao",
                message: "server response contains no final text"
            )
        )
        let coordinator = AppCoordinator(
            transcriptionCredentialStore: InMemoryTranscriptionCredentialStore(apiKey: "sk-test-abcdef"),
            recordingWorkflow: recordingWorkflow
        )
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        let doubaoStep = coordinator.settingsWorkbenchSnapshot.recentChain[2]
        XCTAssertEqual(coordinator.settingsWorkbenchSnapshot.overview.title, "Doubao 转写失败")
        XCTAssertEqual(coordinator.settingsWorkbenchSnapshot.overview.primaryActionTitle, "前往转写服务")
        XCTAssertEqual(doubaoStep.detail, "Doubao 转写失败：server response contains no final text")
        XCTAssertEqual(doubaoStep.status, .needsAttention)
        XCTAssertEqual(doubaoStep.action, .openTranscription)
    }

    @MainActor
    func testWorkbenchKeepsDoubaoFailureWhenPartialArrivedBeforeTranscriptionError() async {
        let partial = TranscriptPartialSnapshot(
            text: "partial text",
            stablePrefixLength: 0,
            providerName: "Doubao"
        )
        let recordingWorkflow = FakeRecordingWorkflow(
            transcriptionStatus: .ready(providerName: "Doubao"),
            stopError: TranscriptionProviderError.transport(
                providerName: "Doubao",
                message: "timeout",
                retryable: true
            ),
            partialsToEmitBeforeStopError: [partial]
        )
        let coordinator = AppCoordinator(
            transcriptionCredentialStore: InMemoryTranscriptionCredentialStore(apiKey: "sk-test-abcdef"),
            recordingWorkflow: recordingWorkflow
        )
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        let doubaoStep = coordinator.settingsWorkbenchSnapshot.recentChain[2]
        XCTAssertEqual(coordinator.lastTranscript?.partials, ["partial text"])
        XCTAssertEqual(coordinator.settingsWorkbenchSnapshot.status(for: .transcription), .needsAttention)
        XCTAssertEqual(doubaoStep.detail, "Doubao 网络错误：timeout")
        XCTAssertEqual(doubaoStep.status, .needsAttention)
        XCTAssertEqual(doubaoStep.action, .openTranscription)
    }

    @MainActor
    func testMissingHotkeyPermissionsDoNotInstallHotkey() {
        let permissionProvider = FakePermissionProvider(
            current: [
                .microphone(.granted),
                .accessibility(.denied),
            ],
            requested: [
                .microphone(.granted),
                .accessibility(.granted),
            ]
        )
        let hotkeyProvider = FakeHotkeyProvider(startState: .listening)
        let coordinator = AppCoordinator(
            permissionProvider: permissionProvider,
            hotkeyProvider: hotkeyProvider
        )

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.hotkeyRuntimeState, .permissionNeeded)
        XCTAssertTrue(hotkeyProvider.startRequests.isEmpty)
    }

    @MainActor
    func testMountedImageLocationBlocksLaunchAtLoginEnable() async {
        let launchProvider = FakeLaunchAtLoginProvider(initialState: .disabled)
        let coordinator = AppCoordinator(
            launchAtLoginProvider: launchProvider,
            installLocationProvider: StaticInstallLocationProvider(
                snapshot: InstallLocationCheck.snapshot(forAppBundlePath: "/Volumes/Voco/Voco.app")
            )
        )
        coordinator.finishLaunching()

        await coordinator.setLaunchAtLoginEnabled(true)

        XCTAssertTrue(launchProvider.requests.isEmpty)
        XCTAssertEqual(coordinator.launchAtLoginState, .unavailable)
        XCTAssertEqual(coordinator.installLocation.status, .mountedImage)
        XCTAssertTrue(coordinator.lastErrorMessage?.contains("/Applications") == true)
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
    var transcriptionStatus: TranscriptionProviderStatus
    let startError: Error?
    let stopError: Error?
    let partialsToEmitOnStart: [TranscriptPartialSnapshot]
    let partialsToEmit: [TranscriptPartialSnapshot]
    let partialsToEmitBeforeStopError: [TranscriptPartialSnapshot]
    let pauseAfterStart: Bool
    let pauseAfterPartials: Bool
    private var storedProgress: TranscriptionProgressHandler?
    private var didEmitPartials = false
    private var didPauseStart = false
    private var startPausedContinuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var partialsEmittedContinuation: CheckedContinuation<Void, Never>?
    private var stopContinuation: CheckedContinuation<Void, Never>?

    init(
        result: RecordingWorkflowResult = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 0.4, sampleRate: 16_000, peakAmplitude: 0.5),
            transcript: TranscriptSnapshot(finalText: "", partials: [], providerName: "Fake ASR", latencyMilliseconds: nil),
            injection: .skippedEmpty
        ),
        transcriptionStatus: TranscriptionProviderStatus = .ready(providerName: "Fake ASR"),
        startError: Error? = nil,
        stopError: Error? = nil,
        partialsToEmitOnStart: [TranscriptPartialSnapshot] = [],
        partialsToEmit: [TranscriptPartialSnapshot] = [],
        partialsToEmitBeforeStopError: [TranscriptPartialSnapshot] = [],
        pauseAfterStart: Bool = false,
        pauseAfterPartials: Bool = false
    ) {
        self.result = result
        self.transcriptionStatus = transcriptionStatus
        self.startError = startError
        self.stopError = stopError
        self.partialsToEmitOnStart = partialsToEmitOnStart
        self.partialsToEmit = partialsToEmit
        self.partialsToEmitBeforeStopError = partialsToEmitBeforeStopError
        self.pauseAfterStart = pauseAfterStart
        self.pauseAfterPartials = pauseAfterPartials
    }

    func startRecording() async throws {
        try await startRecording(progress: nil)
    }

    func startRecording(progress: TranscriptionProgressHandler? = nil) async throws {
        startCount += 1

        if let startError {
            throw startError
        }

        if pauseAfterStart {
            didPauseStart = true
            startPausedContinuation?.resume()
            startPausedContinuation = nil

            await withCheckedContinuation { continuation in
                startContinuation = continuation
            }
        }

        for partial in partialsToEmitOnStart {
            progress?(partial)
        }
    }

    func stopRecording(progress: TranscriptionProgressHandler? = nil) async throws -> RecordingWorkflowResult {
        stopCount += 1
        storedProgress = progress

        if let stopError {
            for partial in partialsToEmitBeforeStopError {
                progress?(partial)
            }
            throw stopError
        }

        for partial in partialsToEmit {
            progress?(partial)
        }
        didEmitPartials = true
        partialsEmittedContinuation?.resume()
        partialsEmittedContinuation = nil

        if pauseAfterPartials {
            await withCheckedContinuation { continuation in
                stopContinuation = continuation
            }
        }

        return result
    }

    func waitUntilPartialsEmitted() async {
        if didEmitPartials {
            return
        }

        await withCheckedContinuation { continuation in
            partialsEmittedContinuation = continuation
        }
    }

    func waitUntilStartPaused() async {
        if didPauseStart {
            return
        }

        await withCheckedContinuation { continuation in
            startPausedContinuation = continuation
        }
    }

    func resumeStart() {
        startContinuation?.resume()
        startContinuation = nil
    }

    func resumeStop() {
        stopContinuation?.resume()
        stopContinuation = nil
    }

    func emitStoredPartial(_ partial: TranscriptPartialSnapshot) {
        storedProgress?(partial)
    }
}

@MainActor
private final class FakeTranscriptionCredentialStore: TranscriptionCredentialStoring {
    var snapshot: TranscriptionCredentialSnapshot
    var saveError: Error?
    var deleteError: Error?
    private var storedCredential: TranscriptionCredential?

    init(
        snapshot: TranscriptionCredentialSnapshot = .missing(provider: .doubao),
        saveError: Error? = nil,
        deleteError: Error? = nil
    ) {
        self.snapshot = snapshot
        self.saveError = saveError
        self.deleteError = deleteError
    }

    func currentSnapshot() -> TranscriptionCredentialSnapshot {
        snapshot
    }

    func saveCredential(
        _ credential: TranscriptionCredential,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot {
        if let saveError {
            throw saveError
        }

        let normalizedCredential = try credential.normalized()
        storedCredential = normalizedCredential
        snapshot = .stored(provider: provider, credential: normalizedCredential)
        return snapshot
    }

    func deleteCredentials(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredentialSnapshot {
        if let deleteError {
            throw deleteError
        }

        storedCredential = nil
        snapshot = .missing(provider: provider)
        return snapshot
    }

    func credential(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredential? {
        storedCredential
    }
}
