# Voco Native Recording Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move native Voco recording control from direct status toggles to a Swift service workflow that can run audio capture, transcription, and text injection in one app process.

**Architecture:** Add focused service protocols in `VocoAppCore` for audio capture, transcription, and text injection. `NativeRecordingWorkflow` composes those services, and `AppCoordinator` owns only user-facing state transitions and diagnostic snapshots.

**Tech Stack:** Swift 6, SwiftUI, XCTest, existing `VocoAppCore` dependency injection pattern.

---

## File Structure

- Create `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`
  - Defines `CapturedAudioSnapshot`, `TranscriptSnapshot`, `TextInjectionSnapshot`, engine protocols, `NativeRecordingWorkflow`, and `StaticRecordingWorkflow`.
- Modify `native/Sources/VocoAppCore/AppCoordinator.swift`
  - Injects `RecordingWorkflowing`, adds `injecting` runtime status, and routes menu/hotkey recording actions through async workflow methods.
- Modify `native/Sources/VocoApp/VocoNativeApp.swift`
  - Uses the default native workflow dependency for the shipping app shell.
- Modify `native/Sources/VocoApp/SettingsView.swift`
  - Surfaces last transcript/injection diagnostic snapshots when available.
- Create `native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift`
  - Tests workflow composition and fail-loud behavior with fake engines.
- Modify `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`
  - Tests coordinator workflow start, stop, success, and failure state transitions.

## Task 1: Recording Workflow Core

**Files:**
- Create: `native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift`
- Create: `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`

- [ ] **Step 1: Write failing workflow tests**

Create `native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift` with tests that assert:
- `NativeRecordingWorkflow.startRecording()` calls the audio engine.
- `NativeRecordingWorkflow.stopRecording()` stops audio, transcribes captured audio, injects non-empty final text, and returns diagnostic snapshots.
- Empty final text skips injection and reports a skipped-empty insertion strategy.
- Audio start failure is thrown with a descriptive localized message.

- [ ] **Step 2: Run workflow tests and verify RED**

Run:

```bash
cd native && swift test --filter RecordingWorkflowTests
```

Expected: build fails because `NativeRecordingWorkflow`, service protocols, and snapshot types do not exist.

- [ ] **Step 3: Implement workflow models**

Create `native/Sources/VocoAppCore/RecordingWorkflowModels.swift` with:
- `CapturedAudioSnapshot`
- `TranscriptSnapshot`
- `TextInjectionStrategy`
- `TextInjectionSnapshot`
- `RecordingWorkflowResult`
- `RecordingWorkflowError`
- `AudioCaptureProviding`
- `TranscriptionProviding`
- `TextInjectionProviding`
- `RecordingWorkflowing`
- `NativeRecordingWorkflow`
- `StaticRecordingWorkflow`

- [ ] **Step 4: Run workflow tests and verify GREEN**

Run:

```bash
cd native && swift test --filter RecordingWorkflowTests
```

Expected: all `RecordingWorkflowTests` pass.

- [ ] **Step 5: Commit workflow core**

Run:

```bash
git add native/Sources/VocoAppCore/RecordingWorkflowModels.swift native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift docs/superpowers/plans/2026-05-06-voco-native-recording-workflow.md
git commit -m "feat(native): add recording workflow core"
```

## Task 2: Coordinator Workflow Routing

**Files:**
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift`

- [ ] **Step 1: Write failing coordinator tests**

Extend `AppCoordinatorTests` with tests that assert:
- starting recording calls `RecordingWorkflowing.startRecording()` and moves to `.recording`;
- stopping recording calls `RecordingWorkflowing.stopRecording()`, records transcript/injection snapshots, and returns to `.ready`;
- workflow start failure moves to `.error` with a user-visible message;
- workflow stop failure moves to `.error` with a user-visible message;
- hotkey toggle actions use the same workflow routing as menu actions.

- [ ] **Step 2: Run coordinator tests and verify RED**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: selected tests fail because `AppCoordinator` still uses direct status transitions.

- [ ] **Step 3: Implement async coordinator routing**

Modify `AppCoordinator` so:
- init accepts `recordingWorkflow: any RecordingWorkflowing = StaticRecordingWorkflow()`;
- `.ready` start sets `.recording` and awaits `recordingWorkflow.startRecording()`;
- `.recording` stop sets `.transcribing`, awaits `recordingWorkflow.stopRecording()`, sets `.injecting` when insertion ran, stores diagnostic snapshots, then returns to `.ready`;
- workflow errors call `fail(_:)` with localized messages;
- menu and hotkey entrypoints call the same async recording action.

- [ ] **Step 4: Run coordinator tests and verify GREEN**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: all `AppCoordinatorTests` pass.

- [ ] **Step 5: Wire app default dependency**

Modify `VocoNativeApp` to pass `recordingWorkflow: StaticRecordingWorkflow()` explicitly while real native provider work is still absent from the shipping package.

- [ ] **Step 6: Commit coordinator routing**

Run:

```bash
git add native/Sources/VocoAppCore/AppCoordinator.swift native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift native/Sources/VocoApp/VocoNativeApp.swift
git commit -m "feat(native): route recording through workflow"
```

## Task 3: Settings Diagnostics Surface

**Files:**
- Modify: `native/Sources/VocoApp/SettingsView.swift`
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Add diagnostic snapshot assertions**

Extend coordinator tests to assert `lastTranscript` and `lastInjection` are retained after a successful stop flow.

- [ ] **Step 2: Implement settings diagnostics rows**

Add compact settings rows that show:
- last transcript provider and final text length;
- last injection target app and strategy;
- failure text from `lastErrorMessage`.

- [ ] **Step 3: Run native tests**

Run:

```bash
cd native && swift test
```

Expected: all native tests pass.

- [ ] **Step 4: Commit diagnostics surface**

Run:

```bash
git add native/Sources/VocoApp/SettingsView.swift native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift
git commit -m "feat(native): show recording diagnostics"
```

## Task 4: Verification

**Files:**
- Verify generated bundle under `target/native/Voco.app`

- [ ] **Step 1: Run full native test suite**

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

Expected: bundle builds, app icon is generated, legacy binaries are absent, codesign verifies, and app does not exit during launch.

- [ ] **Step 3: Run diff and signature checks**

Run:

```bash
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Expected: both commands exit 0.

- [ ] **Step 4: Commit verification notes if code changed during verification**

Run only if verification required code changes:

```bash
git add native docs/superpowers/plans/2026-05-06-voco-native-recording-workflow.md
git commit -m "test(native): verify recording workflow refactor"
```

## Spec Coverage

- Covers the spec requirement that `AppCoordinator` wires hotkey events, audio capture, transcription, and text injection through service objects.
- Covers the normal-use state path from hotkey/menu action to recording, transcribing, injection diagnostics, and ready/error.
- Covers fail-loud behavior for native service failures.
- Leaves real `AVAudioEngine`, real ASR provider, accessibility insertion implementation, in-process HUD overlay, Keychain storage, and notarized DMG as separate executable slices because each one has its own permissions, APIs, and verification surface.
