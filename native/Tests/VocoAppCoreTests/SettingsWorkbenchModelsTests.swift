import XCTest
@testable import VocoAppCore

final class SettingsWorkbenchModelsTests: XCTestCase {
    func testWorkbenchSectionsStayInApprovedOrder() {
        XCTAssertEqual(
            SettingsWorkbenchSection.allCases.map(\.rawValue),
            ["overview", "model", "settings"]
        )
    }

    func testWorkbenchSectionsExposeUserVisibleCopy() {
        XCTAssertEqual(
            SettingsWorkbenchSection.allCases.map(\.title),
            ["主页", "模型", "设置"]
        )
        XCTAssertEqual(
            SettingsWorkbenchSection.allCases.map(\.summary),
            ["当前状态", "火山引擎和 Keychain", "快捷键、麦克风、系统"]
        )
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
        XCTAssertEqual(snapshot.overview.primaryActionTitle, "打开辅助功能设置")
        XCTAssertEqual(snapshot.status(for: .overview), .needsAttention)
        XCTAssertEqual(snapshot.status(for: .settings), .needsAttention)
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
        XCTAssertEqual(snapshot.overview.primaryActionTitle, SettingsWorkbenchActionTitle.checkMicrophone)
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
        XCTAssertEqual(snapshot.overview.primaryActionTitle, "前往模型")
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
        XCTAssertEqual(snapshot.overview.primaryActionTitle, "前往模型")
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
        XCTAssertEqual(snapshot.overview.primaryActionTitle, "重新检查")
        XCTAssertEqual(snapshot.status(for: .overview), .needsAttention)
    }

    func testMissingSectionStatusFallsBackToNeutral() {
        let snapshot = SettingsWorkbenchSnapshot(
            statusTitle: "就绪",
            overview: SettingsWorkbenchOverviewSnapshot(
                title: "Voco 已就绪",
                detail: "Right Command 可以触发录音、转写和文本输入。",
                primaryActionTitle: "开始测试录音"
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
        XCTAssertEqual(snapshot.overview.primaryActionTitle, "前往设置")
        XCTAssertEqual(snapshot.status(for: .settings), .needsAttention)
    }
}
