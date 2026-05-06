# Voco Native Settings Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. If a subagent is dispatched for any step, use GPT-5.5 xhigh.

**Goal:** Complete the native macOS settings surface with tested read-only snapshots for audio, text insertion, HUD behavior, and privacy policy state.

**Architecture:** Keep all display titles, details, symbols, and status mapping in `VocoAppCore` model files so SwiftUI remains thin. `AppCoordinator` exposes computed settings snapshots from existing runtime state; `SettingsView` renders those snapshots without adding persistence or real device enumeration in this slice.

**Tech Stack:** Swift 6, XCTest, SwiftUI, AppKit settings links, existing `AppCoordinator` observable state and `VocoAppCore` snapshots.

---

## Baseline

User-provided baseline before this task:

```bash
cd native && swift test
```

Observed: PASS. XCTest executed 86 tests, 1 skipped, 0 failures.

## Constraints

- Work only in `/private/tmp/voco-native-settings-completion` on branch `codex/native-settings-completion`.
- Do not merge to `master`.
- Do not revert or overwrite unrelated work from other agents.
- Do not implement real audio device enumeration or durable settings persistence in this slice.
- Add read-only/status UI unless state is explicit, in-memory, and tested.
- Preserve existing launch-at-login, hotkey, transcription credential, recording diagnostic, and permission content.

## File Structure

- Modify `native/Sources/VocoAppCore/SettingsSection.swift` — add section summaries used by the settings sidebar/detail headings.
- Create `native/Sources/VocoAppCore/AudioSettingsModels.swift` — input device, level meter, sample-rate display snapshots.
- Create `native/Sources/VocoAppCore/InjectionSettingsModels.swift` — insertion strategy and focused app diagnostic display snapshots.
- Create `native/Sources/VocoAppCore/HUDSettingsModels.swift` — HUD position, notch mode, and transcript preview visibility snapshots.
- Create `native/Sources/VocoAppCore/PrivacySettingsModels.swift` — Keychain status, transcript retention, and diagnostic log policy snapshots.
- Modify `native/Sources/VocoAppCore/AppCoordinator.swift` — expose computed `audioSettingsSnapshot`, `injectionSettingsSnapshot`, `hudSettingsSnapshot`, and `privacySettingsSnapshot`.
- Modify `native/Sources/VocoApp/SettingsView.swift` — render the new read-only sections using coordinator snapshots.
- Create matching tests under `native/Tests/VocoAppCoreTests/`.
- Modify this plan with final verification notes.

## Task 1: Audio Settings Models

**Files:**
- Create: `native/Tests/VocoAppCoreTests/AudioSettingsModelsTests.swift`
- Create: `native/Sources/VocoAppCore/AudioSettingsModels.swift`

- [ ] **Step 1: Write failing audio model tests**

Create `native/Tests/VocoAppCoreTests/AudioSettingsModelsTests.swift`:

```swift
import XCTest
@testable import VocoAppCore

final class AudioSettingsModelsTests: XCTestCase {
    func testDefaultAudioSettingsUseSystemInputAndIdleRuntime() {
        let snapshot = AudioSettingsSnapshot(lastAudio: nil)

        XCTAssertEqual(snapshot.inputDevice.title, "系统默认输入")
        XCTAssertEqual(snapshot.inputDevice.detail, "使用 macOS 当前默认麦克风；真实设备选择将在后续偏好设置中接入。")
        XCTAssertEqual(snapshot.levelMeter.title, "无近期采样")
        XCTAssertEqual(snapshot.levelMeter.detail, "开始一次录音后会显示最近峰值电平。")
        XCTAssertEqual(snapshot.sampleRate.title, "等待采样率")
        XCTAssertEqual(snapshot.sampleRate.detail, "暂无最近录音；目标转写采样率为 16,000 Hz。")
    }

    func testRecentAudioShowsLevelAndMatchedSampleRate() {
        let audio = CapturedAudioSnapshot(durationSeconds: 1.25, sampleRate: 16_000, peakAmplitude: 0.61)

        let snapshot = AudioSettingsSnapshot(lastAudio: audio)

        XCTAssertEqual(snapshot.levelMeter.title, "电平正常")
        XCTAssertEqual(snapshot.levelMeter.detail, "最近峰值 61% · 1.25s")
        XCTAssertEqual(snapshot.levelMeter.systemImage, "waveform")
        XCTAssertEqual(snapshot.sampleRate.title, "16,000 Hz")
        XCTAssertEqual(snapshot.sampleRate.detail, "最近录音采样率符合目标转写输入。")
        XCTAssertTrue(snapshot.sampleRate.matchesExpectedRate)
    }

    func testRecentAudioFlagsClippingAndUnexpectedSampleRate() {
        let audio = CapturedAudioSnapshot(durationSeconds: 0.5, sampleRate: 44_100, peakAmplitude: 0.93)

        let snapshot = AudioSettingsSnapshot(lastAudio: audio)

        XCTAssertEqual(snapshot.levelMeter.title, "电平接近削波")
        XCTAssertEqual(snapshot.levelMeter.detail, "最近峰值 93% · 0.50s")
        XCTAssertEqual(snapshot.sampleRate.title, "44,100 Hz")
        XCTAssertEqual(snapshot.sampleRate.detail, "最近录音采样率与目标 16,000 Hz 不一致。")
        XCTAssertFalse(snapshot.sampleRate.matchesExpectedRate)
    }
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter AudioSettingsModelsTests
```

Expected: compile failure because `AudioSettingsSnapshot` does not exist.

- [ ] **Step 3: Implement audio settings models**

Create `native/Sources/VocoAppCore/AudioSettingsModels.swift` with:

```swift
import Foundation

public struct AudioSettingsSnapshot: Equatable, Sendable {
    public let inputDevice: AudioInputDeviceSnapshot
    public let levelMeter: AudioLevelMeterSnapshot
    public let sampleRate: AudioSampleRateSnapshot

    public init(
        lastAudio: CapturedAudioSnapshot?,
        inputDeviceName: String = "系统默认输入",
        expectedSampleRate: Double = 16_000
    ) {
        self.inputDevice = AudioInputDeviceSnapshot(displayName: inputDeviceName)
        self.levelMeter = AudioLevelMeterSnapshot(lastAudio: lastAudio)
        self.sampleRate = AudioSampleRateSnapshot(lastAudio: lastAudio, expectedSampleRate: expectedSampleRate)
    }
}
```

Add focused helper structs in the same file: `AudioInputDeviceSnapshot`, `AudioLevelMeterSnapshot`, and `AudioSampleRateSnapshot`. Each helper exposes `title`, `detail`, `systemImage`, and simple booleans where tests need them.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter AudioSettingsModelsTests
```

Expected: PASS.

## Task 2: Injection Settings Models

**Files:**
- Create: `native/Tests/VocoAppCoreTests/InjectionSettingsModelsTests.swift`
- Create: `native/Sources/VocoAppCore/InjectionSettingsModels.swift`

- [ ] **Step 1: Write failing injection model tests**

Create `native/Tests/VocoAppCoreTests/InjectionSettingsModelsTests.swift`:

```swift
import XCTest
@testable import VocoAppCore

final class InjectionSettingsModelsTests: XCTestCase {
    func testDefaultInjectionSettingsShowNoRecentTarget() {
        let snapshot = InjectionSettingsSnapshot(lastInjection: nil)

        XCTAssertEqual(snapshot.strategy.title, "等待插入")
        XCTAssertEqual(snapshot.strategy.detail, "完成一次转写后会显示采用的文本插入方式。")
        XCTAssertEqual(snapshot.focusedApp.title, "无近期目标")
        XCTAssertEqual(snapshot.focusedApp.detail, "尚未完成文本插入，无法显示最近聚焦 App。")
        XCTAssertFalse(snapshot.focusedApp.hasRecentTarget)
    }

    func testSuccessfulInjectionShowsStrategyAndFocusedApp() {
        let injection = TextInjectionSnapshot(
            targetAppName: "Notes",
            strategy: .directAccessibility,
            succeeded: true,
            detail: "已通过辅助功能直接插入文本。"
        )

        let snapshot = InjectionSettingsSnapshot(lastInjection: injection)

        XCTAssertEqual(snapshot.strategy.title, "辅助功能直接插入")
        XCTAssertEqual(snapshot.strategy.detail, "已通过辅助功能直接插入文本。")
        XCTAssertEqual(snapshot.strategy.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(snapshot.focusedApp.title, "Notes")
        XCTAssertEqual(snapshot.focusedApp.detail, "最近插入目标 App。")
        XCTAssertTrue(snapshot.focusedApp.hasRecentTarget)
    }

    func testFailedInjectionShowsFailureDiagnostics() {
        let injection = TextInjectionSnapshot(
            targetAppName: nil,
            strategy: .unavailable,
            succeeded: false,
            detail: "无法插入文本：请先允许辅助功能。"
        )

        let snapshot = InjectionSettingsSnapshot(lastInjection: injection)

        XCTAssertEqual(snapshot.strategy.title, "不可用")
        XCTAssertEqual(snapshot.strategy.systemImage, "xmark.circle.fill")
        XCTAssertEqual(snapshot.focusedApp.title, "无目标 App")
        XCTAssertEqual(snapshot.focusedApp.detail, "无法插入文本：请先允许辅助功能。")
        XCTAssertFalse(snapshot.focusedApp.hasRecentTarget)
    }
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter InjectionSettingsModelsTests
```

Expected: compile failure because `InjectionSettingsSnapshot` does not exist.

- [ ] **Step 3: Implement injection settings models**

Create `native/Sources/VocoAppCore/InjectionSettingsModels.swift` with `InjectionSettingsSnapshot`, `InjectionStrategySettingsSnapshot`, and `FocusedAppSettingsSnapshot`. The initializer accepts `lastInjection: TextInjectionSnapshot?` and maps missing, successful, and failed injections to the titles and details asserted above.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter InjectionSettingsModelsTests
```

Expected: PASS.

## Task 3: HUD Settings Models

**Files:**
- Create: `native/Tests/VocoAppCoreTests/HUDSettingsModelsTests.swift`
- Create: `native/Sources/VocoAppCore/HUDSettingsModels.swift`

- [ ] **Step 1: Write failing HUD settings model tests**

Create `native/Tests/VocoAppCoreTests/HUDSettingsModelsTests.swift`:

```swift
import XCTest
@testable import VocoAppCore

final class HUDSettingsModelsTests: XCTestCase {
    func testDefaultHUDSettingsAreTopCenterNotchAwareWithPreviewEnabled() {
        let snapshot = HUDSettingsSnapshot()

        XCTAssertEqual(snapshot.position.title, "顶部居中")
        XCTAssertEqual(snapshot.position.detail, "HUD 固定显示在屏幕顶部中央。")
        XCTAssertEqual(snapshot.notchMode.title, "刘海避让")
        XCTAssertEqual(snapshot.notchMode.detail, "在带刘海屏幕上自动贴近 Dynamic Island 区域。")
        XCTAssertEqual(snapshot.transcriptPreview.title, "显示转写预览")
        XCTAssertEqual(snapshot.transcriptPreview.detail, "录音和插入过程中显示最多 80 个字符的实时文本。")
        XCTAssertTrue(snapshot.transcriptPreview.isVisible)
    }
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter HUDSettingsModelsTests
```

Expected: compile failure because `HUDSettingsSnapshot` does not exist.

- [ ] **Step 3: Implement HUD settings models**

Create `native/Sources/VocoAppCore/HUDSettingsModels.swift` with `HUDSettingsSnapshot`, `HUDPositionSetting`, `HUDNotchModeSetting`, and `HUDTranscriptPreviewSetting`. Defaults are top center, notch-aware, and transcript preview enabled.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter HUDSettingsModelsTests
```

Expected: PASS.

## Task 4: Privacy Settings Models

**Files:**
- Create: `native/Tests/VocoAppCoreTests/PrivacySettingsModelsTests.swift`
- Create: `native/Sources/VocoAppCore/PrivacySettingsModels.swift`

- [ ] **Step 1: Write failing privacy model tests**

Create `native/Tests/VocoAppCoreTests/PrivacySettingsModelsTests.swift`:

```swift
import XCTest
@testable import VocoAppCore

final class PrivacySettingsModelsTests: XCTestCase {
    func testMissingCredentialsShowKeychainMissingAndPrivateDefaults() {
        let snapshot = PrivacySettingsSnapshot(
            transcriptionCredentials: .missing(provider: .doubao)
        )

        XCTAssertEqual(snapshot.keychain.title, "Keychain 未保存凭证")
        XCTAssertEqual(snapshot.keychain.detail, "Keychain 中没有保存 API Key。")
        XCTAssertEqual(snapshot.transcriptRetention.title, "不保留转写文本")
        XCTAssertEqual(snapshot.transcriptRetention.detail, "转写文本仅用于本次插入和当前运行时诊断。")
        XCTAssertEqual(snapshot.logsPolicy.title, "日志默认脱敏")
        XCTAssertEqual(snapshot.logsPolicy.detail, "诊断信息不记录完整 API Key 或完整转写正文。")
    }

    func testStoredCredentialsShowMaskedKeychainStatus() {
        let snapshot = PrivacySettingsSnapshot(
            transcriptionCredentials: .stored(provider: .doubao, apiKey: "sk-test-abcdef")
        )

        XCTAssertEqual(snapshot.keychain.title, "Keychain 已保存凭证")
        XCTAssertEqual(snapshot.keychain.detail, "sk-t...cdef")
        XCTAssertEqual(snapshot.keychain.systemImage, "key.fill")
    }

    func testCredentialFailureShowsKeychainError() {
        let snapshot = PrivacySettingsSnapshot(
            transcriptionCredentials: .failed(provider: .doubao, message: "denied")
        )

        XCTAssertEqual(snapshot.keychain.title, "Keychain 访问失败")
        XCTAssertEqual(snapshot.keychain.detail, "Keychain 访问失败：denied")
        XCTAssertEqual(snapshot.keychain.systemImage, "exclamationmark.triangle.fill")
    }
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter PrivacySettingsModelsTests
```

Expected: compile failure because `PrivacySettingsSnapshot` does not exist.

- [ ] **Step 3: Implement privacy settings models**

Create `native/Sources/VocoAppCore/PrivacySettingsModels.swift` with `PrivacySettingsSnapshot`, `KeychainPrivacyStatusSnapshot`, `TranscriptRetentionPolicySnapshot`, and `DiagnosticLogsPolicySnapshot`. Map `TranscriptionCredentialSnapshot` to Keychain status and keep transcript retention/logging policies conservative and read-only.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter PrivacySettingsModelsTests
```

Expected: PASS.

- [ ] **Step 5: Commit model slice**

Run:

```bash
git add native/Sources/VocoAppCore/AudioSettingsModels.swift \
  native/Sources/VocoAppCore/InjectionSettingsModels.swift \
  native/Sources/VocoAppCore/HUDSettingsModels.swift \
  native/Sources/VocoAppCore/PrivacySettingsModels.swift \
  native/Tests/VocoAppCoreTests/AudioSettingsModelsTests.swift \
  native/Tests/VocoAppCoreTests/InjectionSettingsModelsTests.swift \
  native/Tests/VocoAppCoreTests/HUDSettingsModelsTests.swift \
  native/Tests/VocoAppCoreTests/PrivacySettingsModelsTests.swift
git commit -m "feat(native): add native settings models"
```

## Task 5: SettingsView Section Rendering

**Files:**
- Modify: `native/Sources/VocoAppCore/SettingsSection.swift`
- Modify: `native/Tests/VocoAppCoreTests/SettingsSectionTests.swift`
- Modify: `native/Sources/VocoApp/SettingsView.swift`

- [ ] **Step 1: Write failing section metadata tests**

Add assertions to `native/Tests/VocoAppCoreTests/SettingsSectionTests.swift`:

```swift
func testSettingsSectionsExposeSummariesForDetailRendering() {
    XCTAssertEqual(SettingsSection.audio.summary, "输入设备、电平和采样率")
    XCTAssertEqual(SettingsSection.injection.summary, "插入策略和聚焦 App 诊断")
    XCTAssertEqual(SettingsSection.hud.summary, "位置、刘海模式和转写预览")
    XCTAssertEqual(SettingsSection.privacy.summary, "Keychain、转写保留和日志策略")
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter SettingsSectionTests
```

Expected: compile failure because `SettingsSection.summary` does not exist.

- [ ] **Step 3: Implement section summaries**

Add `public var summary: String` to `SettingsSection`, with concise summaries for all cases. Required values for audio, injection, HUD, and privacy must match the test.

- [ ] **Step 4: Render new settings sections**

Modify `SettingsView` to add read-only cards:

- `audioSettingsSection` shows `coordinator.audioSettingsSnapshot.inputDevice`, `.levelMeter`, and `.sampleRate`.
- `injectionSettingsSection` shows `coordinator.injectionSettingsSnapshot.strategy` and `.focusedApp`.
- `hudSettingsSection` shows `coordinator.hudSettingsSnapshot.position`, `.notchMode`, and `.transcriptPreview`.
- `privacySettingsSection` shows `coordinator.privacySettingsSnapshot.keychain`, `.transcriptRetention`, and `.logsPolicy`.

Keep the existing `launchAtLoginSection`, `hotkeySection`, `transcriptionSection`, `recordingDiagnosticsSection`, and `permissionsSection` in the detail view.

- [ ] **Step 5: Run section metadata GREEN**

Run:

```bash
cd native && swift test --filter SettingsSectionTests
```

Expected: PASS.

## Task 6: Coordinator Settings Snapshot Wiring

**Files:**
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Write failing coordinator snapshot tests**

Add tests to `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`:

```swift
@MainActor
func testCoordinatorPublishesDefaultSettingsSnapshots() {
    let coordinator = AppCoordinator(hasCompletedOnboarding: true)

    XCTAssertEqual(coordinator.audioSettingsSnapshot.inputDevice.title, "系统默认输入")
    XCTAssertEqual(coordinator.injectionSettingsSnapshot.strategy.title, "等待插入")
    XCTAssertEqual(coordinator.hudSettingsSnapshot.position.title, "顶部居中")
    XCTAssertEqual(coordinator.privacySettingsSnapshot.transcriptRetention.title, "不保留转写文本")
}

@MainActor
func testCoordinatorSettingsSnapshotsReflectRecentRuntimeState() async {
    let result = RecordingWorkflowResult(
        audio: CapturedAudioSnapshot(durationSeconds: 1.2, sampleRate: 16_000, peakAmplitude: 0.64),
        transcript: TranscriptSnapshot(finalText: "hello", partials: [], providerName: "Fake ASR", latencyMilliseconds: 10),
        injection: TextInjectionSnapshot(
            targetAppName: "TextEdit",
            strategy: .unicodeEvent,
            succeeded: true,
            detail: "已通过 Unicode 事件插入文本。"
        )
    )
    let coordinator = AppCoordinator(
        hasCompletedOnboarding: true,
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
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests/testCoordinatorPublishesDefaultSettingsSnapshots
cd native && swift test --filter AppCoordinatorTests/testCoordinatorSettingsSnapshotsReflectRecentRuntimeState
```

Expected: compile failure because coordinator computed settings snapshots do not exist.

- [ ] **Step 3: Implement coordinator computed snapshots**

Add computed properties to `AppCoordinator`:

```swift
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
```

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests/testCoordinatorPublishesDefaultSettingsSnapshots
cd native && swift test --filter AppCoordinatorTests/testCoordinatorSettingsSnapshotsReflectRecentRuntimeState
```

Expected: PASS.

- [ ] **Step 5: Commit completed settings sections**

Run:

```bash
git add native/Sources/VocoAppCore/SettingsSection.swift \
  native/Sources/VocoAppCore/AppCoordinator.swift \
  native/Sources/VocoApp/SettingsView.swift \
  native/Tests/VocoAppCoreTests/SettingsSectionTests.swift \
  native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift
git commit -m "feat(native): complete settings sections"
```

## Task 7: Full Verification and Documentation

**Files:**
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-settings-completion.md`

- [ ] **Step 1: Run full native tests**

Run:

```bash
cd native && swift test
```

Expected: PASS with 0 failures.

- [ ] **Step 2: Run native bundle smoke**

Run:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Expected: PASS and key output includes `ok: native Voco.app bundle smoke passed`.

- [ ] **Step 3: Run whitespace diff check**

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 4: Verify generated app signature**

Run:

```bash
codesign --verify --deep --strict target/native/Voco.app
```

Expected: no output and exit code 0.

- [ ] **Step 5: Append verification notes**

Append:

```markdown
## Verification Notes

- `cd native && swift test`: PASS. [observed XCTest summary]
- `packaging/tests/native_app_bundle_smoke.sh`: PASS. [key ok lines]
- `git diff --check`: PASS. No whitespace errors.
- `codesign --verify --deep --strict target/native/Voco.app`: PASS. No output.
```

- [ ] **Step 6: Commit verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-05-06-voco-native-settings-completion.md
git commit -m "docs(native): mark settings completion verification"
```

## Acceptance Checklist

- Audio section shows input device, level meter status, and sample-rate status.
- Injection section shows insertion strategy and focused app diagnostics.
- HUD section exposes position, notch mode, and transcript preview visibility.
- Privacy section shows Keychain status, transcript retention policy, and logs policy.
- Existing launch-at-login, hotkey, transcription credential, recording diagnostic, and permission UI remains present.
- Full verification commands in Task 7 have fresh observed results.
