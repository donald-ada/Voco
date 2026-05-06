# Voco Native Remaining Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the remaining native macOS rewrite work in eight verifiable slices, starting by integrating the completed Keychain credentials branch and then landing ASR, settings, diagnostics, onboarding, release packaging, migration cleanup, and manual UX verification.

**Architecture:** This is a roadmap plan, not a single oversized code-change plan. Each subsystem slice must produce its own focused implementation plan before code changes begin, because ASR, settings, diagnostics, onboarding, packaging, migration, and manual verification have different files, risks, and acceptance criteria. The execution order is strict so `master` stays usable after each slice.

**Tech Stack:** Swift 6, SwiftUI, XCTest, AppKit, AVFoundation, Security Keychain Services, URLSession/WebSocket, shell packaging scripts, macOS signing/notarization tools, existing Superpowers TDD and verification workflows.

---

## Baseline

Current known state before this roadmap:

- Current branch: `codex/native-keychain-credentials`.
- Current completed branch head: `59e28ec docs(native): mark keychain credential verification`.
- `master` is still at `936cb56 docs(native): mark hud overlay verification`.
- The Keychain credentials slice has fresh verification evidence: `cd native && swift test` executed 69 tests with 0 failures.

Before starting Task 1, run:

```bash
git status --short --branch
git log --oneline --decorate --max-count=8
```

Expected:

- Worktree is clean.
- `codex/native-keychain-credentials` contains `59e28ec`.
- `master` is an ancestor of the current branch.

## Execution Rules

- Complete tasks in numeric order.
- Each implementation task must start from a dedicated plan saved under `docs/superpowers/plans/`.
- Each code-changing task must use TDD: write failing tests, run RED, implement, run GREEN, then commit.
- Each completed branch must run fresh verification before merge or PR.
- Do not remove Rust CLI/daemon code until the migration cleanup task explicitly reaches that step.
- Network-backed ASR tests must be opt-in and must fail loudly when credentials or network are unavailable.

## File Structure

Roadmap plan:

- Create `docs/superpowers/plans/2026-05-06-voco-native-remaining-roadmap.md` — this ordered plan.

Dedicated implementation plans to create during execution:

- `docs/superpowers/plans/2026-05-06-voco-native-doubao-asr-provider.md`
- `docs/superpowers/plans/2026-05-06-voco-native-settings-completion.md`
- `docs/superpowers/plans/2026-05-06-voco-native-diagnostics.md`
- `docs/superpowers/plans/2026-05-06-voco-native-first-run-onboarding.md`
- `docs/superpowers/plans/2026-05-06-voco-native-release-packaging.md`
- `docs/superpowers/plans/2026-05-06-voco-native-migration-cleanup.md`
- `docs/superpowers/plans/2026-05-06-voco-native-manual-ux-verification.md`

Expected code areas by subsystem:

- ASR: `native/Sources/VocoAppCore/TranscriptionModels.swift`, `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`, `native/Sources/VocoAppCore/AppCoordinator.swift`, `native/Sources/VocoApp/MacDoubaoTranscriptionProvider.swift`, `native/Sources/VocoApp/VocoNativeApp.swift`, `native/Tests/VocoAppCoreTests/`.
- Settings: `native/Sources/VocoAppCore/SettingsSection.swift`, `native/Sources/VocoApp/SettingsView.swift`, new focused model files under `native/Sources/VocoAppCore/`, and tests under `native/Tests/VocoAppCoreTests/`.
- Diagnostics: new core models under `native/Sources/VocoAppCore/`, SwiftUI views and presenter under `native/Sources/VocoApp/`, and diagnostics tests under `native/Tests/VocoAppCoreTests/`.
- Onboarding: new core models under `native/Sources/VocoAppCore/`, SwiftUI onboarding views under `native/Sources/VocoApp/`, app launch wiring in `native/Sources/VocoApp/VocoNativeApp.swift`, and tests under `native/Tests/VocoAppCoreTests/`.
- Packaging: `packaging/`, `native/Resources/`, and packaging tests under `packaging/tests/`.
- Migration cleanup: `packaging/`, `docs/`, legacy launch agent assets, Rust package references, and native migration detector files.
- Manual UX verification: docs checklist under `docs/superpowers/` or `packaging/tests/`, with no production runtime dependency.

## Task 1: Integrate Keychain Credentials Branch

**Files:**
- No code files.
- Existing branch: `codex/native-keychain-credentials`.

- [ ] **Step 1: Verify feature branch state**

Run from `/private/tmp/voco-native-keychain-credentials`:

```bash
git status --short --branch
git merge-base --is-ancestor master HEAD
git log --oneline --decorate --max-count=6
```

Expected:

- Status shows `## codex/native-keychain-credentials`.
- `git merge-base --is-ancestor master HEAD` exits 0.
- Log contains `59e28ec docs(native): mark keychain credential verification`.

- [ ] **Step 2: Merge into master locally**

Run from `/Users/zhangxiaolong/claude-dev/app/Voco`:

```bash
git status --short --branch
git remote -v
git checkout master
git merge --ff-only codex/native-keychain-credentials
```

Expected:

- `git status --short --branch` is clean before checkout.
- `git remote -v` may be empty in this repository; if empty, do not run `git pull`.
- Merge fast-forwards `master` to `59e28ec`.

- [ ] **Step 3: Verify merged master**

Run from `/Users/zhangxiaolong/claude-dev/app/Voco/native`:

```bash
swift test
```

Expected: XCTest executes 69 tests with 0 failures.

- [ ] **Step 4: Cleanup feature worktree and branch**

Run from `/Users/zhangxiaolong/claude-dev/app/Voco`:

```bash
git worktree remove /private/tmp/voco-native-keychain-credentials
git branch -d codex/native-keychain-credentials
git status --short --branch
```

Expected:

- Worktree is removed.
- Branch is deleted.
- `master` is clean.

## Task 2: Real Doubao ASR Provider and Streaming Transcript

**Files:**
- Create plan: `docs/superpowers/plans/2026-05-06-voco-native-doubao-asr-provider.md`
- Expected create: `native/Sources/VocoApp/MacDoubaoTranscriptionProvider.swift`
- Expected create or modify: `native/Sources/VocoAppCore/TranscriptionModels.swift`
- Expected modify: `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`
- Expected modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Expected modify: `native/Sources/VocoApp/VocoNativeApp.swift`
- Expected tests: `native/Tests/VocoAppCoreTests/TranscriptionModelsTests.swift`, `native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift`, `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Write the dedicated ASR implementation plan**

Create `docs/superpowers/plans/2026-05-06-voco-native-doubao-asr-provider.md` with these required tasks:

```text
Task 1: Transcript streaming core models
Task 2: Recording workflow streaming callbacks
Task 3: Coordinator partial transcript state
Task 4: Doubao provider request/auth/error mapping
Task 5: App wiring from Keychain credentials to provider
Task 6: Opt-in live provider smoke test
Task 7: Full verification and documentation
```

Expected:

- The plan has exact file paths.
- The plan includes RED/GREEN test steps for all core model and coordinator behavior.
- Live network tests are ignored or opt-in through an explicit environment variable.

- [ ] **Step 2: Execute ASR core model tests first**

Run the ASR plan's first RED command, expected shape:

```bash
cd native && swift test --filter TranscriptionModelsTests
```

Expected: tests fail before new streaming transcript model or provider status behavior exists.

- [ ] **Step 3: Implement ASR provider slice**

Use the dedicated ASR plan. Minimum outcome:

- `UnavailableTranscriptionProvider` remains available for tests.
- A real Doubao provider can read API credentials through `TranscriptionCredentialStoring`.
- Missing credentials produce a user-visible auth/configuration error.
- Provider network failures include descriptive messages.
- Partial transcript updates can reach `AppCoordinator` and `HUDSnapshot`.

- [ ] **Step 4: Verify ASR slice**

Run:

```bash
cd native && swift test
packaging/tests/native_app_bundle_smoke.sh
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Expected:

- Native tests pass.
- Bundle smoke passes.
- No whitespace errors.
- Signed bundle verifies.

- [ ] **Step 5: Commit and merge ASR slice**

Expected commits:

```bash
git commit -m "docs(native): plan doubao asr provider"
git commit -m "feat(native): add streaming transcription models"
git commit -m "feat(native): wire partial transcripts into coordinator"
git commit -m "feat(native): add doubao transcription provider"
git commit -m "docs(native): mark doubao asr verification"
```

Expected final state:

- ASR branch merged back to `master`.
- Dedicated ASR worktree cleaned up after merge.

## Task 3: Complete Settings Surface

**Files:**
- Create plan: `docs/superpowers/plans/2026-05-06-voco-native-settings-completion.md`
- Expected modify: `native/Sources/VocoAppCore/SettingsSection.swift`
- Expected modify: `native/Sources/VocoApp/SettingsView.swift`
- Expected create: `native/Sources/VocoAppCore/AudioSettingsModels.swift`
- Expected create: `native/Sources/VocoAppCore/InjectionSettingsModels.swift`
- Expected create: `native/Sources/VocoAppCore/HUDSettingsModels.swift`
- Expected create: `native/Sources/VocoAppCore/PrivacySettingsModels.swift`
- Expected tests: matching model tests in `native/Tests/VocoAppCoreTests/`

- [ ] **Step 1: Write the dedicated Settings implementation plan**

Create `docs/superpowers/plans/2026-05-06-voco-native-settings-completion.md` with these required tasks:

```text
Task 1: Audio settings models
Task 2: Injection settings models
Task 3: HUD settings models
Task 4: Privacy settings models
Task 5: SettingsView section rendering
Task 6: Coordinator settings snapshot wiring
Task 7: Full verification and documentation
```

Expected:

- Each settings model has user-visible title/detail tests.
- Settings state is testable in `VocoAppCore`.
- SwiftUI remains a thin rendering layer.

- [ ] **Step 2: Execute model-first TDD**

Run expected RED commands from the Settings plan:

```bash
cd native && swift test --filter AudioSettingsModelsTests
cd native && swift test --filter InjectionSettingsModelsTests
cd native && swift test --filter HUDSettingsModelsTests
cd native && swift test --filter PrivacySettingsModelsTests
```

Expected: each filter fails before its model file exists.

- [ ] **Step 3: Implement Settings surface**

Use the dedicated Settings plan. Minimum outcome:

- Audio section shows input device, level meter status, and sample rate status.
- Injection section shows insertion strategy and focused app diagnostics.
- HUD section exposes position, notch mode, and transcript preview visibility.
- Privacy section shows Keychain status, transcript retention policy, and logs policy.
- Existing launch-at-login, hotkey, transcription credential, recording diagnostic, and permission content remains intact.

- [ ] **Step 4: Verify Settings slice**

Run:

```bash
cd native && swift test
packaging/tests/native_app_bundle_smoke.sh
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit and merge Settings slice**

Expected commits:

```bash
git commit -m "docs(native): plan settings completion"
git commit -m "feat(native): add native settings models"
git commit -m "feat(native): complete settings sections"
git commit -m "docs(native): mark settings completion verification"
```

## Task 4: Diagnostics Window and Export

**Files:**
- Create plan: `docs/superpowers/plans/2026-05-06-voco-native-diagnostics.md`
- Expected create: `native/Sources/VocoAppCore/DiagnosticsModels.swift`
- Expected create: `native/Sources/VocoAppCore/DiagnosticBundleModels.swift`
- Expected create: `native/Sources/VocoApp/DiagnosticsView.swift`
- Expected create: `native/Sources/VocoApp/DiagnosticsWindowPresenter.swift`
- Expected modify: `native/Sources/VocoApp/VocoNativeApp.swift`
- Expected tests: `native/Tests/VocoAppCoreTests/DiagnosticsModelsTests.swift`

- [ ] **Step 1: Write the dedicated Diagnostics implementation plan**

Create `docs/superpowers/plans/2026-05-06-voco-native-diagnostics.md` with these required tasks:

```text
Task 1: Diagnostic event model and redaction rules
Task 2: Coordinator diagnostic event capture
Task 3: Diagnostics window presenter
Task 4: DiagnosticsView rendering
Task 5: Redacted diagnostic bundle export
Task 6: Menu bar diagnostics action
Task 7: Full verification and documentation
```

Expected:

- Tests prove secrets and transcript text are redacted by default.
- Network, IO, permission, ASR, and injection failures have descriptive diagnostic messages.
- Export failures surface user-visible messages.

- [ ] **Step 2: Execute Diagnostics RED tests**

Run:

```bash
cd native && swift test --filter DiagnosticsModelsTests
```

Expected: compile failure before diagnostics models exist.

- [ ] **Step 3: Implement Diagnostics slice**

Use the dedicated Diagnostics plan. Minimum outcome:

- Menu item opens a native Diagnostics window.
- Diagnostics list includes permission, audio, hotkey, ASR, injection, and recent failure state.
- Export writes a redacted bundle or fails loudly with a clear message.
- No raw API key or transcript body is exported by default.

- [ ] **Step 4: Verify Diagnostics slice**

Run:

```bash
cd native && swift test
packaging/tests/native_app_bundle_smoke.sh
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit and merge Diagnostics slice**

Expected commits:

```bash
git commit -m "docs(native): plan diagnostics"
git commit -m "feat(native): add diagnostics models"
git commit -m "feat(native): show diagnostics window"
git commit -m "feat(native): export redacted diagnostics bundle"
git commit -m "docs(native): mark diagnostics verification"
```

## Task 5: First-Run Onboarding

**Files:**
- Create plan: `docs/superpowers/plans/2026-05-06-voco-native-first-run-onboarding.md`
- Expected create: `native/Sources/VocoAppCore/OnboardingModels.swift`
- Expected create: `native/Sources/VocoAppCore/InstallLocationModels.swift`
- Expected create: `native/Sources/VocoApp/OnboardingView.swift`
- Expected create: `native/Sources/VocoApp/MacInstallLocationProvider.swift`
- Expected modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Expected modify: `native/Sources/VocoApp/VocoNativeApp.swift`
- Expected tests: `native/Tests/VocoAppCoreTests/OnboardingModelsTests.swift`, `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Write the dedicated Onboarding implementation plan**

Create `docs/superpowers/plans/2026-05-06-voco-native-first-run-onboarding.md` with these required tasks:

```text
Task 1: Onboarding step model
Task 2: Install location detection model
Task 3: Coordinator onboarding state transitions
Task 4: OnboardingView rendering
Task 5: DMG run-location warning
Task 6: Hotkey test step
Task 7: Full verification and documentation
```

Expected:

- Tests cover step ordering: microphone, accessibility, input monitoring, ASR setup, launch-at-login, hotkey test.
- Running from a mounted image reports an install-location warning.
- Settings can still be opened explicitly without permanently showing Voco in the Dock.

- [ ] **Step 2: Execute Onboarding RED tests**

Run:

```bash
cd native && swift test --filter OnboardingModelsTests
```

Expected: compile failure before onboarding models exist.

- [ ] **Step 3: Implement Onboarding slice**

Use the dedicated Onboarding plan. Minimum outcome:

- First launch shows a native onboarding flow when required setup is incomplete.
- Each permission step has visible status, retry action, and System Settings recovery link when needed.
- ASR setup step reflects Keychain credential state.
- Launch-at-login and hotkey test steps use existing coordinator state.

- [ ] **Step 4: Verify Onboarding slice**

Run:

```bash
cd native && swift test
packaging/tests/native_app_bundle_smoke.sh
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit and merge Onboarding slice**

Expected commits:

```bash
git commit -m "docs(native): plan first-run onboarding"
git commit -m "feat(native): add onboarding models"
git commit -m "feat(native): show first-run onboarding"
git commit -m "feat(native): warn when running from disk image"
git commit -m "docs(native): mark onboarding verification"
```

## Task 6: Release Packaging and Notarized DMG

**Files:**
- Create plan: `docs/superpowers/plans/2026-05-06-voco-native-release-packaging.md`
- Expected create: `packaging/build_native_dmg.sh`
- Expected create: `packaging/notarize_native_dmg.sh`
- Expected create: `packaging/tests/native_dmg_smoke.sh`
- Expected modify: `packaging/build_app_bundle.sh` if shared helpers are required.
- Expected docs: release verification notes under `docs/superpowers/plans/`.

- [ ] **Step 1: Write the dedicated Release Packaging implementation plan**

Create `docs/superpowers/plans/2026-05-06-voco-native-release-packaging.md` with these required tasks:

```text
Task 1: Native release bundle build flags
Task 2: Developer ID signing inputs
Task 3: Hardened runtime verification
Task 4: DMG creation with Applications alias
Task 5: DMG signing
Task 6: Notarization and stapling
Task 7: Release verification smoke tests
Task 8: Documentation and failure messages
```

Expected:

- Scripts fail loudly when signing identity, Apple credentials, or notarization inputs are missing.
- Debug smoke tests remain available without Developer ID credentials.
- Release verification uses `codesign`, `spctl`, `hdiutil`, `notarytool`, and `stapler`.

- [ ] **Step 2: Execute packaging RED smoke**

Run expected first smoke command from the packaging plan:

```bash
packaging/tests/native_dmg_smoke.sh
```

Expected: failure because the DMG smoke script does not exist yet.

- [ ] **Step 3: Implement packaging slice**

Use the dedicated Release Packaging plan. Minimum outcome:

- `target/native/Voco.app` can be built for release.
- `dist/Voco.dmg` can be produced locally.
- Debug/ad-hoc path remains separate from Developer ID release path.
- Missing notarization credentials produce clear actionable messages.

- [ ] **Step 4: Verify packaging slice**

Run:

```bash
packaging/tests/native_app_bundle_smoke.sh
packaging/tests/native_dmg_smoke.sh
git diff --check
```

If Developer ID credentials are available, also run:

```bash
codesign --verify --deep --strict dist/Voco.app
spctl --assess --type execute --verbose=4 dist/Voco.app
hdiutil verify dist/Voco.dmg
codesign --verify --strict dist/Voco.dmg
xcrun stapler validate dist/Voco.dmg
spctl --assess --type open --verbose=4 dist/Voco.dmg
```

Expected:

- Smoke tests pass.
- Release-only verification passes when credentials are present.
- When credentials are absent, release script exits with explicit missing-input messages.

- [ ] **Step 5: Commit and merge packaging slice**

Expected commits:

```bash
git commit -m "docs(native): plan release packaging"
git commit -m "feat(packaging): build native dmg"
git commit -m "feat(packaging): verify native release artifacts"
git commit -m "docs(native): mark release packaging verification"
```

## Task 7: Migration and Legacy Cleanup

**Files:**
- Create plan: `docs/superpowers/plans/2026-05-06-voco-native-migration-cleanup.md`
- Expected create: `native/Sources/VocoAppCore/LegacyInstallModels.swift`
- Expected create: `native/Sources/VocoApp/MacLegacyInstallProvider.swift`
- Expected modify: `native/Sources/VocoApp/SettingsView.swift`
- Expected modify: `docs/`
- Expected modify or remove: legacy packaging assets only after native feature parity is verified.
- Expected tests: `native/Tests/VocoAppCoreTests/LegacyInstallModelsTests.swift`

- [ ] **Step 1: Write the dedicated Migration Cleanup implementation plan**

Create `docs/superpowers/plans/2026-05-06-voco-native-migration-cleanup.md` with these required tasks:

```text
Task 1: Legacy LaunchAgent detection model
Task 2: Native Settings migration notice
Task 3: Explicit user-triggered legacy removal action
Task 4: CLI/daemon packaging exclusion verification
Task 5: Documentation updates for native-only install
Task 6: Feature-parity gate before deleting legacy assets
Task 7: Full verification and documentation
```

Expected:

- No legacy file is removed before the feature-parity gate step passes.
- User-level cleanup never requires `sudo`.
- Cleanup failures show exact file path and OS error.

- [ ] **Step 2: Execute migration RED tests**

Run:

```bash
cd native && swift test --filter LegacyInstallModelsTests
```

Expected: compile failure before legacy install models exist.

- [ ] **Step 3: Implement migration slice**

Use the dedicated Migration Cleanup plan. Minimum outcome:

- Native app can detect `~/Library/LaunchAgents/com.voco.daemon.plist`.
- Settings or Diagnostics can show a clear legacy-install warning.
- User-triggered removal action removes only the known legacy LaunchAgent plist.
- Final native app bundle excludes user-facing CLI, daemon, and helper binaries.

- [ ] **Step 4: Verify migration slice**

Run:

```bash
cd native && swift test
packaging/tests/native_app_bundle_smoke.sh
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit and merge migration slice**

Expected commits:

```bash
git commit -m "docs(native): plan migration cleanup"
git commit -m "feat(native): detect legacy launch agent"
git commit -m "feat(native): surface legacy cleanup action"
git commit -m "docs(native): update native install guidance"
git commit -m "docs(native): mark migration cleanup verification"
```

## Task 8: Manual UX Verification on macOS

**Files:**
- Create plan: `docs/superpowers/plans/2026-05-06-voco-native-manual-ux-verification.md`
- Expected create: `docs/superpowers/native-manual-ux-checklist.md`
- Expected update: final verification section in the task plan.

- [ ] **Step 1: Write the dedicated Manual UX verification plan**

Create `docs/superpowers/plans/2026-05-06-voco-native-manual-ux-verification.md` with these required tasks:

```text
Task 1: Clean account setup checklist
Task 2: First launch verification
Task 3: Permission recovery verification
Task 4: Hotkey focus verification
Task 5: HUD focus verification
Task 6: Text insertion target matrix
Task 7: Launch-at-login verification
Task 8: Release artifact Gatekeeper verification
Task 9: Result recording and issue follow-up
```

Expected:

- The checklist records exact macOS version, app path, build hash, and signing status.
- Each manual result has `PASS`, `FAIL`, or `BLOCKED`.
- Failures produce a follow-up issue or implementation plan before release.

- [ ] **Step 2: Create the manual checklist**

Create `docs/superpowers/native-manual-ux-checklist.md` with this required matrix:

```text
Environment
- macOS version
- machine model
- Voco build hash
- app path
- signing status

First Launch
- menu bar item appears
- Dock icon absent
- Settings opens only when requested
- DMG run-location warning appears when applicable

Permissions
- microphone prompt
- accessibility recovery link
- input monitoring recovery link

Recording
- global hotkey starts recording
- Voco does not steal focus
- HUD appears near notch/top center
- partial transcript updates appear when ASR streaming is configured

Insertion Targets
- TextEdit
- Safari text field
- Notes
- terminal editor

Lifecycle
- launch-at-login works after logout/login
- quitting Voco removes menu bar item

Release Artifacts
- codesign verification
- spctl app assessment
- hdiutil DMG verification
- stapler DMG validation
- spctl DMG assessment
```

- [ ] **Step 3: Execute manual verification**

Run the release build and manual checklist commands from the dedicated plan.

Expected:

- Every required manual row is marked `PASS`, `FAIL`, or `BLOCKED`.
- Each `FAIL` or `BLOCKED` row links to a concrete follow-up plan or issue.

- [ ] **Step 4: Commit manual verification artifacts**

Expected commits:

```bash
git commit -m "docs(native): plan manual ux verification"
git commit -m "docs(native): add native manual ux checklist"
git commit -m "docs(native): record native manual ux verification"
```

## Final Acceptance Gate

After Task 8 completes, run:

```bash
cd native && swift test
packaging/tests/native_app_bundle_smoke.sh
packaging/tests/native_dmg_smoke.sh
git diff --check
```

If Developer ID credentials are available, also run:

```bash
codesign --verify --deep --strict dist/Voco.app
spctl --assess --type execute --verbose=4 dist/Voco.app
hdiutil verify dist/Voco.dmg
codesign --verify --strict dist/Voco.dmg
xcrun stapler validate dist/Voco.dmg
spctl --assess --type open --verbose=4 dist/Voco.dmg
```

Expected final state:

- Users install only `Voco.app` from `Voco.dmg`.
- No CLI command is required for installation, startup, recording, settings, or diagnostics.
- Voco does not appear in the Dock during normal use.
- Settings and Diagnostics open on demand.
- Launch-at-login is controlled inside the app.
- Hotkey-to-recording latency is within the native rewrite budget.
- HUD and transcript state update without helper-process IPC.
- Text insertion succeeds in common macOS text targets.
- Required permissions have native onboarding and recovery flows.
- Release artifacts pass signing, notarization, and Gatekeeper verification when release credentials are present.

## Self-Review

Spec coverage:

- Task 1 covers integrating completed Keychain credential work into `master`.
- Task 2 covers real ASR provider, streaming partials, auth errors, and transcript flow.
- Task 3 covers remaining Settings sections.
- Task 4 covers Diagnostics and redacted export.
- Task 5 covers first-run onboarding and install-location warning.
- Task 6 covers signed, hardened, notarized DMG release packaging.
- Task 7 covers migration and legacy cleanup.
- Task 8 covers clean-machine manual UX verification.

Placeholder scan:

- The plan avoids reserved placeholder markers and names exact plan files, commands, code areas, expected outcomes, and commit subjects.

Type consistency:

- Shared names match current code direction: `AppCoordinator`, `TranscriptionModels`, `RecordingWorkflowModels`, `SettingsSection`, `SettingsView`, `HUDSnapshot`, `TranscriptionCredentialStoring`, and native `Voco.app` packaging.
