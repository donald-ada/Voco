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
    func testCoordinatorLoadsAndPersistsSkillSettings() {
        let store = FakeSkillPreferenceStore(
            skillSettings: SkillSettings(
                isEnabled: true,
                fillerCleanup: FillerCleanupSettings(isEnabled: false, rules: [])
            )
        )
        let coordinator = AppCoordinator(skillPreferenceStore: store)

        XCTAssertFalse(coordinator.skillSettings.fillerCleanup.isEnabled)

        let updated = SkillSettings(
            isEnabled: coordinator.skillSettings.isEnabled,
            fillerCleanup: FillerCleanupSettings(isEnabled: true, rules: coordinator.skillSettings.fillerCleanup.rules)
        )
        coordinator.saveSkillSettings(updated)

        XCTAssertTrue(coordinator.skillSettings.fillerCleanup.isEnabled)
        XCTAssertEqual(store.savedSkillSettings.last, updated)
    }

    @MainActor
    func testCoordinatorBuildsSkillSettingsSnapshotFromCurrentSettings() {
        let store = FakeSkillPreferenceStore(
            skillSettings: SkillSettings(
                isEnabled: true,
                fillerCleanup: FillerCleanupSettings(
                    isEnabled: true,
                    rules: [
                        FillerCleanupRule(
                            displayName: "删除嗯",
                            matchText: "嗯",
                            action: .delete,
                            isEnabled: true,
                            order: 0
                        )
                    ]
                )
            )
        )
        let coordinator = AppCoordinator(
            appPreferenceStore: FakeAppPreferenceStore(appLanguage: .en),
            skillPreferenceStore: store
        )

        let snapshot = coordinator.skillSettingsSnapshot(previewInput: "嗯hello")

        XCTAssertEqual(snapshot.title, "Skills")
        XCTAssertTrue(snapshot.isFillerCleanupEnabled)
        XCTAssertEqual(snapshot.preview.processedText, "hello")
        XCTAssertEqual(snapshot.preview.matchedRuleTitles, ["删除嗯"])
    }

    @MainActor
    func testCoordinatorSkillSettingsSnapshotUsesRecentSessionHitTotals() {
        let session = VoiceInputSessionSnapshot(
            transcriptText: "今天继续",
            rawTranscriptText: "嗯今天继续",
            postProcessingDiagnostics: [
                TranscriptPostProcessingDiagnostic(
                    skillID: FillerCleanupSkill.skillID,
                    ruleID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    ruleDisplayName: "删除嗯",
                    matchedText: "嗯",
                    replacementText: "",
                    matchCount: 4
                )
            ],
            wordCount: 4,
            durationSeconds: 3,
            targetAppName: "Notes",
            providerName: "火山引擎"
        )
        let coordinator = AppCoordinator(
            voiceInputSessionStore: FakeVoiceInputSessionStore(storedSessions: [session]),
            skillPreferenceStore: FakeSkillPreferenceStore(
                skillSettings: SkillSettings(
                    isEnabled: true,
                    fillerCleanup: FillerCleanupSettings(isEnabled: true)
                )
            )
        )

        let snapshot = coordinator.skillSettingsSnapshot(previewInput: "嗯")

        XCTAssertEqual(snapshot.preview.processedText, "")
        XCTAssertEqual(snapshot.fillerCleanupDetail.totalHitCount, 4)
        XCTAssertEqual(snapshot.fillerCleanupDetail.hitRows.map(\.matchedText), ["嗯"])
    }

    @MainActor
    func testCoordinatorDefaultsToVolcengineModelSelection() {
        let store = FakeTranscriptionModelSelectionStore(selection: .default)
        let coordinator = AppCoordinator(transcriptionModelSelectionStore: store)

        XCTAssertEqual(coordinator.transcriptionModelSelection.providerID, .volcengine)
    }

    @MainActor
    func testCoordinatorSavesReadyLocalModelSelection() {
        let store = FakeTranscriptionModelSelectionStore(selection: .default)
        let coordinator = AppCoordinator(
            transcriptionModelSelectionStore: store,
            localSpeechModelStatusProvider: { .ready }
        )

        coordinator.applyTranscriptionModelSelection(.localRecommended)

        XCTAssertEqual(coordinator.transcriptionModelSelection.providerID, .localRecommended)
        XCTAssertEqual(store.savedSelections.map(\.providerID), [.localRecommended])
    }

    @MainActor
    func testCoordinatorRejectsLocalModelSelectionWhenModelIsNotReady() {
        let store = FakeTranscriptionModelSelectionStore(selection: .default)
        let coordinator = AppCoordinator(
            transcriptionModelSelectionStore: store,
            localSpeechModelStatusProvider: { .notDownloaded }
        )

        coordinator.applyTranscriptionModelSelection(.localRecommended)

        XCTAssertEqual(coordinator.transcriptionModelSelection.providerID, .volcengine)
        XCTAssertTrue(store.savedSelections.isEmpty)
        XCTAssertEqual(coordinator.lastErrorMessage, "本地模型未下载。")
    }

    @MainActor
    func testCoordinatorWorkbenchSnapshotAllowsReadyLocalModelWithoutVolcengineCredentials() {
        let coordinator = AppCoordinator(
            transcriptionCredentialStore: FakeTranscriptionCredentialStore(snapshot: .missing(provider: .volcengine)),
            transcriptionModelSelectionStore: FakeTranscriptionModelSelectionStore(
                selection: TranscriptionModelSelection(providerID: .localRecommended)
            ),
            localSpeechModelStatusProvider: { .ready }
        )

        XCTAssertEqual(coordinator.transcriptionModelSelection.providerID, .localRecommended)
        XCTAssertEqual(coordinator.settingsWorkbenchSnapshot.status(for: .model), .ok)
    }

    @MainActor
    func testCoordinatorPublishesLocalModelDownloadProgressAndReadyState() async {
        let progress = LocalSpeechModelDownloadProgress(bytesWritten: 4, totalBytes: 10)
        let coordinator = AppCoordinator(
            downloadRecommendedLocalModelHandler: { update in
                update(.downloading(progress))
                update(.ready)
            }
        )

        await coordinator.downloadRecommendedLocalModel()

        XCTAssertEqual(coordinator.localSpeechModelStatus, .ready)
        XCTAssertNil(coordinator.lastErrorMessage)
    }

    @MainActor
    func testCoordinatorSkillToggleActionsPersistSemanticChanges() {
        let rule = FillerCleanupRule(displayName: "删除嗯", matchText: "嗯", action: .delete, order: 0)
        let store = FakeSkillPreferenceStore(
            skillSettings: SkillSettings(
                isEnabled: true,
                fillerCleanup: FillerCleanupSettings(isEnabled: false, rules: [rule])
            )
        )
        let coordinator = AppCoordinator(skillPreferenceStore: store)

        coordinator.setSkillsEnabled(false)

        XCTAssertFalse(coordinator.skillSettings.isEnabled)
        XCTAssertEqual(coordinator.skillSettings.fillerCleanup, FillerCleanupSettings(isEnabled: false, rules: [rule]))
        XCTAssertEqual(store.savedSkillSettings.last, coordinator.skillSettings)

        coordinator.setFillerCleanupEnabled(true)

        XCTAssertFalse(coordinator.skillSettings.isEnabled)
        XCTAssertTrue(coordinator.skillSettings.fillerCleanup.isEnabled)
        XCTAssertEqual(coordinator.skillSettings.fillerCleanup.rules, [rule])
        XCTAssertEqual(store.savedSkillSettings.last, coordinator.skillSettings)
    }

    @MainActor
    func testCoordinatorAddsFillerCleanupRuleWithNextOrder() {
        let store = FakeSkillPreferenceStore(
            skillSettings: SkillSettings(
                isEnabled: true,
                fillerCleanup: FillerCleanupSettings(
                    isEnabled: true,
                    rules: [
                        FillerCleanupRule(displayName: "First", matchText: "first", action: .delete, order: 2),
                        FillerCleanupRule(displayName: "Last", matchText: "last", action: .delete, order: 7),
                    ]
                )
            )
        )
        let coordinator = AppCoordinator(skillPreferenceStore: store)

        coordinator.addFillerCleanupRule(displayName: "New", matchText: "new", action: .replace(" "))

        let addedRule = coordinator.skillSettings.fillerCleanup.rules.last
        XCTAssertEqual(addedRule?.displayName, "New")
        XCTAssertEqual(addedRule?.matchText, "new")
        XCTAssertEqual(addedRule?.matchType, .plainText)
        XCTAssertEqual(addedRule?.action, .replace(" "))
        XCTAssertEqual(addedRule?.isEnabled, true)
        XCTAssertEqual(addedRule?.order, 8)
        XCTAssertEqual(store.savedSkillSettings.last, coordinator.skillSettings)
    }

    @MainActor
    func testCoordinatorAddedFillerCleanupRuleActionAffectsPreviewProcessing() {
        let store = FakeSkillPreferenceStore(
            skillSettings: SkillSettings(
                isEnabled: true,
                fillerCleanup: FillerCleanupSettings(isEnabled: true, rules: [])
            )
        )
        let coordinator = AppCoordinator(skillPreferenceStore: store)

        coordinator.addFillerCleanupRule(
            displayName: "那个啥",
            matchText: "那个啥",
            action: .replace("项目")
        )

        let snapshot = coordinator.skillSettingsSnapshot(previewInput: "那个啥今天继续")

        XCTAssertEqual(snapshot.preview.processedText, "项目今天继续")
        XCTAssertEqual(snapshot.fillerCleanupDetail.totalHitCount, 0)
        XCTAssertTrue(snapshot.fillerCleanupDetail.hitRows.isEmpty)
    }

    @MainActor
    func testCoordinatorUpdatesAndRemovesFillerCleanupRulesByID() {
        let keptRule = FillerCleanupRule(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "Keep",
            matchText: "keep",
            action: .delete,
            order: 0
        )
        let targetRule = FillerCleanupRule(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            displayName: "Target",
            matchText: "target",
            action: .delete,
            order: 1
        )
        let store = FakeSkillPreferenceStore(
            skillSettings: SkillSettings(
                isEnabled: true,
                fillerCleanup: FillerCleanupSettings(isEnabled: true, rules: [keptRule, targetRule])
            )
        )
        let coordinator = AppCoordinator(skillPreferenceStore: store)
        let updatedRule = FillerCleanupRule(
            id: targetRule.id,
            displayName: "Updated",
            matchText: "updated",
            action: .replace("replacement"),
            isEnabled: false,
            order: 3
        )

        coordinator.updateFillerCleanupRule(updatedRule)

        XCTAssertEqual(coordinator.skillSettings.fillerCleanup.rules, [keptRule, updatedRule])
        XCTAssertEqual(store.savedSkillSettings.last, coordinator.skillSettings)

        let stateBeforeMissingUpdate = coordinator.skillSettings
        coordinator.updateFillerCleanupRule(
            FillerCleanupRule(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                displayName: "Missing",
                matchText: "missing",
                action: .delete,
                order: 4
            )
        )

        XCTAssertEqual(coordinator.skillSettings, stateBeforeMissingUpdate)

        coordinator.removeFillerCleanupRule(id: keptRule.id)

        XCTAssertEqual(coordinator.skillSettings.fillerCleanup.rules, [updatedRule])
        XCTAssertEqual(store.savedSkillSettings.last, coordinator.skillSettings)
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
    func testLaunchAtLoginFailureUsesSelectedLanguageForErrorMessage() async {
        let launchProvider = FakeLaunchAtLoginProvider(initialState: .disabled)
        launchProvider.error = LaunchAtLoginTestError.failed
        let preferences = FakeAppPreferenceStore(appLanguage: .en)
        let coordinator = AppCoordinator(
            launchAtLoginProvider: launchProvider,
            appPreferenceStore: preferences
        )

        await coordinator.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(coordinator.lastErrorMessage, "Launch at login setup failed: failed")
        XCTAssertFalse(coordinator.lastErrorMessage?.contains("登录时启动") ?? true)
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
    func testSuccessfulRecordingCompletionHidesHUDImmediately() async {
        let result = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 1.1, sampleRate: 16_000, peakAmplitude: 0.61),
            transcript: TranscriptSnapshot(
                finalText: "hello",
                partials: ["he"],
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
        let recordingWorkflow = FakeRecordingWorkflow(result: result)
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(coordinator.hudSnapshot.phase, .hidden)
        XCTAssertFalse(coordinator.hudSnapshot.isVisible)
    }

    @MainActor
    func testNewRecordingClearsHUDPreviewWithoutDroppingLastCompletedTranscript() async {
        let completedTranscript = TranscriptSnapshot(
            finalText: "first session words",
            partials: ["first session"],
            providerName: "Fake ASR",
            latencyMilliseconds: 33
        )
        let result = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 1.1, sampleRate: 16_000, peakAmplitude: 0.61),
            transcript: completedTranscript,
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
        XCTAssertEqual(coordinator.hudSnapshot.phase, .hidden)

        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .recording)
        XCTAssertEqual(coordinator.lastTranscript, completedTranscript)
        XCTAssertNil(coordinator.hudSnapshot.transcriptPreview)
    }

    @MainActor
    func testNewRecordingPartialDoesNotReusePreviousFinalText() async {
        let completedTranscript = TranscriptSnapshot(
            finalText: "first session words",
            partials: ["first session"],
            providerName: "Fake ASR",
            latencyMilliseconds: 33
        )
        let result = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 1.1, sampleRate: 16_000, peakAmplitude: 0.61),
            transcript: completedTranscript,
            injection: TextInjectionSnapshot(
                targetAppName: "TextEdit",
                strategy: .unicodeEvent,
                succeeded: true,
                detail: "Inserted through unicode events"
            )
        )
        let recordingWorkflow = FakeRecordingWorkflow(
            result: result,
            partialsToEmitOnStart: [
                TranscriptPartialSnapshot(
                    text: "second session live",
                    stablePrefixLength: 0,
                    providerName: "Fake ASR"
                )
            ]
        )
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .recording)
        XCTAssertEqual(coordinator.hudSnapshot.transcriptPreview, "second session live")
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
        XCTAssertEqual(coordinator.settingsWorkbenchSnapshot.status(for: .overview), .needsAttention)
    }

    @MainActor
    func testCoordinatorPublishesTranscriptionProviderStatus() {
        let recordingWorkflow = FakeRecordingWorkflow(transcriptionStatus: .authenticationRequired(providerName: "火山引擎"))
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.transcriptionProviderStatus, .authenticationRequired(providerName: "火山引擎"))
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
    func testAsyncCredentialRefreshUpdatesSnapshotAfterNonBlockingLaunch() async {
        let credentialStore = AsyncTranscriptionCredentialStore(
            syncSnapshot: .missing(provider: .volcengine),
            asyncSnapshot: .stored(provider: .volcengine, credential: .volcengineAPIKey("sk-test-abcdef"))
        )
        let coordinator = AppCoordinator(transcriptionCredentialStore: credentialStore)

        coordinator.finishLaunching()
        XCTAssertFalse(coordinator.transcriptionCredentials.hasCredential)

        await coordinator.refreshTranscriptionCredentialsFromStore()

        XCTAssertTrue(coordinator.transcriptionCredentials.hasCredential)
        XCTAssertEqual(coordinator.transcriptionCredentials.maskedAPIKey, "sk-t...cdef")
    }

    @MainActor
    func testBackgroundCredentialRefreshCoalescesInFlightReads() async {
        let credentialStore = SuspendingTranscriptionCredentialStore()
        let coordinator = AppCoordinator(transcriptionCredentialStore: credentialStore)

        coordinator.refreshTranscriptionCredentialsInBackground()
        coordinator.refreshTranscriptionCredentialsInBackground()
        await Task.yield()

        XCTAssertEqual(credentialStore.loadCount, 1)

        credentialStore.resume(
            .stored(provider: .volcengine, credential: .volcengineAPIKey("sk-test-abcdef"))
        )
        await Task.yield()

        XCTAssertTrue(coordinator.transcriptionCredentials.hasCredential)
    }

    @MainActor
    func testCoordinatorSavesAndClearsTranscriptionCredentials() async throws {
        let credentialStore = InMemoryTranscriptionCredentialStore()
        let coordinator = AppCoordinator(transcriptionCredentialStore: credentialStore)

        await coordinator.saveTranscriptionAPIKey("sk-test-abcdef")

        XCTAssertTrue(coordinator.transcriptionCredentials.hasAPIKey)
        XCTAssertEqual(coordinator.transcriptionCredentials.maskedAPIKey, "sk-t...cdef")
        XCTAssertNil(coordinator.lastErrorMessage)
        let savedAPIKey = try await credentialStore.apiKey(for: .volcengine)
        XCTAssertEqual(savedAPIKey, "sk-test-abcdef")

        await coordinator.clearTranscriptionCredentials()

        XCTAssertFalse(coordinator.transcriptionCredentials.hasAPIKey)
        XCTAssertNil(coordinator.lastErrorMessage)
        let clearedAPIKey = try await credentialStore.apiKey(for: .volcengine)
        XCTAssertNil(clearedAPIKey)
    }

    @MainActor
    func testCoordinatorSavesLegacyVolcengineCredentialMode() async throws {
        let credentialStore = InMemoryTranscriptionCredentialStore()
        let coordinator = AppCoordinator(transcriptionCredentialStore: credentialStore)

        await coordinator.saveVolcengineAppIDAccessToken(
            appID: "3145608744",
            accessToken: "legacy-token"
        )

        XCTAssertTrue(coordinator.transcriptionCredentials.hasCredential)
        XCTAssertFalse(coordinator.transcriptionCredentials.hasAPIKey)
        XCTAssertEqual(coordinator.transcriptionCredentials.mode, .appIDAccessToken)
        let credential = try await credentialStore.credential(for: .volcengine)
        XCTAssertEqual(credential?.appID, "3145608744")
        XCTAssertEqual(credential?.accessToken, "legacy-token")
    }

    @MainActor
    func testSavingTranscriptionCredentialRefreshesProviderStatus() async {
        let credentialStore = InMemoryTranscriptionCredentialStore()
        let recordingWorkflow = FakeRecordingWorkflow(
            transcriptionStatus: .authenticationRequired(providerName: "火山引擎")
        )
        let coordinator = AppCoordinator(
            transcriptionCredentialStore: credentialStore,
            recordingWorkflow: recordingWorkflow
        )
        coordinator.finishLaunching()
        XCTAssertEqual(coordinator.transcriptionProviderStatus, .authenticationRequired(providerName: "火山引擎"))

        recordingWorkflow.transcriptionStatus = .ready(providerName: "火山引擎")
        await coordinator.saveTranscriptionAPIKey("sk-test-abcdef")

        XCTAssertEqual(coordinator.transcriptionProviderStatus, .ready(providerName: "火山引擎"))
    }

    @MainActor
    func testClearingTranscriptionCredentialRefreshesProviderStatus() async {
        let credentialStore = InMemoryTranscriptionCredentialStore(apiKey: "sk-test-abcdef")
        let recordingWorkflow = FakeRecordingWorkflow(
            transcriptionStatus: .ready(providerName: "火山引擎")
        )
        let coordinator = AppCoordinator(
            transcriptionCredentialStore: credentialStore,
            recordingWorkflow: recordingWorkflow
        )
        coordinator.finishLaunching()
        XCTAssertEqual(coordinator.transcriptionProviderStatus, .ready(providerName: "火山引擎"))

        recordingWorkflow.transcriptionStatus = .authenticationRequired(providerName: "火山引擎")
        await coordinator.clearTranscriptionCredentials()

        XCTAssertEqual(coordinator.transcriptionProviderStatus, .authenticationRequired(providerName: "火山引擎"))
    }

    @MainActor
    func testCredentialStoreFailureSurfacesError() async {
        let credentialStore = FakeTranscriptionCredentialStore(
            saveError: TranscriptionCredentialError.storeFailed(message: "Keychain denied")
        )
        let coordinator = AppCoordinator(transcriptionCredentialStore: credentialStore)

        await coordinator.saveTranscriptionAPIKey("sk-test-abcdef")

        XCTAssertEqual(coordinator.transcriptionCredentials.statusTitle, "火山引擎凭证读取失败")
        XCTAssertEqual(coordinator.transcriptionCredentials.lastErrorMessage, "保存 ASR 凭证失败：Keychain denied")
        XCTAssertEqual(coordinator.lastErrorMessage, "保存 ASR 凭证失败：Keychain denied")
    }

    @MainActor
    func testChangingAppLanguageRelocalizesCredentialStoreFailure() async {
        let credentialStore = FakeTranscriptionCredentialStore(
            saveError: TranscriptionCredentialError.storeFailed(message: "Keychain denied")
        )
        let coordinator = AppCoordinator(transcriptionCredentialStore: credentialStore)

        await coordinator.saveTranscriptionAPIKey("sk-test-abcdef")
        coordinator.setAppLanguage(.en)

        XCTAssertEqual(coordinator.lastErrorMessage, "Unable to save ASR credentials: Keychain denied")
        XCTAssertEqual(
            coordinator.transcriptionCredentials.lastErrorMessage,
            "Unable to save ASR credentials: Keychain denied"
        )
        XCTAssertEqual(
            coordinator.transcriptionCredentials.statusTitle(strings: VocoStrings(language: .en)),
            "Volcengine credentials read failed"
        )
    }

    @MainActor
    func testChangingAppLanguageRelocalizesLoadedCredentialSnapshotFailure() {
        let credentialStore = FakeTranscriptionCredentialStore(
            snapshot: .failed(
                provider: .volcengine,
                message: "Keychain 返回的数据格式无效。"
            )
        )
        let coordinator = AppCoordinator(transcriptionCredentialStore: credentialStore)

        coordinator.refreshTranscriptionCredentials()
        coordinator.setAppLanguage(.en)

        XCTAssertEqual(
            coordinator.lastErrorMessage,
            "Keychain returned data in an invalid format."
        )
        XCTAssertEqual(
            coordinator.transcriptionCredentials.storageDetail,
            "Keychain access failed: Keychain returned data in an invalid format."
        )
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
        XCTAssertEqual(coordinator.hudSnapshot.detail, "模型未配置：请先在设置中配置火山引擎凭证。")
    }

    @MainActor
    func testChangingAppLanguageRelocalizesCurrentProviderError() async {
        let recordingWorkflow = FakeRecordingWorkflow(stopError: TranscriptionProviderError.notConfigured)
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()
        XCTAssertEqual(coordinator.lastErrorMessage, "模型未配置：请先在设置中配置火山引擎凭证。")

        coordinator.setAppLanguage(.en)

        XCTAssertEqual(
            coordinator.lastErrorMessage,
            "Model not configured: configure Volcengine credentials in Settings first."
        )
        XCTAssertEqual(
            coordinator.hudSnapshot.detail,
            "Model not configured: configure Volcengine credentials in Settings first."
        )
    }

    @MainActor
    func testEnglishCoordinatorUsesLocalizedTextInjectionFailure() async {
        let result = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 0.4, sampleRate: 16_000, peakAmplitude: 0.5),
            transcript: TranscriptSnapshot(
                finalText: "hello",
                partials: [],
                providerName: "Fake ASR",
                latencyMilliseconds: 10
            ),
            injection: .failed(
                targetAppName: "Notes",
                strategy: .unavailable,
                error: .accessibilityPermissionMissing
            )
        )
        let coordinator = AppCoordinator(
            transcriptionCredentialStore: InMemoryTranscriptionCredentialStore(apiKey: "sk-test-abcdef"),
            recordingWorkflow: FakeRecordingWorkflow(result: result)
        )
        coordinator.setAppLanguage(.en)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .error)
        XCTAssertEqual(
            coordinator.lastErrorMessage,
            "Unable to insert text: allow Voco to use Accessibility in System Settings first."
        )
        XCTAssertEqual(
            coordinator.settingsWorkbenchSnapshot.overview.detail,
            "Unable to insert text: allow Voco to use Accessibility in System Settings first."
        )
    }

    @MainActor
    func testCoordinatorPublishesDefaultSettingsSnapshots() {
        let coordinator = AppCoordinator()

        XCTAssertEqual(coordinator.audioSettingsSnapshot.inputDevice.title, "系统默认输入")
        XCTAssertEqual(coordinator.injectionSettingsSnapshot.strategy.title, "等待插入")
        XCTAssertEqual(coordinator.hudSettingsSnapshot.position.title, "顶部居中")
    }

    @MainActor
    func testUpdatingVoiceInputSettingsRestartsHotkeyMonitorAndUpdatesAudioSelection() {
        let hotkeyProvider = FakeHotkeyProvider(startState: .listening)
        let recordingWorkflow = FakeRecordingWorkflow()
        let preferences = FakeVoiceInputPreferenceStore()
        let coordinator = AppCoordinator(
            recordingWorkflow: recordingWorkflow,
            hotkeyProvider: hotkeyProvider,
            voiceInputPreferenceStore: preferences
        )
        coordinator.finishLaunching()

        coordinator.setHotkeyPreset(.capsLock)
        coordinator.setHotkeyMode(.pressAndHold)
        coordinator.setAudioInputDevice(.device(id: "studio-mic", title: "Studio Mic"))

        XCTAssertEqual(coordinator.hotkeyBinding, HotkeyPreset.capsLock.binding)
        XCTAssertEqual(coordinator.hotkeyMode, .pressAndHold)
        XCTAssertEqual(hotkeyProvider.stopCount, 2)
        XCTAssertEqual(
            hotkeyProvider.startRequests.map(\.binding),
            [.default, HotkeyPreset.capsLock.binding, HotkeyPreset.capsLock.binding]
        )
        XCTAssertEqual(
            hotkeyProvider.startRequests.map(\.mode),
            [.toggle, .toggle, .pressAndHold]
        )
        XCTAssertEqual(coordinator.audioSettingsSnapshot.inputDevice.title, "Studio Mic")
        XCTAssertEqual(recordingWorkflow.selectedAudioInputDevice, .device(id: "studio-mic", title: "Studio Mic"))
        XCTAssertEqual(preferences.hotkeyPreset, .capsLock)
        XCTAssertEqual(preferences.hotkeyMode, .pressAndHold)
        XCTAssertEqual(preferences.audioInputDevice, .device(id: "studio-mic", title: "Studio Mic"))
    }

    @MainActor
    func testCoordinatorLoadsAndPersistsSilentLaunchPreference() {
        let preferences = FakeAppPreferenceStore(silentLaunchEnabled: true)
        let coordinator = AppCoordinator(appPreferenceStore: preferences)

        XCTAssertTrue(coordinator.silentLaunchEnabled)

        coordinator.setSilentLaunchEnabled(false)

        XCTAssertFalse(coordinator.silentLaunchEnabled)
        XCTAssertEqual(preferences.savedSilentLaunchValues, [false])
    }

    @MainActor
    func testCoordinatorLoadsAndPersistsDisplayInDockPreference() {
        let preferences = FakeAppPreferenceStore(displayInDockEnabled: true)
        let coordinator = AppCoordinator(appPreferenceStore: preferences)

        XCTAssertTrue(coordinator.displayInDockEnabled)

        coordinator.setDisplayInDockEnabled(false)

        XCTAssertFalse(coordinator.displayInDockEnabled)
        XCTAssertEqual(preferences.savedDisplayInDockValues, [false])
    }

    @MainActor
    func testCoordinatorLoadsAndPersistsVoiceInputSessionHistoryPreferences() {
        let preferences = FakeAppPreferenceStore(
            voiceInputSessionHistoryEnabled: false,
            voiceInputSessionRetentionPolicy: .forever
        )
        let coordinator = AppCoordinator(appPreferenceStore: preferences)

        XCTAssertFalse(coordinator.voiceInputSessionHistoryEnabled)
        XCTAssertEqual(coordinator.voiceInputSessionRetentionPolicy, .forever)

        coordinator.setVoiceInputSessionHistoryEnabled(true)
        coordinator.setVoiceInputSessionRetentionPolicy(.last100)

        XCTAssertTrue(coordinator.voiceInputSessionHistoryEnabled)
        XCTAssertEqual(coordinator.voiceInputSessionRetentionPolicy, .last100)
        XCTAssertEqual(preferences.savedVoiceInputSessionHistoryValues, [true])
        XCTAssertEqual(preferences.savedVoiceInputSessionRetentionPolicies, [.last100])
    }

    @MainActor
    func testCoordinatorSessionStoreFailureUsesSelectedLanguage() {
        let preferences = FakeAppPreferenceStore(
            voiceInputSessionHistoryEnabled: false,
            appLanguage: .en
        )
        let sessionStore = FakeVoiceInputSessionStore(
            loadError: VoiceInputSessionStoreError.loadFailed(message: "database unavailable")
        )
        let coordinator = AppCoordinator(
            appPreferenceStore: preferences,
            voiceInputSessionStore: sessionStore
        )

        coordinator.setVoiceInputSessionHistoryEnabled(true)

        XCTAssertEqual(
            coordinator.lastErrorMessage,
            "Unable to load session history: database unavailable"
        )
    }

    @MainActor
    func testCoordinatorReadsInitialAppLanguageFromPreferences() {
        let store = FakeAppPreferenceStore(appLanguage: .en)
        let coordinator = AppCoordinator(appPreferenceStore: store)

        XCTAssertEqual(coordinator.appLanguage, .en)
        XCTAssertEqual(coordinator.strings.language, .en)
    }

    @MainActor
    func testCoordinatorMenuBarSnapshotUsesSelectedLanguage() {
        let store = FakeAppPreferenceStore(appLanguage: .en)
        let coordinator = AppCoordinator(appPreferenceStore: store)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.snapshot.title, "Ready")
    }

    @MainActor
    func testCoordinatorHUDSnapshotUsesSelectedLanguage() {
        let store = FakeAppPreferenceStore(appLanguage: .en)
        let coordinator = AppCoordinator(appPreferenceStore: store)

        coordinator.fail("network down")

        XCTAssertEqual(coordinator.hudSnapshot.title, "Needs Attention")
        XCTAssertEqual(coordinator.hudSnapshot.detail, "network down")
    }

    @MainActor
    func testCoordinatorPersistsAppLanguageChanges() {
        let store = FakeAppPreferenceStore(appLanguage: .zhHans)
        let coordinator = AppCoordinator(appPreferenceStore: store)

        coordinator.setAppLanguage(.en)

        XCTAssertEqual(coordinator.appLanguage, .en)
        XCTAssertEqual(store.appLanguage, .en)
    }

    @MainActor
    func testCoordinatorUsesSelectedLanguageForInstallAndLegacySnapshots() {
        let store = FakeAppPreferenceStore(appLanguage: .en)
        let launchAgent = URL(fileURLWithPath: "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist")
        let coordinator = AppCoordinator(
            installLocationProvider: LocalizedInstallLocationProvider(path: "/Applications/Voco.app"),
            legacyInstallProvider: LocalizedLegacyInstallProvider(launchAgentURL: launchAgent),
            appPreferenceStore: store
        )

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.installLocation.title, "Installed")
        XCTAssertEqual(coordinator.legacyInstall.title, "No legacy launch item detected")
    }

    @MainActor
    func testChangingAppLanguageRefreshesLocalizedInstallAndLegacySnapshots() {
        let store = FakeAppPreferenceStore(appLanguage: .zhHans)
        let launchAgent = URL(fileURLWithPath: "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist")
        let coordinator = AppCoordinator(
            installLocationProvider: LocalizedInstallLocationProvider(path: "/Volumes/Voco/Voco.app"),
            legacyInstallProvider: LocalizedLegacyInstallProvider(launchAgentURL: launchAgent, status: .detected),
            appPreferenceStore: store
        )

        XCTAssertEqual(coordinator.installLocation.title, "磁盘映像")
        XCTAssertEqual(coordinator.legacyInstall.title, "检测到旧版后台启动项")

        coordinator.setAppLanguage(.en)

        XCTAssertEqual(coordinator.installLocation.title, "Disk Image")
        XCTAssertTrue(coordinator.installLocation.detail.contains("not the final install location"))
        XCTAssertFalse(coordinator.installLocation.detail.contains("不是最终安装位置"))
        XCTAssertEqual(coordinator.legacyInstall.title, "Legacy background launch item detected")
        XCTAssertTrue(coordinator.legacyInstall.detail.contains("Detected legacy LaunchAgent"))
        XCTAssertFalse(coordinator.legacyInstall.detail.contains("检测到旧版"))
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
    }

    @MainActor
    func testSuccessfulRecordingAddsRawTranscriptToRecentVoiceInputSessions() async {
        let result = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 42, sampleRate: 16_000, peakAmplitude: 0.42),
            transcript: TranscriptSnapshot(
                finalText: "把总览改成主页。右侧的语音输入流程不要再占四大行。",
                partials: [],
                providerName: "火山引擎",
                latencyMilliseconds: 25
            ),
            injection: TextInjectionSnapshot(
                targetAppName: "Codex",
                strategy: .unicodeEvent,
                succeeded: true,
                detail: "已通过 Unicode 事件插入文本。"
            )
        )
        let coordinator = AppCoordinator(recordingWorkflow: FakeRecordingWorkflow(result: result))
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.recentVoiceInputSessions.count, 1)
        XCTAssertEqual(coordinator.recentVoiceInputSessions[0].transcriptText, result.transcript.finalText)
        XCTAssertEqual(coordinator.recentVoiceInputSessions[0].targetAppName, "Codex")
        XCTAssertEqual(coordinator.recentVoiceInputSessions[0].durationTitle, "42s")
    }

    @MainActor
    func testCoordinatorLoadsRecentVoiceInputSessionsFromStore() {
        let session = VoiceInputSessionSnapshot(
            transcriptText: "上次录音内容",
            wordCount: 6,
            durationSeconds: 4,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            targetAppName: "Codex",
            providerName: "火山引擎"
        )
        let sessionStore = FakeVoiceInputSessionStore(storedSessions: [session])

        let coordinator = AppCoordinator(voiceInputSessionStore: sessionStore)

        XCTAssertEqual(coordinator.recentVoiceInputSessions, [session])
        XCTAssertEqual(sessionStore.loadLimitRequests, [VoiceInputSessionRetentionPolicy.last1000.loadLimit])
    }

    @MainActor
    func testSuccessfulRecordingPersistsRecentVoiceInputSessionToStore() async {
        let result = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 42, sampleRate: 16_000, peakAmplitude: 0.42),
            transcript: TranscriptSnapshot(
                finalText: "持久化这条录音。",
                partials: [],
                providerName: "火山引擎",
                latencyMilliseconds: 25
            ),
            injection: TextInjectionSnapshot(
                targetAppName: "Codex",
                strategy: .unicodeEvent,
                succeeded: true,
                detail: "已通过 Unicode 事件插入文本。"
            )
        )
        let sessionStore = FakeVoiceInputSessionStore()
        let coordinator = AppCoordinator(
            recordingWorkflow: FakeRecordingWorkflow(result: result),
            voiceInputSessionStore: sessionStore
        )
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(sessionStore.savedSessions.map(\.transcriptText), [result.transcript.finalText])
        XCTAssertEqual(sessionStore.storedSessions.map(\.transcriptText), [result.transcript.finalText])
    }

    @MainActor
    func testDisabledVoiceInputSessionHistoryDoesNotPersistRecording() async {
        let result = RecordingWorkflowResult(
            audio: CapturedAudioSnapshot(durationSeconds: 42, sampleRate: 16_000, peakAmplitude: 0.42),
            transcript: TranscriptSnapshot(
                finalText: "这条只显示在当前运行。",
                partials: [],
                providerName: "火山引擎",
                latencyMilliseconds: 25
            ),
            injection: TextInjectionSnapshot(
                targetAppName: "Codex",
                strategy: .unicodeEvent,
                succeeded: true,
                detail: "已通过 Unicode 事件插入文本。"
            )
        )
        let preferences = FakeAppPreferenceStore(voiceInputSessionHistoryEnabled: false)
        let sessionStore = FakeVoiceInputSessionStore()
        let coordinator = AppCoordinator(
            recordingWorkflow: FakeRecordingWorkflow(result: result),
            appPreferenceStore: preferences,
            voiceInputSessionStore: sessionStore
        )
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.recentVoiceInputSessions.map(\.transcriptText), [result.transcript.finalText])
        XCTAssertTrue(sessionStore.savedSessions.isEmpty)
        XCTAssertEqual(sessionStore.loadLimitRequests, [])
    }

    @MainActor
    func testChangingVoiceInputSessionRetentionPolicyTrimsStoreAndReloadsSessions() {
        let sessions = (1...105).map { index in
            VoiceInputSessionSnapshot(
                transcriptText: "录音 \(index)",
                wordCount: 4,
                durationSeconds: Double(index),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                targetAppName: "Codex",
                providerName: "火山引擎"
            )
        }
        let sessionStore = FakeVoiceInputSessionStore(storedSessions: sessions.reversed())
        let coordinator = AppCoordinator(voiceInputSessionStore: sessionStore)

        coordinator.setVoiceInputSessionRetentionPolicy(.last100)

        XCTAssertEqual(sessionStore.trimLimitRequests, [100])
        XCTAssertEqual(sessionStore.loadLimitRequests.suffix(1), [100])
        XCTAssertEqual(coordinator.recentVoiceInputSessions.count, 100)
    }

    @MainActor
    func testUnavailableTranscriptionFailureSurfacesProviderMessage() async {
        let recordingWorkflow = FakeRecordingWorkflow(stopError: TranscriptionProviderError.notConfigured)
        let coordinator = AppCoordinator(recordingWorkflow: recordingWorkflow)
        coordinator.finishLaunching()

        await coordinator.toggleRecordingFromUserAction()
        await coordinator.toggleRecordingFromUserAction()

        XCTAssertEqual(coordinator.status, .providerOffline)
        XCTAssertEqual(coordinator.lastErrorMessage, "模型未配置：请先在设置中配置火山引擎凭证。")
    }

    @MainActor
    func testWorkbenchMarksVolcengineFailedAfterTranscriptionError() async {
        let recordingWorkflow = FakeRecordingWorkflow(
            transcriptionStatus: .ready(providerName: "火山引擎"),
            stopError: TranscriptionProviderError.provider(
                providerName: "火山引擎",
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

        XCTAssertEqual(coordinator.settingsWorkbenchSnapshot.overview.title, "火山引擎转写失败")
        XCTAssertEqual(
            coordinator.settingsWorkbenchSnapshot.overview.primaryActionID,
            SettingsWorkbenchActionID.openModel
        )
        XCTAssertEqual(coordinator.settingsWorkbenchSnapshot.status(for: .model), .needsAttention)
    }

    @MainActor
    func testWorkbenchKeepsVolcengineFailureWhenPartialArrivedBeforeTranscriptionError() async {
        let partial = TranscriptPartialSnapshot(
            text: "partial text",
            stablePrefixLength: 0,
            providerName: "火山引擎"
        )
        let recordingWorkflow = FakeRecordingWorkflow(
            transcriptionStatus: .ready(providerName: "火山引擎"),
            stopError: TranscriptionProviderError.transport(
                providerName: "火山引擎",
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

        XCTAssertEqual(coordinator.lastTranscript?.partials, ["partial text"])
        XCTAssertEqual(coordinator.settingsWorkbenchSnapshot.status(for: .model), .needsAttention)
        XCTAssertEqual(coordinator.settingsWorkbenchSnapshot.overview.detail, "火山引擎网络错误：timeout")
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

private struct LocalizedInstallLocationProvider: InstallLocationProviding {
    let path: String

    func currentInstallLocation() -> InstallLocationSnapshot {
        InstallLocationCheck.snapshot(forAppBundlePath: path)
    }

    func currentInstallLocation(strings: VocoStrings) -> InstallLocationSnapshot {
        InstallLocationCheck.snapshot(forAppBundlePath: path, strings: strings)
    }
}

@MainActor
private struct LocalizedLegacyInstallProvider: LegacyInstallProviding {
    let launchAgentURL: URL
    var status: LegacyInstallStatus = .notFound

    func currentSnapshot() -> LegacyInstallSnapshot {
        snapshot(strings: VocoStrings())
    }

    func currentSnapshot(strings: VocoStrings) -> LegacyInstallSnapshot {
        snapshot(strings: strings)
    }

    func removeKnownLaunchAgent() async throws -> LegacyInstallSnapshot {
        snapshot(strings: VocoStrings())
    }

    func removeKnownLaunchAgent(strings: VocoStrings) async throws -> LegacyInstallSnapshot {
        snapshot(strings: strings)
    }

    private func snapshot(strings: VocoStrings) -> LegacyInstallSnapshot {
        switch status {
        case .notFound:
            .notFound(launchAgentURL: launchAgentURL, strings: strings)
        case .detected:
            .detected(launchAgentURL: launchAgentURL, strings: strings)
        case .removalFailed(let message):
            .failed(launchAgentURL: launchAgentURL, message: message, strings: strings)
        }
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
    private(set) var selectedAudioInputDevice: AudioInputDeviceSelection
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
        pauseAfterPartials: Bool = false,
        selectedAudioInputDevice: AudioInputDeviceSelection = .systemDefault
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
        self.selectedAudioInputDevice = selectedAudioInputDevice
    }

    var availableAudioInputDevices: [AudioInputDeviceSelection] {
        [.systemDefault, .device(id: "studio-mic", title: "Studio Mic")]
    }

    func setAudioInputDevice(_ device: AudioInputDeviceSelection) {
        selectedAudioInputDevice = device
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
private final class FakeVoiceInputPreferenceStore: VoiceInputPreferenceStoring {
    private(set) var hotkeyPreset: HotkeyPreset?
    private(set) var hotkeyMode: HotkeyMode?
    private(set) var audioInputDevice: AudioInputDeviceSelection?

    func saveHotkeyPreset(_ preset: HotkeyPreset) {
        hotkeyPreset = preset
    }

    func saveHotkeyMode(_ mode: HotkeyMode) {
        hotkeyMode = mode
    }

    func saveAudioInputDevice(_ device: AudioInputDeviceSelection) {
        audioInputDevice = device
    }
}

@MainActor
private final class FakeSkillPreferenceStore: SkillPreferenceStoring {
    private(set) var skillSettings: SkillSettings
    private(set) var savedSkillSettings: [SkillSettings] = []

    init(skillSettings: SkillSettings = .default) {
        self.skillSettings = skillSettings
    }

    func saveSkillSettings(_ settings: SkillSettings) {
        skillSettings = settings
        savedSkillSettings.append(settings)
    }
}

@MainActor
private final class FakeTranscriptionModelSelectionStore: TranscriptionModelSelectionStoring {
    private(set) var selection: TranscriptionModelSelection
    private(set) var savedSelections: [TranscriptionModelSelection] = []

    init(selection: TranscriptionModelSelection = .default) {
        self.selection = selection
    }

    func saveSelection(_ selection: TranscriptionModelSelection) {
        self.selection = selection
        savedSelections.append(selection)
    }
}

@MainActor
private final class FakeAppPreferenceStore: AppPreferenceStoring {
    private(set) var silentLaunchEnabled: Bool
    private(set) var displayInDockEnabled: Bool
    private(set) var voiceInputSessionHistoryEnabled: Bool
    private(set) var voiceInputSessionRetentionPolicy: VoiceInputSessionRetentionPolicy
    private(set) var appLanguage: AppLanguage
    private(set) var savedSilentLaunchValues: [Bool] = []
    private(set) var savedDisplayInDockValues: [Bool] = []
    private(set) var savedVoiceInputSessionHistoryValues: [Bool] = []
    private(set) var savedVoiceInputSessionRetentionPolicies: [VoiceInputSessionRetentionPolicy] = []
    private(set) var savedAppLanguages: [AppLanguage] = []

    init(
        silentLaunchEnabled: Bool = false,
        displayInDockEnabled: Bool = false,
        voiceInputSessionHistoryEnabled: Bool = true,
        voiceInputSessionRetentionPolicy: VoiceInputSessionRetentionPolicy = .last1000,
        appLanguage: AppLanguage = .default
    ) {
        self.silentLaunchEnabled = silentLaunchEnabled
        self.displayInDockEnabled = displayInDockEnabled
        self.voiceInputSessionHistoryEnabled = voiceInputSessionHistoryEnabled
        self.voiceInputSessionRetentionPolicy = voiceInputSessionRetentionPolicy
        self.appLanguage = appLanguage
    }

    func saveSilentLaunchEnabled(_ enabled: Bool) {
        silentLaunchEnabled = enabled
        savedSilentLaunchValues.append(enabled)
    }

    func saveDisplayInDockEnabled(_ enabled: Bool) {
        displayInDockEnabled = enabled
        savedDisplayInDockValues.append(enabled)
    }

    func saveVoiceInputSessionHistoryEnabled(_ enabled: Bool) {
        voiceInputSessionHistoryEnabled = enabled
        savedVoiceInputSessionHistoryValues.append(enabled)
    }

    func saveVoiceInputSessionRetentionPolicy(_ policy: VoiceInputSessionRetentionPolicy) {
        voiceInputSessionRetentionPolicy = policy
        savedVoiceInputSessionRetentionPolicies.append(policy)
    }

    func saveAppLanguage(_ language: AppLanguage) {
        appLanguage = language
        savedAppLanguages.append(language)
    }
}

private final class FakeVoiceInputSessionStore: VoiceInputSessionStoring {
    private(set) var storedSessions: [VoiceInputSessionSnapshot]
    private(set) var savedSessions: [VoiceInputSessionSnapshot] = []
    private(set) var loadLimitRequests: [Int] = []
    private(set) var trimLimitRequests: [Int?] = []
    var loadError: Error?
    var saveError: Error?
    var trimError: Error?

    init(
        storedSessions: [VoiceInputSessionSnapshot] = [],
        loadError: Error? = nil,
        saveError: Error? = nil,
        trimError: Error? = nil
    ) {
        self.storedSessions = storedSessions
        self.loadError = loadError
        self.saveError = saveError
        self.trimError = trimError
    }

    func loadRecentSessions(limit: Int) throws -> [VoiceInputSessionSnapshot] {
        loadLimitRequests.append(limit)
        if let loadError {
            throw loadError
        }
        return Array(storedSessions.prefix(max(0, limit)))
    }

    func save(_ session: VoiceInputSessionSnapshot) throws {
        if let saveError {
            throw saveError
        }
        savedSessions.append(session)
        storedSessions.insert(session, at: 0)
    }

    func trimRecentSessions(limit: Int?) throws {
        trimLimitRequests.append(limit)
        if let trimError {
            throw trimError
        }
        if let limit {
            storedSessions = Array(storedSessions.prefix(limit))
        }
    }
}

@MainActor
private final class FakeTranscriptionCredentialStore: TranscriptionCredentialStoring {
    var snapshot: TranscriptionCredentialSnapshot
    var saveError: Error?
    var deleteError: Error?
    private var storedCredential: TranscriptionCredential?

    init(
        snapshot: TranscriptionCredentialSnapshot = .missing(provider: .volcengine),
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

@MainActor
private final class AsyncTranscriptionCredentialStore: TranscriptionCredentialStoring {
    let syncSnapshot: TranscriptionCredentialSnapshot
    let asyncSnapshot: TranscriptionCredentialSnapshot

    init(
        syncSnapshot: TranscriptionCredentialSnapshot,
        asyncSnapshot: TranscriptionCredentialSnapshot
    ) {
        self.syncSnapshot = syncSnapshot
        self.asyncSnapshot = asyncSnapshot
    }

    func currentSnapshot() -> TranscriptionCredentialSnapshot {
        syncSnapshot
    }

    func loadCurrentSnapshot() async -> TranscriptionCredentialSnapshot {
        asyncSnapshot
    }

    func saveCredential(
        _ credential: TranscriptionCredential,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot {
        .stored(provider: provider, credential: try credential.normalized())
    }

    func deleteCredentials(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredentialSnapshot {
        .missing(provider: provider)
    }

    func credential(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredential? {
        nil
    }
}

@MainActor
private final class SuspendingTranscriptionCredentialStore: TranscriptionCredentialStoring {
    private var continuation: CheckedContinuation<TranscriptionCredentialSnapshot, Never>?
    private(set) var loadCount = 0

    func currentSnapshot() -> TranscriptionCredentialSnapshot {
        .missing(provider: .volcengine)
    }

    func loadCurrentSnapshot() async -> TranscriptionCredentialSnapshot {
        loadCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(_ snapshot: TranscriptionCredentialSnapshot) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }

    func saveCredential(
        _ credential: TranscriptionCredential,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot {
        .stored(provider: provider, credential: try credential.normalized())
    }

    func deleteCredentials(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredentialSnapshot {
        .missing(provider: provider)
    }

    func credential(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredential? {
        nil
    }
}
