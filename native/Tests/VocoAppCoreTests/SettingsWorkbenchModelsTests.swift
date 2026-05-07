import XCTest
@testable import VocoAppCore

final class SettingsWorkbenchModelsTests: XCTestCase {
    func testWorkbenchSectionsStayInApprovedOrder() {
        XCTAssertEqual(
            SettingsWorkbenchSection.allCases.map(\.rawValue),
            ["overview", "settings", "transcription"]
        )
    }

    func testWorkbenchSectionsExposeUserVisibleCopy() {
        XCTAssertEqual(
            SettingsWorkbenchSection.allCases.map(\.title),
            ["总览", "设置", "转写服务"]
        )
        XCTAssertEqual(
            SettingsWorkbenchSection.allCases.map(\.summary),
            ["当前状态", "快捷键、模式、麦克风、权限", "Doubao 和 Keychain"]
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
            asrStatus: .ready(providerName: "Doubao"),
            credentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "辅助功能权限缺失")
        XCTAssertEqual(snapshot.overview.detail, "Voco 可以录音，但不能稳定插入当前输入框。")
        XCTAssertEqual(snapshot.overview.primaryActionTitle, "打开辅助功能设置")
        XCTAssertEqual(snapshot.status(for: .overview), .needsAttention)
        XCTAssertEqual(snapshot.status(for: .settings), .needsAttention)
    }

    func testMissingDoubaoCredentialBecomesOverviewBlockerWhenPermissionsAreReady() {
        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "就绪",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .authenticationRequired(providerName: "Doubao"),
            credentials: .missing(provider: .doubao),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "Doubao 凭证未保存")
        XCTAssertEqual(snapshot.overview.primaryActionTitle, "前往转写服务")
        XCTAssertEqual(snapshot.status(for: .transcription), .needsAttention)
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
            asrStatus: .offline(providerName: "Doubao"),
            credentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "Doubao 离线")
        XCTAssertEqual(snapshot.overview.detail, "转写服务暂不可用，稍后可重试。")
        XCTAssertEqual(snapshot.overview.primaryActionTitle, "前往转写服务")
        XCTAssertEqual(snapshot.status(for: .overview), .needsAttention)
        XCTAssertEqual(snapshot.status(for: .transcription), .needsAttention)
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
            asrStatus: .ready(providerName: "Doubao"),
            credentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef"),
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
            asrStatus: .ready(providerName: "Doubao"),
            credentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef"),
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
            asrStatus: .failed(providerName: "Doubao", message: "server response contains no final text"),
            credentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef"),
            injection: nil,
            lastErrorMessage: "server response contains no final text"
        )

        XCTAssertEqual(snapshot.overview.title, "Doubao 转写失败")
        XCTAssertEqual(snapshot.status(for: .overview), .needsAttention)
        XCTAssertEqual(snapshot.status(for: .transcription), .needsAttention)
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
            asrStatus: .ready(providerName: "Doubao"),
            credentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef"),
            injection: injection,
            lastErrorMessage: injection.detail
        )

        XCTAssertEqual(snapshot.overview.title, "文本输入失败")
        XCTAssertEqual(snapshot.overview.primaryActionTitle, "前往设置")
        XCTAssertEqual(snapshot.status(for: .settings), .needsAttention)
    }
}
