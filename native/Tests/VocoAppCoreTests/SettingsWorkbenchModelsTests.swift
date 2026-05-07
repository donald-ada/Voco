import XCTest
@testable import VocoAppCore

final class SettingsWorkbenchModelsTests: XCTestCase {
    func testWorkbenchSectionsStayInApprovedOrder() {
        XCTAssertEqual(
            SettingsWorkbenchSection.allCases,
            [
                .overview,
                .voiceInput,
                .transcription,
                .permissionsAndInput,
                .diagnosticsAndPrivacy
            ]
        )
    }

    func testWorkbenchSectionsExposeUserVisibleCopy() {
        XCTAssertEqual(SettingsWorkbenchSection.overview.title, "总览")
        XCTAssertEqual(SettingsWorkbenchSection.overview.summary, "当前状态")
        XCTAssertEqual(SettingsWorkbenchSection.voiceInput.title, "语音输入")
        XCTAssertEqual(SettingsWorkbenchSection.voiceInput.summary, "快捷键、音频、HUD")
        XCTAssertEqual(SettingsWorkbenchSection.transcription.title, "转写服务")
        XCTAssertEqual(SettingsWorkbenchSection.transcription.summary, "Doubao 和 Keychain")
        XCTAssertEqual(SettingsWorkbenchSection.permissionsAndInput.title, "权限与输入")
        XCTAssertEqual(SettingsWorkbenchSection.permissionsAndInput.summary, "macOS 权限、插入策略")
        XCTAssertEqual(SettingsWorkbenchSection.diagnosticsAndPrivacy.title, "诊断与隐私")
        XCTAssertEqual(SettingsWorkbenchSection.diagnosticsAndPrivacy.summary, "记录、导出、脱敏")
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
            audio: nil,
            transcript: nil,
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "辅助功能权限缺失")
        XCTAssertEqual(snapshot.overview.detail, "Voco 可以录音，但不能稳定插入当前输入框。")
        XCTAssertEqual(snapshot.overview.primaryActionTitle, "打开辅助功能设置")
        XCTAssertEqual(snapshot.status(for: .overview), .needsAttention)
        XCTAssertEqual(snapshot.status(for: .permissionsAndInput), .needsAttention)
        XCTAssertEqual(snapshot.status(for: .voiceInput), .warning)
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
            audio: nil,
            transcript: nil,
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.overview.title, "Doubao 凭证未保存")
        XCTAssertEqual(snapshot.overview.primaryActionTitle, "前往转写服务")
        XCTAssertEqual(snapshot.status(for: .transcription), .needsAttention)
        XCTAssertEqual(snapshot.status(for: .permissionsAndInput), .ok)
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
            audio: nil,
            transcript: nil,
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
            audio: nil,
            transcript: nil,
            injection: nil,
            lastErrorMessage: "server response contains no final text"
        )

        XCTAssertEqual(snapshot.overview.title, "最近一次操作失败")
        XCTAssertEqual(snapshot.overview.primaryActionTitle, "查看诊断与隐私")
    }

    func testMissingSectionStatusFallsBackToNeutral() {
        let snapshot = SettingsWorkbenchSnapshot(
            statusTitle: "就绪",
            overview: SettingsWorkbenchOverviewSnapshot(
                title: "Voco 已就绪",
                detail: "Right Command 可以触发录音、转写和文本输入。",
                primaryActionTitle: "开始测试录音"
            ),
            sectionStatuses: [:],
            recentChain: []
        )

        XCTAssertEqual(snapshot.status(for: .diagnosticsAndPrivacy), .neutral)
    }

    func testRecentChainContainsCommandAudioDoubaoAndInput() {
        let audio = CapturedAudioSnapshot(
            durationSeconds: 2.84,
            sampleRate: 16_000,
            peakAmplitude: 0.67,
            pcm16Samples: [1, 2, 3]
        )
        let transcript = TranscriptSnapshot(
            finalText: "insert text",
            partials: ["insert"],
            providerName: "Doubao",
            latencyMilliseconds: 420
        )
        let injection = TextInjectionSnapshot(
            targetAppName: "Notes",
            strategy: .clipboardFallback,
            succeeded: true,
            detail: "已通过剪贴板回退插入文本并恢复剪贴板。"
        )

        let snapshot = SettingsWorkbenchSnapshot.make(
            statusTitle: "就绪",
            permissions: [
                .microphone(.granted),
                .accessibility(.granted),
            ],
            hotkeyState: .listening,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .ready(providerName: "Doubao"),
            credentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef"),
            audio: audio,
            transcript: transcript,
            injection: injection,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.recentChain.map(\.title), ["Command", "录音", "Doubao", "输入"])
        XCTAssertEqual(snapshot.recentChain[0].detail, "Right Command · 切换录音")
        XCTAssertEqual(snapshot.recentChain[0].status, .ok)
        XCTAssertEqual(snapshot.recentChain[0].actionTitle, "查看详情")
        XCTAssertEqual(snapshot.recentChain[1].detail, "2.84s · 16000 Hz · peak 0.67")
        XCTAssertEqual(snapshot.recentChain[1].status, .ok)
        XCTAssertEqual(snapshot.recentChain[2].detail, "11 字符 · 1 个 partial · 420 ms")
        XCTAssertEqual(snapshot.recentChain[2].status, .ok)
        XCTAssertEqual(snapshot.recentChain[3].detail, "Notes · 剪贴板回退")
        XCTAssertEqual(snapshot.recentChain[3].status, .ok)
        XCTAssertEqual(snapshot.recentChain[3].actionTitle, "查看详情")
    }

    func testRecentChainShowsNeutralFallbacksWithoutRecentArtifacts() {
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
            audio: nil,
            transcript: nil,
            injection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.recentChain[0].detail, "Right Command · 按住录音")
        XCTAssertEqual(snapshot.recentChain[0].status, .warning)
        XCTAssertEqual(snapshot.recentChain[0].actionTitle, "检查快捷键")
        XCTAssertEqual(snapshot.recentChain[0].action, .checkHotkey)
        XCTAssertEqual(snapshot.recentChain[1].detail, "尚无近期录音")
        XCTAssertEqual(snapshot.recentChain[1].status, .neutral)
        XCTAssertEqual(snapshot.recentChain[1].actionTitle, "开始测试录音")
        XCTAssertEqual(snapshot.recentChain[1].action, .startTestRecording)
        XCTAssertEqual(snapshot.recentChain[2].detail, "尚无近期转写")
        XCTAssertEqual(snapshot.recentChain[2].status, .neutral)
        XCTAssertEqual(snapshot.recentChain[2].action, .testTranscription)
        XCTAssertEqual(snapshot.recentChain[3].detail, "尚无近期输入")
        XCTAssertEqual(snapshot.recentChain[3].status, .neutral)
    }

    func testRecentChainMarksDoubaoFailureWithoutTranscript() {
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
            audio: nil,
            transcript: nil,
            injection: nil,
            lastErrorMessage: "server response contains no final text"
        )

        XCTAssertEqual(snapshot.recentChain[2].detail, "server response contains no final text")
        XCTAssertEqual(snapshot.recentChain[2].status, .needsAttention)
        XCTAssertEqual(snapshot.recentChain[2].actionTitle, "前往转写服务")
        XCTAssertEqual(snapshot.recentChain[2].action, .openTranscription)
    }

    func testRecentChainMarksFailedInputAsNeedsAttention() {
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
                .accessibility(.denied),
            ],
            hotkeyState: .permissionNeeded,
            hotkeyBinding: .default,
            hotkeyMode: .toggle,
            asrStatus: .ready(providerName: "Doubao"),
            credentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef"),
            audio: nil,
            transcript: nil,
            injection: injection,
            lastErrorMessage: injection.detail
        )

        XCTAssertEqual(snapshot.recentChain[3].detail, "Notes · 不可用")
        XCTAssertEqual(snapshot.recentChain[3].status, .needsAttention)
        XCTAssertEqual(snapshot.recentChain[3].actionTitle, "修复输入权限")
        XCTAssertEqual(snapshot.recentChain[3].action, .openPermissionsAndInput)
    }
}
