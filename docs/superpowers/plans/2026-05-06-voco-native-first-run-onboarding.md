# Voco Native First-Run Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. If any subagent is dispatched for this plan, use GPT-5.5 xhigh.

**Goal:** Add the first-run native onboarding flow for required permissions, ASR credentials, launch-at-login choice, install-location warnings, and hotkey verification.

**Architecture:** Keep onboarding step ordering, step status mapping, completion rules, and install-location detection in `VocoAppCore` so XCTest can verify behavior without AppKit. `AppCoordinator` owns the published onboarding snapshot and actions; `VocoApp` adds an accessory onboarding window that is shown when setup is incomplete and keeps settings explicit.

**Tech Stack:** Swift 6, XCTest, SwiftUI, AppKit `NSWindow`, Foundation URL/path modeling, existing `AppCoordinator`, `PermissionModels`, `TranscriptionCredentialModels`, `LaunchAtLoginModels`, and `HotkeyModels`.

---

## Baseline

User-provided baseline before this task:

```bash
cd native && swift test
```

Observed from native baseline: PASS. XCTest executed 110 tests, 1 skipped, 0 failures.

## Constraints

- Work only in `/private/tmp/voco-native-first-run-onboarding` on branch `codex/native-first-run-onboarding`.
- Do not merge to `master`.
- Do not revert or rewrite other agents' changes.
- Keep `Voco.app` as a menu bar accessory app; do not introduce a persistent Dock icon for onboarding or settings.
- Settings must still open only through an explicit user action.
- Permission recovery links must use existing `PermissionKind.settingsURLString`.
- DMG/install-location detection must be deterministic in core and testable from supplied paths.
- Network and IO failures must surface descriptive messages; no silent catches.

## File Structure

- Create `native/Sources/VocoAppCore/OnboardingModels.swift` for onboarding step identity, ordered snapshots, status labels, and completion rules.
- Create `native/Sources/VocoAppCore/InstallLocationModels.swift` for install-location status, warning copy, and a protocol used by the coordinator.
- Modify `native/Sources/VocoAppCore/AppCoordinator.swift` to publish onboarding and install-location snapshots, refresh step state, mark onboarding complete, and keep runtime state transitions consistent.
- Create `native/Sources/VocoApp/OnboardingView.swift` for native first-run rendering and actions.
- Create `native/Sources/VocoApp/OnboardingWindowPresenter.swift` for retained accessory onboarding window lifecycle.
- Create `native/Sources/VocoApp/MacInstallLocationProvider.swift` for bundle path inspection.
- Modify `native/Sources/VocoApp/VocoNativeApp.swift` to construct the coordinator with persisted onboarding completion and install-location provider, show onboarding on first launch when needed, and avoid Dock activation.
- Create `native/Tests/VocoAppCoreTests/OnboardingModelsTests.swift` for ordered steps, status mapping, completion, and install-location warning coverage.
- Modify `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift` for coordinator onboarding transitions and hotkey-test state.
- Modify this plan with final verification notes after all checks run.

## Task 1: Onboarding Step Model

**Files:**
- Create: `native/Tests/VocoAppCoreTests/OnboardingModelsTests.swift`
- Create: `native/Sources/VocoAppCore/OnboardingModels.swift`

- [ ] **Step 1: Write failing step-ordering tests**

Create tests that assert `OnboardingStepID.ordered` is exactly:

```swift
[
    .microphone,
    .accessibility,
    .inputMonitoring,
    .asrSetup,
    .launchAtLogin,
    .hotkeyTest
]
```

Also assert each step has a visible `title`, `detail`, `systemImage`, status title, retry action title, and recovery action when applicable.

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter OnboardingModelsTests
```

Expected: compile failure because onboarding model types do not exist.

- [ ] **Step 3: Implement the model**

Create `OnboardingStepID`, `OnboardingStepStatus`, `OnboardingAction`, `OnboardingStepSnapshot`, and `OnboardingSnapshot`.

Required behavior:

- Permission steps map from `PermissionSnapshot`.
- ASR step is complete only when `TranscriptionCredentialSnapshot.hasAPIKey` is true.
- Launch-at-login step is complete when launch-at-login is enabled, and remains skippable when disabled.
- Hotkey test step reflects `HotkeyRuntimeState` and a coordinator-owned `hasVerifiedHotkey` flag.
- `OnboardingSnapshot.isComplete` requires required permission steps, ASR setup, and hotkey test to be complete; launch-at-login can be skipped.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter OnboardingModelsTests
```

Expected: onboarding model tests pass.

- [ ] **Step 5: Commit**

Commit:

```bash
git add native/Sources/VocoAppCore/OnboardingModels.swift native/Tests/VocoAppCoreTests/OnboardingModelsTests.swift
git commit -m "feat(native): add onboarding models"
```

## Task 2: Install Location Detection Model

**Files:**
- Modify: `native/Tests/VocoAppCoreTests/OnboardingModelsTests.swift`
- Create: `native/Sources/VocoAppCore/InstallLocationModels.swift`

- [ ] **Step 1: Write failing install-location tests**

Add tests that assert:

- `/Volumes/Voco/Voco.app` reports a warning with title `从磁盘映像运行`.
- `/Applications/Voco.app` reports a final install location.
- `/Users/alice/Applications/Voco.app` reports a final install location.
- unknown paths are allowed but diagnostic detail includes the original path.

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter OnboardingModelsTests
```

Expected: compile failure because install-location model types do not exist.

- [ ] **Step 3: Implement the model**

Create `InstallLocationStatus`, `InstallLocationSnapshot`, `InstallLocationCheck`, and `InstallLocationProviding`.

Required behavior:

- Mounted image paths start with `/Volumes/` and are not under `/Applications` or `/Users/*/Applications`.
- Mounted image status blocks enabling launch-at-login by surfacing an onboarding warning, but it does not block trial use.
- Warning copy tells the user to move `Voco.app` to `/Applications` before enabling launch-at-login.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter OnboardingModelsTests
```

Expected: onboarding model tests pass.

## Task 3: Coordinator Onboarding State Transitions

**Files:**
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Write failing coordinator tests**

Add tests that assert:

- `finishLaunching()` with incomplete setup publishes `.needsOnboarding` and an `onboardingSnapshot` containing the six ordered steps.
- requesting microphone permission refreshes the microphone step status.
- saving an ASR API key refreshes the ASR step from action-needed to complete.
- `markLaunchAtLoginSkippedForOnboarding()` keeps onboarding available while launch-at-login remains disabled.
- `markHotkeyVerifiedForOnboarding()` completes the hotkey-test step using existing hotkey runtime state.
- completing onboarding persists through an injected completion setter and moves status to `.ready` when required setup is complete.

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: compile failure or failing assertions because coordinator onboarding APIs do not exist.

- [ ] **Step 3: Implement coordinator state**

Modify `AppCoordinator` to accept:

- `hasCompletedOnboarding: Bool`
- `setHasCompletedOnboarding: @MainActor @Sendable (Bool) -> Void`
- `installLocationProvider: any InstallLocationProviding`

Add published `onboarding`, `installLocation`, and explicit methods:

- `refreshOnboardingState()`
- `markLaunchAtLoginSkippedForOnboarding()`
- `markHotkeyVerifiedForOnboarding()`
- `completeOnboardingIfReady()`

Required behavior:

- First launch stays `.needsOnboarding` until `OnboardingSnapshot.isComplete`.
- Ready apps that later lose permissions use `.permissionNeeded`.
- Settings presentation still refreshes permissions and credentials but does not permanently show a Dock icon.
- Launch-at-login enable attempts are rejected with a descriptive warning when `installLocation.status == .mountedImage`.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: coordinator tests pass.

## Task 4: OnboardingView Rendering

**Files:**
- Create: `native/Sources/VocoApp/OnboardingView.swift`
- Create: `native/Sources/VocoApp/OnboardingWindowPresenter.swift`
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift`

- [ ] **Step 1: Add native SwiftUI view**

Create a SwiftUI onboarding window that renders:

- Install-location warning banner when present.
- Six ordered steps with visible status.
- Retry action on permission steps.
- System Settings recovery button for manual permission steps.
- ASR secure-field save and clear actions backed by coordinator credential methods.
- Launch-at-login toggle and skip action.
- Hotkey test button that marks the hotkey as verified.
- Completion button disabled until `onboarding.isComplete`.

- [ ] **Step 2: Wire retained accessory window presenter**

Create `OnboardingWindowPresenter` matching `SettingsWindowPresenter` and `DiagnosticsWindowPresenter`, using an `NSWindow` retained by the presenter. Showing onboarding may activate the app transiently, but `VocoNativeApp` must keep `NSApplication.shared.setActivationPolicy(.accessory)`.

- [ ] **Step 3: Wire app launch**

Modify `VocoNativeApp` to:

- Instantiate `AppCoordinator` with persisted completion from `UserDefaults`.
- Pass `MacInstallLocationProvider`.
- Call `finishLaunching()`.
- Show onboarding window when `coordinator.status == .needsOnboarding`.
- Keep settings and diagnostics opened only from explicit menu actions.

- [ ] **Step 4: Run build check**

Run:

```bash
cd native && swift test --filter OnboardingModelsTests
```

Expected: target compiles and focused onboarding tests still pass.

- [ ] **Step 5: Commit**

Commit:

```bash
git add native/Sources/VocoApp/OnboardingView.swift native/Sources/VocoApp/OnboardingWindowPresenter.swift native/Sources/VocoApp/VocoNativeApp.swift native/Sources/VocoAppCore/AppCoordinator.swift native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift
git commit -m "feat(native): show first-run onboarding"
```

## Task 5: DMG Run-Location Warning

**Files:**
- Create: `native/Sources/VocoApp/MacInstallLocationProvider.swift`
- Modify: `native/Sources/VocoApp/OnboardingView.swift`
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Tests/VocoAppCoreTests/OnboardingModelsTests.swift`

- [ ] **Step 1: Implement macOS provider**

Create `MacInstallLocationProvider` that reads `Bundle.main.bundleURL.path` and returns `InstallLocationCheck.snapshot(forAppBundlePath:)`.

- [ ] **Step 2: Surface warning**

Ensure the onboarding view shows `InstallLocationSnapshot.warningTitle` and `warningDetail` when running from `/Volumes/.../Voco.app`.

- [ ] **Step 3: Block launch-at-login enable from mounted image**

Ensure `AppCoordinator.setLaunchAtLoginEnabled(true)` does not call the launch provider from mounted-image locations and sets `launchAtLoginState` plus `lastErrorMessage` to descriptive values.

- [ ] **Step 4: Run focused tests**

Run:

```bash
cd native && swift test --filter OnboardingModelsTests
cd native && swift test --filter AppCoordinatorTests
```

Expected: all focused tests pass.

- [ ] **Step 5: Commit**

Commit:

```bash
git add native/Sources/VocoApp/MacInstallLocationProvider.swift native/Sources/VocoApp/OnboardingView.swift native/Sources/VocoAppCore/AppCoordinator.swift native/Sources/VocoAppCore/InstallLocationModels.swift native/Tests/VocoAppCoreTests/OnboardingModelsTests.swift native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift
git commit -m "feat(native): warn when running from disk image"
```

## Task 6: Hotkey Test Step

**Files:**
- Modify: `native/Sources/VocoAppCore/OnboardingModels.swift`
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Sources/VocoApp/OnboardingView.swift`
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Verify hotkey runtime linkage**

Add focused assertions that hotkey-test status is:

- blocked when required hotkey permissions are missing;
- action-needed when the hotkey listener is inactive;
- complete after `markHotkeyVerifiedForOnboarding()` and `HotkeyRuntimeState.listening`.

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: failing assertions until hotkey verification state is wired.

- [ ] **Step 3: Implement hotkey-test update**

Use existing `hotkeyRuntimeState`, `hotkeyBinding`, and `hotkeyMode` for the onboarding step copy and status. The UI button should not synthesize a global key event; it records that the user confirmed the configured hotkey after the runtime listener is active.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: coordinator tests pass.

## Task 7: Full Verification and Documentation

**Files:**
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-first-run-onboarding.md`

- [ ] **Step 1: Run final verification**

Run:

```bash
cd native && swift test
packaging/tests/native_app_bundle_smoke.sh
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Expected: all commands exit 0.

- [ ] **Step 2: Record verification notes**

Append the observed command outputs under `## Verification Notes`.

- [ ] **Step 3: Commit verification docs**

Commit:

```bash
git add docs/superpowers/plans/2026-05-06-voco-native-first-run-onboarding.md
git commit -m "docs(native): mark onboarding verification"
```

## Verification Notes

Pending implementation.
