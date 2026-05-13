import XCTest
@testable import VocoAppCore

final class SettingsWorkbenchModelsTests: XCTestCase {
    func testWorkbenchSectionsStayInApprovedOrder() {
        XCTAssertEqual(
            SettingsWorkbenchSection.allCases.map(\.rawValue),
            ["overview", "model", "skills", "statistics", "settings"]
        )
    }

    func testWorkbenchSectionsIncludeSkillsInApprovedOrder() {
        XCTAssertEqual(SettingsWorkbenchSection.allCases, [.overview, .model, .skills, .statistics, .settings])
    }

    func testWorkbenchSectionsExposeUserVisibleCopy() {
        XCTAssertEqual(
            SettingsWorkbenchSection.allCases.map(\.title),
            ["主页", "模型", "技能", "统计", "设置"]
        )
        XCTAssertEqual(
            SettingsWorkbenchSection.allCases.map(\.summary),
            ["当前状态", "火山引擎和 Keychain", "转写清理和动作", "使用趋势和分布", "快捷键、麦克风、系统"]
        )
    }

    func testWorkbenchSectionsExposeEnglishCopy() {
        let strings = VocoStrings(language: .en)

        XCTAssertEqual(
            SettingsWorkbenchSection.allCases.map { $0.title(strings: strings) },
            ["Home", "Model", "Skills", "Statistics", "Settings"]
        )
        XCTAssertEqual(
            SettingsWorkbenchSection.allCases.map { $0.summary(strings: strings) },
            ["Current status", "Volcengine and Keychain", "Transcript cleanup and actions", "Usage trends and distribution", "Hotkey, microphone, and system"]
        )
    }

    func testSkillsSectionUsesEnglishCopy() {
        let strings = VocoStrings(language: .en)

        XCTAssertEqual(SettingsWorkbenchSection.skills.title(strings: strings), "Skills")
        XCTAssertEqual(SettingsWorkbenchSection.skills.summary(strings: strings), "Transcript cleanup and actions")
    }

    func testStatusToneMapsToSystemImages() {
        XCTAssertEqual(SettingsWorkbenchSectionStatus.ok.systemImage, "circle.fill")
        XCTAssertEqual(SettingsWorkbenchSectionStatus.needsAttention.systemImage, "circle.fill")
        XCTAssertEqual(SettingsWorkbenchSectionStatus.warning.systemImage, "circle.fill")
        XCTAssertEqual(SettingsWorkbenchSectionStatus.neutral.systemImage, "circle.fill")
    }

    func testPermissionProblemTakesOverviewPriority() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "需要权限",
            permissions: [
                .microphone(.granted),
                .accessibility(.denied),
            ],
            hotkeyState: .permissionNeeded,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .ready(providerName: "火山引擎"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "辅助功能权限缺失")
        XCTAssertEqual(snapshot.overview.detail, "Voco 可以录音，但不能稳定插入当前输入框。")
        XCTAssertEqual(snapshot.overview.primaryActionID, SettingsWorkbenchActionID.openAccessibilitySettings)
        XCTAssertEqual(snapshot.overview.primaryActionDisplayTitle, "打开辅助功能设置")
        XCTAssertEqual(snapshot.status(for: .overview), .needsAttention)
        XCTAssertEqual(snapshot.status(for: .settings), .needsAttention)
    }

    func testAccessibilityPermissionProblemUsesStableActionAndEnglishDisplayTitle() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            strings: VocoStrings(language: .en),
            statusTitle: "Permission Needed",
            permissions: [
                .microphone(.granted),
                .accessibility(.denied),
            ],
            hotkeyState: .permissionNeeded,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .ready(providerName: "Volcengine"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "Accessibility permission missing")
        XCTAssertEqual(snapshot.overview.detail, "Voco can record, but cannot reliably insert into the current text field.")
        XCTAssertEqual(snapshot.overview.primaryActionID, SettingsWorkbenchActionID.openAccessibilitySettings)
        XCTAssertEqual(snapshot.overview.primaryActionDisplayTitle, "Open Accessibility Settings")
    }

    func testEnglishMissingCredentialsLocalizesOverviewAndHomeIssue() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            strings: VocoStrings(language: .en),
            statusTitle: "Ready",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .authenticationRequired(providerName: "Volcengine"),
            credentials: .missing(provider: .volcengine),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "Volcengine credentials not saved")
        XCTAssertEqual(snapshot.overview.detail, "No Volcengine credentials are saved in Keychain.")
        XCTAssertEqual(snapshot.homeIssueItems.map(\.title), ["Volcengine credentials not saved"])
        XCTAssertEqual(snapshot.homeIssueItems.map(\.detail), ["No Volcengine credentials are saved in Keychain."])
    }

    func testReadyLocalModelDoesNotRequireVolcengineCredentials() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "就绪",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .ready(providerName: "本地模型"),
            credentials: .missing(provider: .volcengine),
            injection: nil,
            lastErrorMessage: nil,
            modelSelection: TranscriptionModelSelection(providerID: .localRecommended),
            localModelStatus: .ready
        )

        XCTAssertEqual(snapshot.status(for: .model), .ok)
        XCTAssertEqual(snapshot.homeIssueItems, [])
    }

    func testNotDownloadedLocalModelNeedsAttention() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "就绪",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .ready(providerName: "本地模型"),
            credentials: .missing(provider: .volcengine),
            injection: nil,
            lastErrorMessage: nil,
            modelSelection: TranscriptionModelSelection(providerID: .localRecommended),
            localModelStatus: .notDownloaded
        )

        XCTAssertEqual(snapshot.status(for: .model), .needsAttention)
        XCTAssertEqual(snapshot.overview.primaryActionID, SettingsWorkbenchActionID.openModel)
        XCTAssertEqual(snapshot.homeIssueItems.map(\.detail), ["本地模型未下载。"])
    }

    func testEnglishASROfflineLocalizesOverviewCopy() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            strings: VocoStrings(language: .en),
            statusTitle: "Ready",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .offline(providerName: "Volcengine"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "Volcengine offline")
        XCTAssertEqual(snapshot.overview.detail, "The model is temporarily unavailable. Try again later.")
    }

    func testEnglishASROfflineNormalizesChineseProviderNameInOverviewAndHomeIssue() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            strings: VocoStrings(language: .en),
            statusTitle: "Ready",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .offline(providerName: "火山引擎"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "Volcengine offline")
        XCTAssertEqual(snapshot.overview.detail, "The model is temporarily unavailable. Try again later.")
        XCTAssertEqual(snapshot.homeIssueItems.map(\.title), ["Volcengine offline"])
        XCTAssertEqual(snapshot.homeIssueItems.map(\.detail), ["The model is temporarily unavailable. Try again later."])
    }

    func testEnglishFailedInjectionLocalizesOverviewTitleAndPreservesDetail() {
        let injection = TextInjectionSnapshot(
            targetAppName: "Notes",
            strategy: .unavailable,
            succeeded: false,
            detail: "Accessibility permission is required."
        )

        let snapshot = SettingsWorkbenchSnapshot.make(
            strings: VocoStrings(language: .en),
            statusTitle: "Error",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .ready(providerName: "Volcengine"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: injection,
            lastErrorMessage: injection.detail
        )

        XCTAssertEqual(snapshot.overview.title, "Text input failed")
        XCTAssertEqual(snapshot.overview.detail, "Accessibility permission is required.")
        XCTAssertEqual(snapshot.homeIssueItems.map(\.title), ["Text input failed"])
        XCTAssertEqual(snapshot.homeIssueItems.map(\.detail), ["Accessibility permission is required."])
    }

    func testEnglishRecentRuntimeErrorLocalizesOverviewTitleAndPreservesDetail() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            strings: VocoStrings(language: .en),
            statusTitle: "Error",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .ready(providerName: "Volcengine"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: "server response contains no final text"
        )

        XCTAssertEqual(snapshot.overview.title, "Last operation failed")
        XCTAssertEqual(snapshot.overview.detail, "server response contains no final text")
        XCTAssertEqual(snapshot.homeIssueItems.map(\.title), ["Last operation failed"])
        XCTAssertEqual(snapshot.homeIssueItems.map(\.detail), ["server response contains no final text"])
    }

    func testHomeIssueItemsListEveryProblemThatNeedsResolution() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "需要权限",
            permissions: [
                .microphone(.denied),
                .accessibility(.denied),
            ],
            hotkeyState: .permissionNeeded,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .authenticationRequired(providerName: "火山引擎"),
            credentials: .missing(provider: .volcengine),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(
            snapshot.homeIssueItems.map(\.title),
            ["麦克风权限缺失", "辅助功能权限缺失", "火山引擎凭证未保存"]
        )
    }

    func testReadyHomeHasNoIssueItems() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "就绪",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .ready(providerName: "火山引擎"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertTrue(snapshot.homeIssueItems.isEmpty)
    }

    func testSettingsWorkbenchSnapshotUsesEnglishOverviewCopy() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            strings: VocoStrings(language: .en),
            statusTitle: "Ready",
            permissions: [.microphone(.granted), .accessibility(.granted)],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .ready(providerName: "Volcengine"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "Voco is ready")
        XCTAssertEqual(snapshot.overview.primaryActionID, SettingsWorkbenchActionID.startTestRecording)
        XCTAssertEqual(snapshot.overview.primaryActionDisplayTitle, "Start Test Recording")
        XCTAssertEqual(snapshot.overview.secondaryActionID, SettingsWorkbenchActionID.refresh)
        XCTAssertEqual(snapshot.overview.secondaryActionDisplayTitle, "Recheck")
    }

    func testMicrophonePermissionProblemUsesPromptRecoveryAction() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "需要权限",
            permissions: [
                .microphone(.notDetermined),
                .accessibility(.granted),
            ],
            hotkeyState: .permissionNeeded,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .ready(providerName: "火山引擎"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "麦克风权限缺失")
        XCTAssertEqual(snapshot.overview.primaryActionID, SettingsWorkbenchActionID.checkMicrophone)
    }

    func testMissingVolcengineCredentialBecomesOverviewBlockerWhenPermissionsAreReady() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "就绪",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .authenticationRequired(providerName: "火山引擎"),
            credentials: .missing(provider: .volcengine),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "火山引擎凭证未保存")
        XCTAssertEqual(snapshot.overview.primaryActionID, SettingsWorkbenchActionID.openModel)
        XCTAssertEqual(snapshot.overview.primaryActionDisplayTitle, "前往模型")
        XCTAssertEqual(snapshot.status(for: .model), .needsAttention)
        XCTAssertEqual(snapshot.status(for: .settings), .ok)
    }

    func testASRProviderProblemBecomesOverviewBlockerWhenCredentialExists() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "就绪",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .offline(providerName: "火山引擎"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "火山引擎离线")
        XCTAssertEqual(snapshot.overview.detail, "模型暂不可用，稍后可重试。")
        XCTAssertEqual(snapshot.overview.primaryActionID, SettingsWorkbenchActionID.openModel)
        XCTAssertEqual(snapshot.overview.primaryActionDisplayTitle, "前往模型")
        XCTAssertEqual(snapshot.status(for: .overview), .needsAttention)
        XCTAssertEqual(snapshot.status(for: .model), .needsAttention)
    }

    func testRecentRuntimeErrorKeepsRecoveryInsideSettingsWorkbench() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "错误",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .ready(providerName: "火山引擎"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: "server response contains no final text"
        )

        XCTAssertEqual(snapshot.overview.title, "最近一次操作失败")
        XCTAssertEqual(snapshot.overview.primaryActionID, SettingsWorkbenchActionID.refresh)
        XCTAssertEqual(snapshot.overview.primaryActionDisplayTitle, "重新检查")
        XCTAssertEqual(snapshot.status(for: .overview), .needsAttention)
    }

    func testMissingSectionStatusFallsBackToNeutral() {
        let snapshot = SettingsWorkbenchSnapshot(
            statusTitle: "就绪",
            overview: SettingsWorkbenchOverviewSnapshot(
                title: "Voco 已就绪",
                detail: "Right Command 可以触发录音、转写和文本输入。",
                primaryActionID: SettingsWorkbenchActionID.startTestRecording,
                primaryActionDisplayTitle: "开始测试录音",
                secondaryActionDisplayTitle: "重新检查"
            ),
            sectionStatuses: [:]
        )

        XCTAssertEqual(snapshot.status(for: .settings), .neutral)
    }

    func testSettingsStatusWarnsWhenHotkeyIsInactive() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "需要快捷键",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .inactive,
            hotkeyBinding: .default,
            hotkeyMode: .pressAndHold,
            asrStatus: .ready(providerName: "火山引擎"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.status(for: .settings), .warning)
    }

    func testTranscriptionFailureMarksOverviewAndTranscription() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "错误",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .failed(providerName: "火山引擎", message: "server response contains no final text"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: "server response contains no final text"
        )

        XCTAssertEqual(snapshot.overview.title, "火山引擎转写失败")
        XCTAssertEqual(snapshot.status(for: .overview), .needsAttention)
        XCTAssertEqual(snapshot.status(for: .model), .needsAttention)
    }

    func testFailedInputRoutesRecoveryToSettings() {
        let injection = TextInjectionSnapshot(
            targetAppName: "Notes",
            strategy: .unavailable,
            succeeded: false,
            detail: "无法插入文本：请先在系统设置中允许 Voco 使用辅助功能。"
        )

        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "错误",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .ready(providerName: "火山引擎"),
            credentials: .stored(provider: .volcengine, apiKey: "sk-test-abcdef"),
            injection: injection,
            lastErrorMessage: injection.detail
        )

        XCTAssertEqual(snapshot.overview.title, "文本输入失败")
        XCTAssertEqual(snapshot.overview.primaryActionID, SettingsWorkbenchActionID.openSettings)
        XCTAssertEqual(snapshot.overview.primaryActionDisplayTitle, "前往设置")
        XCTAssertEqual(snapshot.status(for: .settings), .needsAttention)
    }
}
