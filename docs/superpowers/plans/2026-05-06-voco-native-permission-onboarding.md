# Voco Native Permission Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first native permission onboarding slice to `Voco.app`: microphone, accessibility, and input-monitoring status are checked in-process and surfaced through the menu/settings shell.

**Architecture:** Keep permission data models and coordinator state in `VocoAppCore` so they are unit-testable without touching macOS TCC. Put real macOS API calls in `VocoApp/MacPermissionProvider.swift`, then inject that provider into `AppCoordinator` from the app entry point. Settings UI renders permission rows and recovery actions; the app still ships as an agent-style menu bar app with no Dock icon.

**Tech Stack:** Swift 6.0, SwiftUI, AppKit `NSWorkspace`, AVFoundation `AVCaptureDevice`, ApplicationServices `AXIsProcessTrusted`, CoreGraphics `CGPreflightListenEventAccess`, XCTest, shell bundle smoke tests.

---

## File Structure

- Create: `native/Sources/VocoAppCore/PermissionModels.swift` — permission kind, grant state, snapshot, summary, and provider protocol.
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift` — store permission snapshots, refresh permission status, request microphone access, and map missing permissions into app runtime state.
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift` — add fake permission provider tests for onboarding and refresh behavior.
- Create: `native/Tests/VocoAppCoreTests/PermissionModelsTests.swift` — cover permission labels, recovery URLs, and summary behavior.
- Create: `native/Sources/VocoApp/MacPermissionProvider.swift` — native macOS permission checker/requester.
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift` — inject `MacPermissionProvider` and add a menu action to check permissions.
- Modify: `native/Sources/VocoApp/SettingsView.swift` — render permission onboarding rows, refresh button, microphone request, and System Settings links.
- Modify: `packaging/tests/native_app_bundle_smoke.sh` — keep checking `NSMicrophoneUsageDescription`; no new bundle artifact is required.
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-permission-onboarding.md` — record final verification results.

## Task 1: Permission Model Red Tests

**Files:**
- Create: `native/Tests/VocoAppCoreTests/PermissionModelsTests.swift`
- Create: `native/Sources/VocoAppCore/PermissionModels.swift`

- [ ] **Step 1: Write failing permission model tests**

Create `PermissionModelsTests` with tests that expect:

```swift
XCTAssertEqual(PermissionKind.microphone.title, "麦克风")
XCTAssertEqual(PermissionKind.accessibility.settingsURLString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
XCTAssertTrue(PermissionGrantState.granted.isGranted)
XCTAssertFalse(PermissionGrantState.denied.isGranted)
XCTAssertFalse(PermissionSummary(snapshots: [.microphone(.granted), .accessibility(.denied), .inputMonitoring(.granted)]).allRequiredGranted)
```

- [ ] **Step 2: Run model tests and verify RED**

Run:

```bash
cd native && swift test --filter PermissionModelsTests
```

Expected: compile failure because `PermissionKind`, `PermissionGrantState`, and `PermissionSummary` do not exist.

- [ ] **Step 3: Implement permission models**

Create `PermissionModels.swift` with:

```swift
import Foundation

public enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case microphone
    case accessibility
    case inputMonitoring
}

public enum PermissionGrantState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
    case unknown
}

public struct PermissionSnapshot: Equatable, Sendable, Identifiable {
    public let kind: PermissionKind
    public let state: PermissionGrantState
    public let isRequired: Bool
}

public struct PermissionSummary: Equatable, Sendable {
    public let snapshots: [PermissionSnapshot]
    public var allRequiredGranted: Bool
}

public protocol PermissionProviding {
    func currentSnapshots() -> [PermissionSnapshot]
    func requestMicrophoneAccess() async -> [PermissionSnapshot]
}
```

Add exact user-facing titles, symbols, descriptions, recovery button text, and System Settings URLs as computed properties on `PermissionKind`.

- [ ] **Step 4: Run model tests and verify GREEN**

Run:

```bash
cd native && swift test --filter PermissionModelsTests
```

Expected: all `PermissionModelsTests` pass.

- [ ] **Step 5: Commit permission models**

```bash
git add native/Sources/VocoAppCore/PermissionModels.swift native/Tests/VocoAppCoreTests/PermissionModelsTests.swift
git commit -m "feat(native): add permission onboarding models"
```

## Task 2: Coordinator Permission State

**Files:**
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Write failing coordinator tests**

Add a fake provider in `AppCoordinatorTests`:

```swift
private final class FakePermissionProvider: PermissionProviding {
    var current: [PermissionSnapshot]
    var requested: [PermissionSnapshot]

    init(current: [PermissionSnapshot], requested: [PermissionSnapshot]) {
        self.current = current
        self.requested = requested
    }

    func currentSnapshots() -> [PermissionSnapshot] { current }
    func requestMicrophoneAccess() async -> [PermissionSnapshot] { requested }
}
```

Add tests proving:

```swift
// hasCompletedOnboarding true + denied microphone => finishLaunching sets .needsOnboarding
// ready app + denied accessibility after refreshPermissions() => .permissionNeeded
// requestMicrophonePermission() updates snapshots and returns ready when all required permissions are granted
```

- [ ] **Step 2: Run coordinator tests and verify RED**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: compile failure because `AppCoordinator` has no permission provider injection or permission refresh methods.

- [ ] **Step 3: Implement coordinator permission state**

Update `AppCoordinator`:

```swift
@Published public private(set) var permissions: [PermissionSnapshot]
private let permissionProvider: PermissionProviding

public var permissionSummary: PermissionSummary {
    PermissionSummary(snapshots: permissions)
}

public func refreshPermissions()
public func requestMicrophonePermission() async
```

`finishLaunching()` must refresh permissions and set `.ready` only when onboarding is complete and all required permissions are granted. `refreshPermissions()` must move `.ready` to `.permissionNeeded` when permissions are missing and move `.permissionNeeded` back to `.ready` after recovery.

- [ ] **Step 4: Run coordinator tests and verify GREEN**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: all coordinator tests pass.

- [ ] **Step 5: Commit coordinator permission state**

```bash
git add native/Sources/VocoAppCore/AppCoordinator.swift native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift
git commit -m "feat(native): wire permission state into app coordinator"
```

## Task 3: Native macOS Permission Provider and UI

**Files:**
- Create: `native/Sources/VocoApp/MacPermissionProvider.swift`
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift`
- Modify: `native/Sources/VocoApp/SettingsView.swift`

- [ ] **Step 1: Implement native permission provider**

Create `MacPermissionProvider` that maps:

```swift
AVCaptureDevice.authorizationStatus(for: .audio)
AXIsProcessTrusted()
CGPreflightListenEventAccess()
```

to `PermissionSnapshot` values for `.microphone`, `.accessibility`, and `.inputMonitoring`. `requestMicrophoneAccess()` must call `AVCaptureDevice.requestAccess(for: .audio)` and then return fresh snapshots.

- [ ] **Step 2: Inject provider in the app**

In `VocoNativeApp.init()`, create:

```swift
let appCoordinator = AppCoordinator(permissionProvider: MacPermissionProvider())
```

Keep `NSApplication.shared.setActivationPolicy(.accessory)`.

- [ ] **Step 3: Add menu action**

Add a menu button labeled `检查权限` that calls `coordinator.refreshPermissions()` and opens the settings window.

- [ ] **Step 4: Render onboarding rows in settings**

`SettingsView` must show each permission with:

```text
title
description
status text
status symbol
重新检查
请求麦克风权限 (only for microphone when not granted)
打开系统设置 (for non-granted permissions)
```

Use `NSWorkspace.shared.open(URL(string: snapshot.kind.settingsURLString)!)` for System Settings links. Network/IO errors are not involved; invalid URL construction must fail loud during development by leaving the button disabled if URL creation fails.

- [ ] **Step 5: Run full Swift tests**

Run:

```bash
cd native && swift test
```

Expected: all native tests pass.

- [ ] **Step 6: Commit native permission UI**

```bash
git add native/Sources/VocoApp/MacPermissionProvider.swift native/Sources/VocoApp/VocoNativeApp.swift native/Sources/VocoApp/SettingsView.swift
git commit -m "feat(native): surface native permission onboarding"
```

## Task 4: Bundle Smoke and Verification

**Files:**
- Modify: `packaging/tests/native_app_bundle_smoke.sh`
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-permission-onboarding.md`

- [ ] **Step 1: Run bundle smoke**

Run:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Expected: generated `target/native/Voco.app` passes plist, icon, signature, menu bar resource, and launch checks.

- [ ] **Step 2: Run final verification commands**

Run:

```bash
cd native && swift test
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Expected: all commands pass.

- [ ] **Step 3: Record verification results**

Append the observed verification commands and pass/fail result to this plan under `## Verification Results`.

- [ ] **Step 4: Commit verification notes**

```bash
git add docs/superpowers/plans/2026-05-06-voco-native-permission-onboarding.md
git commit -m "docs(native): mark permission onboarding verification"
```

## Verification Results

Completed on 2026-05-06:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Result: PASS. The command built `target/native/Voco.app`, generated `Voco.icns`, verified the bundle signature, checked native app icon and menu bar icon resources, launched the app for smoke validation, and exited with `ok: native Voco.app bundle smoke passed`.

```bash
cd native && swift test
```

Result: PASS. XCTest executed 14 tests with 0 failures across `AppCoordinatorTests`, `PermissionModelsTests`, and `SettingsSectionTests`.

```bash
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Result: PASS. No whitespace errors were reported and the generated app bundle passed strict codesign verification.
