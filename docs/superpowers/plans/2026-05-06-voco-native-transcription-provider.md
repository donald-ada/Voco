# Voco Native Transcription Provider Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace silent empty native transcription with a fail-loud provider foundation: status metadata, typed provider errors, coordinator diagnostics, and an unconfigured provider wired into the app.

**Architecture:** Keep provider state and error classification in `VocoAppCore` so tests do not require network credentials. Expose transcription status through `RecordingWorkflowing`, let `AppCoordinator` publish it for settings, and wire `VocoNativeApp` to an `UnavailableTranscriptionProvider` until the real ASR provider and Keychain slice land.

**Tech Stack:** Swift 6, XCTest, SwiftUI settings diagnostics, existing native `RecordingWorkflowing` dependency injection.

---

## File Structure

- Create `native/Sources/VocoAppCore/TranscriptionModels.swift`
  - Defines `TranscriptionProviderStatus` and `TranscriptionProviderError`.
- Create `native/Tests/VocoAppCoreTests/TranscriptionModelsTests.swift`
  - Covers status labels, usability, and localized provider error messages.
- Modify `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`
  - Adds `status` to `TranscriptionProviding`, `transcriptionStatus` to `RecordingWorkflowing`, and introduces `UnavailableTranscriptionProvider`.
- Modify `native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift`
  - Covers unavailable provider throwing instead of silently returning an empty transcript.
- Modify `native/Sources/VocoAppCore/AppCoordinator.swift`
  - Publishes `transcriptionProviderStatus` and refreshes it from the workflow.
- Modify `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`
  - Covers status publication and provider failure surfacing.
- Modify `native/Sources/VocoApp/SettingsView.swift`
  - Shows transcription provider status in settings.
- Modify `native/Sources/VocoApp/VocoNativeApp.swift`
  - Wires `UnavailableTranscriptionProvider()` instead of `StaticTranscriptionProvider()`.
- Modify this plan with final verification results.

## Task 1: Transcription Models

**Files:**
- Create: `native/Tests/VocoAppCoreTests/TranscriptionModelsTests.swift`
- Create: `native/Sources/VocoAppCore/TranscriptionModels.swift`

- [ ] **Step 1: Write failing model tests**

Create `native/Tests/VocoAppCoreTests/TranscriptionModelsTests.swift`:

```swift
import XCTest
@testable import VocoAppCore

final class TranscriptionModelsTests: XCTestCase {
    func testProviderStatusHasUserVisibleMetadata() {
        XCTAssertEqual(TranscriptionProviderStatus.notConfigured.title, "未配置")
        XCTAssertEqual(TranscriptionProviderStatus.notConfigured.systemImage, "exclamationmark.triangle")
        XCTAssertFalse(TranscriptionProviderStatus.notConfigured.isUsable)

        XCTAssertEqual(TranscriptionProviderStatus.ready(providerName: "Doubao").title, "Doubao")
        XCTAssertEqual(TranscriptionProviderStatus.ready(providerName: "Doubao").detail, "转写服务已配置")
        XCTAssertTrue(TranscriptionProviderStatus.ready(providerName: "Doubao").isUsable)

        XCTAssertEqual(TranscriptionProviderStatus.authenticationRequired(providerName: "Doubao").title, "Doubao 需要认证")
        XCTAssertFalse(TranscriptionProviderStatus.authenticationRequired(providerName: "Doubao").isUsable)
    }

    func testProviderErrorsAreLocalizedAndClassified() {
        XCTAssertEqual(
            TranscriptionProviderError.notConfigured.localizedDescription,
            "转写服务未配置：请先在设置中配置 ASR provider。"
        )
        XCTAssertEqual(
            TranscriptionProviderError.authentication(providerName: "Doubao", message: "invalid token").localizedDescription,
            "Doubao 认证失败：invalid token"
        )
        XCTAssertTrue(TranscriptionProviderError.transport(providerName: "Doubao", message: "timeout", retryable: true).isRetryable)
        XCTAssertFalse(TranscriptionProviderError.authentication(providerName: "Doubao", message: "invalid token").isRetryable)
    }
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter TranscriptionModelsTests
```

Expected: compile failure because `TranscriptionProviderStatus` and `TranscriptionProviderError` do not exist.

- [ ] **Step 3: Implement models**

Create `native/Sources/VocoAppCore/TranscriptionModels.swift` with:

```swift
import Foundation

public enum TranscriptionProviderStatus: Equatable, Sendable {
    case notConfigured
    case ready(providerName: String)
    case authenticationRequired(providerName: String)
    case offline(providerName: String)
    case failed(providerName: String, message: String)

    public var title: String { ... }
    public var detail: String { ... }
    public var systemImage: String { ... }
    public var isUsable: Bool { ... }
}

public enum TranscriptionProviderError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case emptyAudio
    case authentication(providerName: String, message: String)
    case transport(providerName: String, message: String, retryable: Bool)
    case provider(providerName: String, message: String)
    case cancelled

    public var errorDescription: String? { ... }
    public var isRetryable: Bool { ... }
}
```

Use the exact Chinese strings asserted by tests for `notConfigured` and authentication errors. For the other statuses, use concise user-facing Chinese detail strings.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter TranscriptionModelsTests
```

Expected: all `TranscriptionModelsTests` pass.

- [ ] **Step 5: Commit models**

Run:

```bash
git add native/Sources/VocoAppCore/TranscriptionModels.swift native/Tests/VocoAppCoreTests/TranscriptionModelsTests.swift docs/superpowers/plans/2026-05-06-voco-native-transcription-provider.md
git commit -m "feat(native): add transcription provider models"
```

## Task 2: Workflow Provider Status and Unavailable Provider

**Files:**
- Modify: `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`
- Modify: `native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift`

- [ ] **Step 1: Write failing workflow tests**

Add to `RecordingWorkflowTests`:

```swift
@MainActor
func testUnavailableTranscriptionProviderFailsLoudly() async {
    let provider = UnavailableTranscriptionProvider()

    do {
        _ = try await provider.transcribe(CapturedAudioSnapshot(durationSeconds: 1, sampleRate: 16_000, peakAmplitude: 0.2, pcm16Samples: [1]))
        XCTFail("Expected unavailable provider to throw")
    } catch {
        XCTAssertEqual(error.localizedDescription, "转写服务未配置：请先在设置中配置 ASR provider。")
    }

    XCTAssertEqual(provider.status, .notConfigured)
}

@MainActor
func testNativeRecordingWorkflowExposesTranscriptionStatus() {
    let workflow = NativeRecordingWorkflow(
        audioCapture: FakeAudioCaptureEngine(),
        transcription: UnavailableTranscriptionProvider(),
        textInjection: FakeTextInjectionEngine()
    )

    XCTAssertEqual(workflow.transcriptionStatus, .notConfigured)
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter RecordingWorkflowTests
```

Expected: compile failure because `UnavailableTranscriptionProvider`, `TranscriptionProviding.status`, and `RecordingWorkflowing.transcriptionStatus` do not exist.

- [ ] **Step 3: Implement workflow status**

Update protocols:

```swift
@MainActor
public protocol TranscriptionProviding {
    var status: TranscriptionProviderStatus { get }
    func transcribe(_ audio: CapturedAudioSnapshot) async throws -> TranscriptSnapshot
}

@MainActor
public protocol RecordingWorkflowing: AnyObject {
    var transcriptionStatus: TranscriptionProviderStatus { get }
    func startRecording() async throws
    func stopRecording() async throws -> RecordingWorkflowResult
}
```

Implement:

```swift
public final class NativeRecordingWorkflow: RecordingWorkflowing {
    public var transcriptionStatus: TranscriptionProviderStatus {
        transcription.status
    }
}

public final class StaticTranscriptionProvider: TranscriptionProviding {
    public var status: TranscriptionProviderStatus { .ready(providerName: transcript.providerName) }
}

public final class UnavailableTranscriptionProvider: TranscriptionProviding {
    public var status: TranscriptionProviderStatus { .notConfigured }
    public init() {}
    public func transcribe(_ audio: CapturedAudioSnapshot) async throws -> TranscriptSnapshot {
        throw TranscriptionProviderError.notConfigured
    }
}

public final class StaticRecordingWorkflow: RecordingWorkflowing {
    public let transcriptionStatus: TranscriptionProviderStatus
}
```

Update test fakes to return `.ready(providerName: "Fake ASR")`.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter RecordingWorkflowTests
```

Expected: all `RecordingWorkflowTests` pass.

- [ ] **Step 5: Commit workflow status**

Run:

```bash
git add native/Sources/VocoAppCore/RecordingWorkflowModels.swift native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift
git commit -m "feat(native): expose transcription provider status"
```

## Task 3: Coordinator and Settings Diagnostics

**Files:**
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`
- Modify: `native/Sources/VocoApp/SettingsView.swift`

- [ ] **Step 1: Write failing coordinator tests**

Add to `AppCoordinatorTests`:

```swift
@MainActor
func testCoordinatorPublishesTranscriptionProviderStatus() {
    let recordingWorkflow = FakeRecordingWorkflow(transcriptionStatus: .authenticationRequired(providerName: "Doubao"))
    let coordinator = AppCoordinator(hasCompletedOnboarding: true, recordingWorkflow: recordingWorkflow)

    coordinator.finishLaunching()

    XCTAssertEqual(coordinator.transcriptionProviderStatus, .authenticationRequired(providerName: "Doubao"))
}

@MainActor
func testUnavailableTranscriptionFailureSurfacesProviderMessage() async {
    let recordingWorkflow = FakeRecordingWorkflow(stopError: TranscriptionProviderError.notConfigured)
    let coordinator = AppCoordinator(hasCompletedOnboarding: true, recordingWorkflow: recordingWorkflow)
    coordinator.finishLaunching()

    await coordinator.toggleRecordingFromUserAction()
    await coordinator.toggleRecordingFromUserAction()

    XCTAssertEqual(coordinator.status, .providerOffline)
    XCTAssertEqual(coordinator.lastErrorMessage, "转写服务未配置：请先在设置中配置 ASR provider。")
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: compile failure because `transcriptionProviderStatus` is missing, then status assertion fails until provider errors map to `.providerOffline`.

- [ ] **Step 3: Implement coordinator status**

Add:

```swift
@Published public private(set) var transcriptionProviderStatus: TranscriptionProviderStatus
```

Initialize from `recordingWorkflow.transcriptionStatus`, refresh it in `finishLaunching()` and `prepareForSettingsPresentation()`, and add:

```swift
private func failFromWorkflowError(_ error: Error) {
    lastErrorMessage = error.localizedDescription
    if error is TranscriptionProviderError {
        status = .providerOffline
    } else {
        status = .error
    }
}
```

Use `failFromWorkflowError(_:)` in `startRecording()` and `stopRecording()` catches.

- [ ] **Step 4: Render settings status**

Add a compact transcription section in `SettingsView` near recording diagnostics:

```swift
private var transcriptionSection: some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack {
            Text("转写")
                .font(.headline)
            Spacer()
            Label(coordinator.transcriptionProviderStatus.title, systemImage: coordinator.transcriptionProviderStatus.systemImage)
                .font(.caption)
                .foregroundStyle(transcriptionTint(coordinator.transcriptionProviderStatus))
        }
        Text(coordinator.transcriptionProviderStatus.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(12)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
}
```

Insert it before `recordingDiagnosticsSection`. Use green tint for usable status, yellow for `.notConfigured`/`.authenticationRequired`, red for `.offline`/`.failed`.

- [ ] **Step 5: Run GREEN**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: all `AppCoordinatorTests` pass.

- [ ] **Step 6: Commit diagnostics**

Run:

```bash
git add native/Sources/VocoAppCore/AppCoordinator.swift native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift native/Sources/VocoApp/SettingsView.swift
git commit -m "feat(native): surface transcription provider status"
```

## Task 4: Wire App to Fail Loudly When ASR Is Unconfigured

**Files:**
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift`

- [ ] **Step 1: Wire unavailable provider**

In `VocoNativeApp.init()`, change:

```swift
transcription: StaticTranscriptionProvider(),
```

to:

```swift
transcription: UnavailableTranscriptionProvider(),
```

- [ ] **Step 2: Run native tests**

Run:

```bash
cd native && swift test
```

Expected: all native tests pass and the app target compiles with `UnavailableTranscriptionProvider`.

- [ ] **Step 3: Commit wiring**

Run:

```bash
git add native/Sources/VocoApp/VocoNativeApp.swift
git commit -m "feat(native): fail loudly when transcription is unconfigured"
```

## Task 5: Verification

**Files:**
- Verify generated bundle under `target/native/Voco.app`
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-transcription-provider.md`

- [ ] **Step 1: Run full native tests**

Run:

```bash
cd native && swift test
```

Expected: all native tests pass.

- [ ] **Step 2: Run native bundle smoke**

Run:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Expected: native bundle builds, signs, verifies, and launches for smoke validation.

- [ ] **Step 3: Run diff and signature checks**

Run:

```bash
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Expected: both commands exit 0.

- [ ] **Step 4: Record verification results**

Append observed command results under `## Verification Results`.

- [ ] **Step 5: Commit verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-05-06-voco-native-transcription-provider.md
git commit -m "docs(native): mark transcription provider verification"
```

## Spec Coverage

- Covers transcription provider status and provider error classification from the native rewrite testing strategy.
- Prevents the current static empty transcript behavior from silently skipping insertion when ASR is not configured.
- Leaves real Doubao/WebSocket transport, Keychain credential storage, streaming partials, text injection, HUD overlay, and release packaging as separate executable slices.

