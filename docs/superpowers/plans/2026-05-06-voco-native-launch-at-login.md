# Voco Native Launch at Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the shell-only `登录时启动` toggle with real macOS Login Items state through `SMAppService.mainApp`.

**Architecture:** Keep a testable launch-at-login protocol and state model in `VocoAppCore`; inject the real ServiceManagement implementation from `VocoApp`. `AppCoordinator` owns the published state and error handling, while SwiftUI menu/settings controls call async coordinator actions.

**Tech Stack:** Swift 6.0, SwiftUI, ServiceManagement `SMAppService.mainApp`, XCTest, shell bundle smoke tests.

---

## File Structure

- Create: `native/Sources/VocoAppCore/LaunchAtLoginModels.swift` — state enum and provider protocol.
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift` — inject provider, publish state, perform async enable/disable requests.
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift` — fake provider tests for success and failure.
- Create: `native/Tests/VocoAppCoreTests/LaunchAtLoginModelsTests.swift` — state labels and enabled mapping tests.
- Create: `native/Sources/VocoApp/MacLaunchAtLoginProvider.swift` — `SMAppService.mainApp` adapter.
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift` — make menu toggle call async launch-at-login action.
- Modify: `native/Sources/VocoApp/SettingsView.swift` — show launch-at-login status and toggle in settings.
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-launch-at-login.md` — record verification results.

## Task 1: Launch at Login Models

- [ ] **Step 1: Write failing model tests**

Create `LaunchAtLoginModelsTests` expecting:

```swift
XCTAssertTrue(LaunchAtLoginState.enabled.isEnabled)
XCTAssertFalse(LaunchAtLoginState.disabled.isEnabled)
XCTAssertEqual(LaunchAtLoginState.requiresApproval.title, "需要批准")
XCTAssertEqual(LaunchAtLoginState.unavailable.title, "不可用")
```

- [ ] **Step 2: Run RED**

```bash
cd native && swift test --filter LaunchAtLoginModelsTests
```

Expected: compile failure because `LaunchAtLoginState` does not exist.

- [ ] **Step 3: Implement models**

Create `LaunchAtLoginModels.swift` with `LaunchAtLoginState`, `LaunchAtLoginProviding`, and `StaticLaunchAtLoginProvider`.

- [ ] **Step 4: Run GREEN**

```bash
cd native && swift test --filter LaunchAtLoginModelsTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add native/Sources/VocoAppCore/LaunchAtLoginModels.swift native/Tests/VocoAppCoreTests/LaunchAtLoginModelsTests.swift
git commit -m "feat(native): add launch at login models"
```

## Task 2: Coordinator Wiring

- [ ] **Step 1: Write failing coordinator tests**

Add a fake launch-at-login provider to `AppCoordinatorTests`. Cover successful enable, successful disable, and provider failure surfacing through `lastErrorMessage`.

- [ ] **Step 2: Run RED**

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: compile failure because coordinator has no launch-at-login provider.

- [ ] **Step 3: Implement coordinator wiring**

Inject `launchAtLoginProvider`, publish `launchAtLoginState`, and replace shell-only state mutation with async `setLaunchAtLoginEnabled(_:)`.

- [ ] **Step 4: Run GREEN**

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add native/Sources/VocoAppCore/AppCoordinator.swift native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift
git commit -m "feat(native): wire launch at login state"
```

## Task 3: Native ServiceManagement Provider and UI

- [ ] **Step 1: Implement ServiceManagement adapter**

Create `MacLaunchAtLoginProvider` mapping `SMAppService.mainApp.status` to `LaunchAtLoginState`, calling `register()` when enabled and `unregister()` when disabled.

- [ ] **Step 2: Inject provider and update menu toggle**

Pass `MacLaunchAtLoginProvider()` to `AppCoordinator` and call `Task { await coordinator.setLaunchAtLoginEnabled(value) }` from SwiftUI toggle bindings.

- [ ] **Step 3: Render settings status**

Show Login Items state in settings with a toggle and status text. If state is `requiresApproval`, show a hint that the user must approve Voco in System Settings → General → Login Items.

- [ ] **Step 4: Run Swift tests**

```bash
cd native && swift test
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add native/Sources/VocoApp/MacLaunchAtLoginProvider.swift native/Sources/VocoApp/VocoNativeApp.swift native/Sources/VocoApp/SettingsView.swift
git commit -m "feat(native): use SMAppService for launch at login"
```

## Task 4: Verification

- [ ] **Step 1: Run bundle smoke**

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Expected: app bundle builds, signs, and launches.

- [ ] **Step 2: Run final checks**

```bash
cd native && swift test
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Expected: all commands pass.

- [ ] **Step 3: Record results and commit**

Append results under `## Verification Results`, then commit this plan file.

## Verification Results

Completed on 2026-05-06:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Result: PASS. The command built `target/native/Voco.app`, generated `Voco.icns`, verified the bundle signature, checked app/menu icon resources, launched the app for smoke validation, and exited with `ok: native Voco.app bundle smoke passed`.

```bash
cd native && swift test
```

Result: PASS. XCTest executed 19 tests with 0 failures across `AppCoordinatorTests`, `LaunchAtLoginModelsTests`, `PermissionModelsTests`, and `SettingsSectionTests`.

```bash
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Result: PASS. No whitespace errors were reported and the generated app bundle passed strict codesign verification.
