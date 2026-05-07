# Voco Settings Workbench Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the native SwiftUI settings window into the approved A workbench design: a task recovery console with 5 real sidebar sections, state dots, voice-input flow preview, and recent voice-input chain diagnostics.

**Architecture:** Add a small VocoAppCore workbench view model layer that derives settings navigation, blocking status, and chain diagnostics from existing coordinator snapshots. Then refactor `SettingsView` into a selection-driven `NavigationSplitView` that renders the new 5 task sections while preserving existing credential, permission, launch-at-login, and diagnostic actions.

**Tech Stack:** Swift 6, SwiftUI, XCTest, existing VocoAppCore model patterns, existing macOS Settings window presenter.

---

## File Structure

Create:

- `native/Sources/VocoAppCore/SettingsWorkbenchModels.swift`
  - Owns the new 5-section settings workbench model, section status, overview recovery action metadata, and recent chain step snapshots.
- `native/Tests/VocoAppCoreTests/SettingsWorkbenchModelsTests.swift`
  - Tests section order, titles, summaries, status derivation, overview blocking priority, and recent chain step composition.

Modify:

- `native/Sources/VocoAppCore/AppCoordinator.swift`
  - Adds `settingsWorkbenchSnapshot` computed property using current app state.
- `native/Sources/VocoApp/SettingsView.swift`
  - Replaces the static 8-section long scroll with a 5-section selection-driven workbench UI.
  - Keeps existing credential input state and existing action methods.
  - Extracts small subviews inside the file for the first pass to keep the patch scoped.
- `native/Tests/VocoAppCoreTests/SettingsSectionTests.swift`
  - Keep existing tests unchanged unless compiler warnings require updates. The old `SettingsSection` remains valid.

Do not modify:

- `native/Sources/VocoApp/OnboardingView.swift`
- `native/Sources/VocoApp/VocoNativeApp.swift`
- `native/Sources/VocoApp/HUDOverlayView.swift`
- `docs/prototypes/voco-settings-redesign.html`

---

### Task 1: Add Workbench Model Tests

**Files:**

- Create: `native/Tests/VocoAppCoreTests/SettingsWorkbenchModelsTests.swift`

- [ ] **Step 1: Write failing tests for section metadata and order**

Create `native/Tests/VocoAppCoreTests/SettingsWorkbenchModelsTests.swift` with:

```swift
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
        XCTAssertEqual(SettingsWorkbenchSection.overview.summary, "状态和下一步")
        XCTAssertEqual(SettingsWorkbenchSection.voiceInput.title, "语音输入")
        XCTAssertEqual(SettingsWorkbenchSection.voiceInput.summary, "快捷键、音频、HUD")
        XCTAssertEqual(SettingsWorkbenchSection.transcription.title, "转写服务")
        XCTAssertEqual(SettingsWorkbenchSection.transcription.summary, "Doubao 和 Keychain")
        XCTAssertEqual(SettingsWorkbenchSection.permissionsAndInput.title, "权限与输入")
        XCTAssertEqual(SettingsWorkbenchSection.permissionsAndInput.summary, "macOS 权限、插入策略")
        XCTAssertEqual(SettingsWorkbenchSection.diagnosticsAndPrivacy.title, "诊断与隐私")
        XCTAssertEqual(SettingsWorkbenchSection.diagnosticsAndPrivacy.summary, "最近链路、导出、脱敏")
    }

    func testStatusToneMapsToSystemImages() {
        XCTAssertEqual(SettingsWorkbenchSectionStatus.ok.systemImage, "circle.fill")
        XCTAssertEqual(SettingsWorkbenchSectionStatus.needsAttention.systemImage, "circle.fill")
        XCTAssertEqual(SettingsWorkbenchSectionStatus.warning.systemImage, "circle.fill")
        XCTAssertEqual(SettingsWorkbenchSectionStatus.neutral.systemImage, "circle.fill")
    }
}
```

- [ ] **Step 2: Run tests to verify model is missing**

Run:

```bash
swift test --package-path native --filter SettingsWorkbenchModelsTests
```

Expected: FAIL to compile with errors like `cannot find 'SettingsWorkbenchSection' in scope`.

- [ ] **Step 3: Add minimal model definitions**

Create `native/Sources/VocoAppCore/SettingsWorkbenchModels.swift`:

```swift
import Foundation

public enum SettingsWorkbenchSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case voiceInput
    case transcription
    case permissionsAndInput
    case diagnosticsAndPrivacy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview:
            "总览"
        case .voiceInput:
            "语音输入"
        case .transcription:
            "转写服务"
        case .permissionsAndInput:
            "权限与输入"
        case .diagnosticsAndPrivacy:
            "诊断与隐私"
        }
    }

    public var summary: String {
        switch self {
        case .overview:
            "状态和下一步"
        case .voiceInput:
            "快捷键、音频、HUD"
        case .transcription:
            "Doubao 和 Keychain"
        case .permissionsAndInput:
            "macOS 权限、插入策略"
        case .diagnosticsAndPrivacy:
            "最近链路、导出、脱敏"
        }
    }
}

public enum SettingsWorkbenchSectionStatus: Equatable, Sendable {
    case ok
    case needsAttention
    case warning
    case neutral

    public var systemImage: String {
        "circle.fill"
    }
}
```

- [ ] **Step 4: Run tests to verify metadata passes**

Run:

```bash
swift test --package-path native --filter SettingsWorkbenchModelsTests
```

Expected: PASS.

---

### Task 2: Derive Workbench Snapshot State

**Files:**

- Modify: `native/Tests/VocoAppCoreTests/SettingsWorkbenchModelsTests.swift`
- Modify: `native/Sources/VocoAppCore/SettingsWorkbenchModels.swift`
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`

- [ ] **Step 1: Add failing tests for overview blocking priority**

Append to `SettingsWorkbenchModelsTests`:

```swift
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
        XCTAssertEqual(snapshot.status(for: .permissionsAndInput), .warning)
    }
```

- [ ] **Step 2: Run tests to verify snapshot type is missing**

Run:

```bash
swift test --package-path native --filter SettingsWorkbenchModelsTests
```

Expected: FAIL to compile with errors like `cannot find 'SettingsWorkbenchSnapshot' in scope`.

- [ ] **Step 3: Implement overview snapshot and section status derivation**

Append to `SettingsWorkbenchModels.swift`:

```swift
public struct SettingsWorkbenchOverviewSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let primaryActionTitle: String
    public let secondaryActionTitle: String

    public init(
        title: String,
        detail: String,
        primaryActionTitle: String,
        secondaryActionTitle: String = "重新检查"
    ) {
        self.title = title
        self.detail = detail
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
    }
}

public struct SettingsWorkbenchSnapshot: Equatable, Sendable {
    public let statusTitle: String
    public let overview: SettingsWorkbenchOverviewSnapshot
    public let sectionStatuses: [SettingsWorkbenchSection: SettingsWorkbenchSectionStatus]

    public init(
        statusTitle: String,
        overview: SettingsWorkbenchOverviewSnapshot,
        sectionStatuses: [SettingsWorkbenchSection: SettingsWorkbenchSectionStatus]
    ) {
        self.statusTitle = statusTitle
        self.overview = overview
        self.sectionStatuses = sectionStatuses
    }

    public func status(for section: SettingsWorkbenchSection) -> SettingsWorkbenchSectionStatus {
        sectionStatuses[section] ?? .neutral
    }

    public static func make(
        statusTitle: String,
        permissions: [PermissionSnapshot],
        hotkeyState: HotkeyRuntimeState,
        hotkeyBinding: HotkeyBinding,
        hotkeyMode: HotkeyMode,
        asrStatus: TranscriptionProviderStatus,
        credentials: TranscriptionCredentialSnapshot,
        audio: CapturedAudioSnapshot?,
        transcript: TranscriptSnapshot?,
        injection: TextInjectionSnapshot?,
        lastErrorMessage: String?
    ) -> SettingsWorkbenchSnapshot {
        let requiredMissing = permissions.first { permission in
            permission.isRequired && !permission.state.isGranted
        }
        let optionalPermissionProblem = permissions.contains { permission in
            !permission.isRequired && !permission.state.isGranted
        }

        let overview: SettingsWorkbenchOverviewSnapshot
        if let requiredMissing {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: "\(requiredMissing.kind.title)权限缺失",
                detail: requiredMissing.kind == .accessibility
                    ? "Voco 可以录音，但不能稳定插入当前输入框。"
                    : "\(requiredMissing.kind.title)权限缺失，语音输入链路无法完成。",
                primaryActionTitle: requiredMissing.kind.recoveryActionTitle
            )
        } else if !credentials.hasCredential || credentials.lastErrorMessage != nil {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: credentials.lastErrorMessage == nil ? "Doubao 凭证未保存" : "Doubao 凭证读取失败",
                detail: credentials.storageDetail,
                primaryActionTitle: "前往转写服务"
            )
        } else if case .failed(_, let message) = asrStatus {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: "Doubao 转写失败",
                detail: message,
                primaryActionTitle: "前往转写服务"
            )
        } else if let injection, !injection.succeeded {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: "文本输入失败",
                detail: injection.detail,
                primaryActionTitle: "前往权限与输入"
            )
        } else if let lastErrorMessage, !lastErrorMessage.isEmpty {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: "最近一次操作失败",
                detail: lastErrorMessage,
                primaryActionTitle: "打开诊断"
            )
        } else {
            overview = SettingsWorkbenchOverviewSnapshot(
                title: "Voco 已就绪",
                detail: "Right Command 可以触发录音、转写和文本输入。",
                primaryActionTitle: "开始测试录音"
            )
        }

        let hasRequiredPermissionProblem = requiredMissing != nil
        let transcriptionNeedsAttention = !credentials.hasCredential ||
            credentials.lastErrorMessage != nil ||
            asrStatus.isWorkbenchAttention
        let inputNeedsAttention = injection.map { !$0.succeeded } ?? false

        return SettingsWorkbenchSnapshot(
            statusTitle: statusTitle,
            overview: overview,
            sectionStatuses: [
                .overview: hasRequiredPermissionProblem || transcriptionNeedsAttention || inputNeedsAttention
                    ? .needsAttention
                    : .ok,
                .voiceInput: hotkeyState == .listening ? .ok : .warning,
                .transcription: transcriptionNeedsAttention ? .needsAttention : .ok,
                .permissionsAndInput: hasRequiredPermissionProblem
                    ? .needsAttention
                    : (optionalPermissionProblem || inputNeedsAttention ? .warning : .ok),
                .diagnosticsAndPrivacy: lastErrorMessage == nil ? .neutral : .needsAttention
            ]
        )
    }
}

private extension TranscriptionProviderStatus {
    var isWorkbenchAttention: Bool {
        switch self {
        case .ready:
            false
        case .notConfigured, .authenticationRequired, .offline, .failed:
            true
        }
    }
}
```

- [ ] **Step 4: Add AppCoordinator computed snapshot**

In `native/Sources/VocoAppCore/AppCoordinator.swift`, after `diagnosticsSnapshot`, add:

```swift
    public var settingsWorkbenchSnapshot: SettingsWorkbenchSnapshot {
        SettingsWorkbenchSnapshot.make(
            statusTitle: snapshot.title,
            permissions: permissions,
            hotkeyState: hotkeyRuntimeState,
            hotkeyBinding: hotkeyBinding,
            hotkeyMode: hotkeyMode,
            asrStatus: transcriptionProviderStatus,
            credentials: transcriptionCredentials,
            audio: lastAudio,
            transcript: lastTranscript,
            injection: lastInjection,
            lastErrorMessage: lastErrorMessage
        )
    }
```

- [ ] **Step 5: Run targeted tests**

Run:

```bash
swift test --package-path native --filter SettingsWorkbenchModelsTests
```

Expected: PASS.

---

### Task 3: Add Recent Voice Input Chain Model

**Files:**

- Modify: `native/Tests/VocoAppCoreTests/SettingsWorkbenchModelsTests.swift`
- Modify: `native/Sources/VocoAppCore/SettingsWorkbenchModels.swift`

- [ ] **Step 1: Add failing tests for the four-step chain**

Append to `SettingsWorkbenchModelsTests`:

```swift
    func testRecentChainContainsCommandAudioDoubaoAndInput() {
        let audio = CapturedAudioSnapshot(
            durationSeconds: 2.84,
            sampleRate: 16_000,
            peakAmplitude: 0.67,
            pcm16Samples: [1, 2, 3]
        )
        let transcript = TranscriptSnapshot(
            finalText: "把这段内容插入当前输入框",
            partials: ["把这段内容"],
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
        XCTAssertEqual(snapshot.recentChain[1].detail, "2.84s · 16000 Hz · peak 0.67")
        XCTAssertEqual(snapshot.recentChain[2].detail, "24 字符 · 1 个 partial · 420 ms")
        XCTAssertEqual(snapshot.recentChain[3].detail, "Notes · 剪贴板回退")
        XCTAssertEqual(snapshot.recentChain[3].status, .ok)
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

        XCTAssertEqual(snapshot.recentChain[3].status, .needsAttention)
        XCTAssertEqual(snapshot.recentChain[3].actionTitle, "修复输入权限")
    }
```

- [ ] **Step 2: Run tests to verify chain model is missing**

Run:

```bash
swift test --package-path native --filter SettingsWorkbenchModelsTests
```

Expected: FAIL to compile with `value of type 'SettingsWorkbenchSnapshot' has no member 'recentChain'`.

- [ ] **Step 3: Implement chain step model**

In `SettingsWorkbenchModels.swift`, add before `SettingsWorkbenchSnapshot`:

```swift
public struct VoiceInputChainStepSnapshot: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let status: SettingsWorkbenchSectionStatus
    public let actionTitle: String

    public init(
        id: String,
        title: String,
        detail: String,
        status: SettingsWorkbenchSectionStatus,
        actionTitle: String
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.actionTitle = actionTitle
    }
}
```

Update `SettingsWorkbenchSnapshot` to include `recentChain`:

```swift
    public let recentChain: [VoiceInputChainStepSnapshot]
```

Update its initializer:

```swift
        recentChain: [VoiceInputChainStepSnapshot]
```

Assign:

```swift
        self.recentChain = recentChain
```

In `make(...)`, before `return SettingsWorkbenchSnapshot(...)`, add:

```swift
        let recentChain = makeRecentChain(
            hotkeyState: hotkeyState,
            hotkeyBinding: hotkeyBinding,
            hotkeyMode: hotkeyMode,
            audio: audio,
            transcript: transcript,
            injection: injection
        )
```

Pass it to the initializer:

```swift
            recentChain: recentChain
```

Add private helper methods inside `SettingsWorkbenchSnapshot`:

```swift
    private static func makeRecentChain(
        hotkeyState: HotkeyRuntimeState,
        hotkeyBinding: HotkeyBinding,
        hotkeyMode: HotkeyMode,
        audio: CapturedAudioSnapshot?,
        transcript: TranscriptSnapshot?,
        injection: TextInjectionSnapshot?
    ) -> [VoiceInputChainStepSnapshot] {
        [
            VoiceInputChainStepSnapshot(
                id: "command",
                title: "Command",
                detail: "\(hotkeyBinding.displayName) · \(hotkeyMode.title)",
                status: hotkeyState == .listening ? .ok : .warning,
                actionTitle: hotkeyState == .listening ? "查看详情" : "检查快捷键"
            ),
            VoiceInputChainStepSnapshot(
                id: "audio",
                title: "录音",
                detail: audio.map(audioDetail) ?? "尚无近期录音",
                status: audio == nil ? .neutral : .ok,
                actionTitle: audio == nil ? "开始测试录音" : "查看详情"
            ),
            VoiceInputChainStepSnapshot(
                id: "doubao",
                title: "Doubao",
                detail: transcript.map(transcriptDetail) ?? "尚无近期转写",
                status: transcript == nil ? .neutral : .ok,
                actionTitle: transcript == nil ? "测试连接" : "查看详情"
            ),
            VoiceInputChainStepSnapshot(
                id: "input",
                title: "输入",
                detail: injection.map(inputDetail) ?? "尚无近期输入",
                status: injection.map { $0.succeeded ? .ok : .needsAttention } ?? .neutral,
                actionTitle: injection.map { $0.succeeded ? "查看详情" : "修复输入权限" } ?? "查看详情"
            )
        ]
    }

    private static func audioDetail(_ audio: CapturedAudioSnapshot) -> String {
        String(format: "%.2fs · %.0f Hz · peak %.2f", audio.durationSeconds, audio.sampleRate, audio.peakAmplitude)
    }

    private static func transcriptDetail(_ transcript: TranscriptSnapshot) -> String {
        let latency = transcript.latencyMilliseconds.map { " · \($0) ms" } ?? ""
        return "\(transcript.finalText.count) 字符 · \(transcript.partials.count) 个 partial\(latency)"
    }

    private static func inputDetail(_ injection: TextInjectionSnapshot) -> String {
        "\(injection.targetAppName ?? "当前 App") · \(injection.strategy.title)"
    }
```

- [ ] **Step 4: Run chain tests**

Run:

```bash
swift test --package-path native --filter SettingsWorkbenchModelsTests
```

Expected: PASS.

---

### Task 4: Refactor SettingsView Root and Sidebar

**Files:**

- Modify: `native/Sources/VocoApp/SettingsView.swift`

- [ ] **Step 1: Add selection state and replace old sidebar list**

In `SettingsView`, add state:

```swift
    @State private var selectedSection: SettingsWorkbenchSection = .overview
```

Replace the current `NavigationSplitView` body with:

```swift
    var body: some View {
        NavigationSplitView {
            SettingsWorkbenchSidebar(
                selectedSection: $selectedSection,
                snapshot: coordinator.settingsWorkbenchSnapshot
            )
            .navigationTitle("Voco")
        } detail: {
            ScrollView {
                detailContent(for: selectedSection)
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
            }
            .frame(minWidth: 560, minHeight: 420, alignment: .topLeading)
        }
        .onAppear {
            coordinator.prepareForSettingsPresentation()
            syncSelectedDoubaoCredentialMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            coordinator.refreshLegacyInstall()
            coordinator.refreshPermissions()
            coordinator.refreshTranscriptionCredentials()
            syncSelectedDoubaoCredentialMode()
        }
    }
```

Add detail routing inside `SettingsView`:

```swift
    @ViewBuilder
    private func detailContent(for section: SettingsWorkbenchSection) -> some View {
        switch section {
        case .overview:
            overviewSection
        case .voiceInput:
            voiceInputSection
        case .transcription:
            transcriptionWorkbenchSection
        case .permissionsAndInput:
            permissionsAndInputSection
        case .diagnosticsAndPrivacy:
            diagnosticsAndPrivacySection
        }
    }
```

- [ ] **Step 2: Add sidebar subviews**

At the end of `SettingsView.swift`, after `SettingsView`, add:

```swift
private struct SettingsWorkbenchSidebar: View {
    @Binding var selectedSection: SettingsWorkbenchSection
    let snapshot: SettingsWorkbenchSnapshot

    var body: some View {
        List(selection: $selectedSection) {
            ForEach(SettingsWorkbenchSection.allCases) { section in
                SettingsWorkbenchSidebarRow(
                    section: section,
                    status: snapshot.status(for: section)
                )
                .tag(section)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SettingsWorkbenchSidebarRow: View {
    let section: SettingsWorkbenchSection
    let status: SettingsWorkbenchSectionStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: status.systemImage)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .lineLimit(1)

                Text(section.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var statusColor: Color {
        switch status {
        case .ok:
            .green
        case .needsAttention:
            .red
        case .warning:
            .yellow
        case .neutral:
            .secondary
        }
    }
}
```

- [ ] **Step 3: Add temporary placeholder detail sections**

Inside `SettingsView`, add these temporary computed views so the file compiles before Task 5:

```swift
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voco 设置")
                .font(.title2)
                .fontWeight(.semibold)
            statusRow
            legacyInstallSection
        }
    }

    private var voiceInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            hotkeySection
            audioSettingsSection
            hudSettingsSection
        }
    }

    private var transcriptionWorkbenchSection: some View {
        transcriptionSection
    }

    private var permissionsAndInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            permissionsSection
            injectionSettingsSection
        }
    }

    private var diagnosticsAndPrivacySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            privacySettingsSection
            recordingDiagnosticsSection
        }
    }
```

- [ ] **Step 4: Build tests to catch compile issues**

Run:

```bash
swift test --package-path native --filter SettingsWorkbenchModelsTests
```

Expected: PASS and compile `VocoApp`.

---

### Task 5: Implement Workbench Overview UI

**Files:**

- Modify: `native/Sources/VocoApp/SettingsView.swift`

- [ ] **Step 1: Replace overview placeholder with approved A layout**

Replace `overviewSection` with:

```swift
    private var overviewSection: some View {
        let workbench = coordinator.settingsWorkbenchSnapshot

        return VStack(alignment: .leading, spacing: 16) {
            settingsPageHeader(
                eyebrow: "OVERVIEW",
                title: "把设置页改成可恢复、可验证的控制台",
                detail: "首屏直接回答“现在能不能用、哪里坏了、下一步点哪里”。菜单、权限、转写、HUD 和诊断仍然保留，但不再混在一条长滚动里。"
            ) {
                Button {
                    coordinator.toggleRecordingFromMenu()
                } label: {
                    Label("开始测试录音", systemImage: "waveform")
                }

                Button {
                    DiagnosticsWindowPresenter.shared.show(coordinator: coordinator)
                } label: {
                    Label("打开诊断", systemImage: "stethoscope")
                }
            }

            statusRow

            legacyInstallSection

            SettingsOverviewRecoveryCard(
                snapshot: workbench,
                primaryAction: performOverviewPrimaryAction,
                secondaryAction: {
                    coordinator.prepareForSettingsPresentation()
                }
            )

            RecentVoiceInputChainPanel(
                steps: workbench.recentChain,
                rerunAction: {
                    coordinator.toggleRecordingFromMenu()
                },
                exportAction: exportDiagnosticsFromSettings
            )
        }
    }
```

- [ ] **Step 2: Add reusable page header helper**

Inside `SettingsView`, add:

```swift
    private func settingsPageHeader<Actions: View>(
        eyebrow: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(spacing: 8) {
                actions()
            }
            .controlSize(.small)
        }
    }
```

- [ ] **Step 3: Add overview action helpers**

Inside `SettingsView`, add:

```swift
    private func performOverviewPrimaryAction() {
        let title = coordinator.settingsWorkbenchSnapshot.overview.primaryActionTitle
        if title.contains("辅助功能") {
            openSettings(for: .accessibility)
        } else if title.contains("麦克风") {
            openSettings(for: .microphone)
        } else if title.contains("转写") || title.contains("Keychain") {
            selectedSection = .transcription
        } else if title.contains("权限与输入") || title.contains("输入") {
            selectedSection = .permissionsAndInput
        } else if title.contains("诊断") {
            DiagnosticsWindowPresenter.shared.show(coordinator: coordinator)
        } else {
            coordinator.toggleRecordingFromMenu()
        }
    }

    private func exportDiagnosticsFromSettings() {
        do {
            _ = try coordinator.exportDiagnosticBundleToTemporaryDirectory()
        } catch {
            coordinator.fail(error.localizedDescription)
        }
    }
```

- [ ] **Step 4: Add overview card subviews**

After sidebar subviews, add:

```swift
private struct SettingsOverviewRecoveryCard: View {
    let snapshot: SettingsWorkbenchSnapshot
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("需要处理 1 项", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)

                Text(snapshot.overview.title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(snapshot.overview.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(snapshot.overview.primaryActionTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                    Button(snapshot.overview.secondaryActionTitle, action: secondaryAction)
                }
                .controlSize(.small)
            }

            Spacer(minLength: 12)

            VoiceInputFlowPreview()
                .frame(width: 320)
        }
        .padding(14)
        .background(.quaternary.opacity(0.36), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct VoiceInputFlowPreview: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("语音输入链路")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            flowBox(title: "Right Command", detail: "切换录音")
            connector
            notchPreview
            connector
            flowBox(title: "当前输入框", detail: "等待插入转写文本")
        }
        .padding(10)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator.opacity(0.45), lineWidth: 1)
        )
    }

    private func flowBox(title: String, detail: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private var connector: some View {
        Rectangle()
            .fill(.separator.opacity(0.65))
            .frame(width: 1, height: 10)
    }

    private var notchPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("语音输入")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.yellow)
                Spacer()
                MiniWaveform()
            }

            Text("第二行实时显示你正在说的内容")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.green)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MiniWaveform: View {
    private let heights: [CGFloat] = [9, 16, 22, 15, 11, 18, 13]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(heights.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.green)
                    .frame(width: 3, height: heights[index])
            }
        }
        .frame(height: 24)
    }
}
```

- [ ] **Step 5: Add recent chain panel subview**

After `VoiceInputFlowPreview`, add:

```swift
private struct RecentVoiceInputChainPanel: View {
    let steps: [VoiceInputChainStepSnapshot]
    let rerunAction: () -> Void
    let exportAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("最近一次语音输入链路")
                        .font(.headline)
                    Text("按真实使用路径检查：Command -> 录音 -> Doubao -> 输入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("重新运行测试", action: rerunAction)
                Button("导出诊断包", action: exportAction)
            }
            .controlSize(.small)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(steps) { step in
                    RecentVoiceInputChainStepCard(step: step)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct RecentVoiceInputChainStepCard: View {
    let step: VoiceInputChainStepSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: step.status.systemImage)
                    .font(.system(size: 8))
                    .foregroundStyle(statusColor)
                Spacer()
                Text(statusTitle)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }

            Text(step.title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(step.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(step.actionTitle) {}
                .controlSize(.small)
                .disabled(true)
        }
        .padding(10)
        .frame(minHeight: 136, alignment: .topLeading)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
        )
    }

    private var statusTitle: String {
        switch step.status {
        case .ok:
            "正常"
        case .needsAttention:
            "阻塞"
        case .warning:
            "注意"
        case .neutral:
            "等待"
        }
    }

    private var statusColor: Color {
        switch step.status {
        case .ok:
            .green
        case .needsAttention:
            .red
        case .warning:
            .yellow
        case .neutral:
            .secondary
        }
    }
}
```

- [ ] **Step 6: Run Swift tests for compile**

Run:

```bash
swift test --package-path native --filter SettingsWorkbenchModelsTests
```

Expected: PASS.

---

### Task 6: Map Detail Screens to the Five Workbench Sections

**Files:**

- Modify: `native/Sources/VocoApp/SettingsView.swift`

- [ ] **Step 1: Replace detail section placeholders with headers**

Replace `voiceInputSection`, `transcriptionWorkbenchSection`, `permissionsAndInputSection`, and `diagnosticsAndPrivacySection` with:

```swift
    private var voiceInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsPageHeader(
                eyebrow: "VOICE INPUT",
                title: "语音输入体验",
                detail: "快捷键、录音、电平和 HUD 预览集中在这里。"
            ) {
                Button {
                    coordinator.toggleRecordingFromMenu()
                } label: {
                    Label("试录 3 秒", systemImage: "waveform")
                }
            }

            hotkeySection
            audioSettingsSection
            hudSettingsSection
        }
    }

    private var transcriptionWorkbenchSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsPageHeader(
                eyebrow: "TRANSCRIPTION",
                title: "Doubao 转写服务",
                detail: "凭证只通过设置界面保存到 Keychain；新旧控制台凭证模式必须由用户明确选择。"
            ) {
                Button("测试连接") {
                    coordinator.prepareForSettingsPresentation()
                }
            }

            transcriptionSection
        }
    }

    private var permissionsAndInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsPageHeader(
                eyebrow: "PERMISSIONS AND INPUT",
                title: "权限与文本输入",
                detail: "麦克风和辅助功能是必需权限。"
            ) {
                Button {
                    coordinator.refreshPermissions()
                } label: {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
            }

            permissionsSection
            injectionSettingsSection
        }
    }

    private var diagnosticsAndPrivacySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsPageHeader(
                eyebrow: "DIAGNOSTICS AND PRIVACY",
                title: "诊断与隐私",
                detail: "最近运行链路、导出诊断包、Keychain、转写保留和日志脱敏集中在这里。"
            ) {
                Button("导出诊断包", action: exportDiagnosticsFromSettings)
            }

            RecentVoiceInputChainPanel(
                steps: coordinator.settingsWorkbenchSnapshot.recentChain,
                rerunAction: {
                    coordinator.toggleRecordingFromMenu()
                },
                exportAction: exportDiagnosticsFromSettings
            )
            privacySettingsSection
            recordingDiagnosticsSection
        }
    }
```

- [ ] **Step 2: Keep old helpers but remove old top-level long-scroll composition**

Delete only the old body content that rendered every section in one `VStack`. Do not delete these existing helper views:

```swift
statusRow
launchAtLoginSection
legacyInstallSection
audioSettingsSection
permissionsSection
hotkeySection
injectionSettingsSection
hudSettingsSection
privacySettingsSection
transcriptionSection
recordingDiagnosticsSection
permissionRow(_:)
settingsCard(section:content:)
settingsStatusRow(title:detail:systemImage:tint:)
diagnosticRow(title:value:systemImage:)
```

- [ ] **Step 3: Add launch-at-login to overview or diagnostics**

In `overviewSection`, after `legacyInstallSection`, insert:

```swift
            launchAtLoginSection
```

Expected: launch-at-login remains discoverable from the default page.

- [ ] **Step 4: Run full Swift tests**

Run:

```bash
swift test --package-path native
```

Expected: PASS, except any existing explicitly skipped live Doubao opt-in test remains skipped.

---

### Task 7: Polish macOS Layout and Remove Visual Regressions

**Files:**

- Modify: `native/Sources/VocoApp/SettingsView.swift`

- [ ] **Step 1: Ensure sidebar has no badge or trailing icon**

Inspect `SettingsWorkbenchSidebarRow`. It must only contain:

```swift
Image(systemName: status.systemImage)
VStack { Text(section.title); Text(section.summary) }
```

Expected: no `Text("1")`, no `.badge`, no trailing section icon.

- [ ] **Step 2: Keep card styling light**

For new workbench cards, use:

```swift
.background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
```

Expected: no fixed white background, no custom gradient, no nested card-in-card beyond actual repeated step cards.

- [ ] **Step 3: Confirm text does not use viewport-scaled sizes**

Search:

```bash
rg -n "GeometryReader|\\.scaleEffect|font\\(\\.system\\(size:" native/Sources/VocoApp/SettingsView.swift
```

Expected: no new viewport-driven type scaling. Existing fixed small `MiniWaveform` geometry is acceptable if it does not scale text.

- [ ] **Step 4: Run formatting check**

Run:

```bash
swift test --package-path native --filter SettingsWorkbenchModelsTests
```

Expected: PASS and no compiler warnings from the changed files.

---

### Task 8: Final Verification

**Files:**

- No code edits unless verification reveals a defect.

- [ ] **Step 1: Run all native tests**

Run:

```bash
swift test --package-path native
```

Expected: all tests pass; the live Doubao opt-in test may remain skipped if it is already configured that way.

- [ ] **Step 2: Build debug app bundle**

Run:

```bash
packaging/build_native_app_bundle.sh --profile debug
```

Expected: command exits 0 and verifies `target/native/Voco.app`.

- [ ] **Step 3: Run diff whitespace check**

Run:

```bash
git diff --check
```

Expected: no output and exit 0.

- [ ] **Step 4: Inspect changed files**

Run:

```bash
git status --short
git diff --stat
```

Expected: changed files include the new workbench model/tests and `SettingsView.swift`; unrelated user changes remain untouched.

---

## Self-Review Checklist

- Spec coverage:
  - 5-section navigation: Tasks 1, 2, 4, 6.
  - Task recovery overview: Tasks 2, 5.
  - Voice-input flow preview: Task 5.
  - Recent chain diagnostics: Tasks 3, 5, 6.
  - Sidebar state dots and no badges/icons: Tasks 4, 7.
  - Existing credential and permission actions preserved: Tasks 4, 6.
  - Verification commands: Task 8.
- Placeholder scan: no `TBD`, `TODO`, or unspecified implementation steps.
- Type consistency:
  - `SettingsWorkbenchSection`
  - `SettingsWorkbenchSectionStatus`
  - `SettingsWorkbenchSnapshot`
  - `SettingsWorkbenchOverviewSnapshot`
  - `VoiceInputChainStepSnapshot`
