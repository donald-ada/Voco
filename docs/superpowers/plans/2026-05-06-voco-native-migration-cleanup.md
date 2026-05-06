# Voco Native Migration Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. If a subagent is dispatched for any step, use GPT-5.5 xhigh.

**Goal:** Add native-only migration cleanup support so Voco detects the legacy user LaunchAgent, warns in Settings, lets the user explicitly remove only that known plist, verifies native bundles exclude legacy user-facing binaries, and documents the feature-parity gate before legacy assets are deleted.

**Architecture:** Keep migration state and failure messages in `VocoAppCore` as testable models and provider protocols. Keep macOS filesystem access in `VocoApp` with a provider scoped to `~/Library/LaunchAgents/com.voco.daemon.plist`; the UI calls coordinator actions only after user intent. Leave legacy Rust crates, LaunchAgent templates, and development packaging assets intact until Task 8 manual UX/feature-parity verification passes.

**Tech Stack:** Swift 6, XCTest, SwiftUI, Foundation `FileManager`, existing native packaging smoke scripts, Markdown docs.

---

## Baseline

User-provided baseline from `native` before this task:

```bash
cd native && swift test
```

Observed: PASS. XCTest executed 128 tests, 1 skipped, 0 failures.

## Constraints

- Work only in `/private/tmp/voco-native-migration-cleanup` on branch `codex/native-migration-cleanup`.
- Do not merge to `master`.
- Do not revert or rewrite Task 1-6 changes already merged to `master`.
- Do not remove `crates/voco-cli`, `crates/voco-daemon`, `packaging/com.voco.daemon.plist.tmpl`, `packaging/build_app_bundle.sh`, or `hud/` packaging before the feature-parity gate passes.
- User-level cleanup must never require `sudo`.
- Cleanup must only target `~/Library/LaunchAgents/com.voco.daemon.plist`.
- Cleanup failures must include the exact filesystem path and OS error text.
- The native app must not install `~/Library/LaunchAgents/com.voco.daemon.plist`.
- The final native app bundle must not contain user-facing `voco`, `voco-daemon`, or `voco-hud` binaries.

## File Structure

- Create `native/Sources/VocoAppCore/LegacyInstallModels.swift` - legacy LaunchAgent path model, status snapshot, cleanup error, and provider protocol.
- Create `native/Tests/VocoAppCoreTests/LegacyInstallModelsTests.swift` - RED/GREEN model tests for detection, no-op cleanup, exact path scoping, and descriptive failures.
- Modify `native/Sources/VocoAppCore/AppCoordinator.swift` - publish legacy install snapshot, refresh it during launch/settings presentation, and expose explicit user-triggered cleanup.
- Create `native/Sources/VocoApp/MacLegacyInstallProvider.swift` - real macOS provider using `FileManager` and `FileManager.default.homeDirectoryForCurrentUser`.
- Modify `native/Sources/VocoApp/VocoNativeApp.swift` - inject the macOS legacy provider.
- Modify `native/Sources/VocoApp/SettingsView.swift` - surface a clear migration warning/action without nested card redesign.
- Modify `native/Sources/VocoAppCore/DiagnosticsModels.swift` - include a warning event when the legacy LaunchAgent is detected.
- Modify `README.md` and `packaging/README.md` - move user install guidance to native DMG, keep legacy paths as archived/development-only.
- Modify `docs/superpowers/plans/2026-05-06-voco-native-migration-cleanup.md` - append final verification evidence.

## Task 1: Legacy LaunchAgent Detection Model

**Files:**
- Create: `native/Tests/VocoAppCoreTests/LegacyInstallModelsTests.swift`
- Create: `native/Sources/VocoAppCore/LegacyInstallModels.swift`
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Sources/VocoAppCore/DiagnosticsModels.swift`

- [ ] **Step 1: Write the failing model tests**

Create `native/Tests/VocoAppCoreTests/LegacyInstallModelsTests.swift` with tests for:

```swift
import Foundation
import XCTest
@testable import VocoAppCore

final class LegacyInstallModelsTests: XCTestCase {
    func testKnownLaunchAgentPathExpandsInsideUserLibraryOnly() {
        let home = URL(fileURLWithPath: "/Users/alice")

        let snapshot = LegacyInstallSnapshot.detected(homeDirectory: home)

        XCTAssertEqual(snapshot.launchAgentPath, "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist")
        XCTAssertEqual(snapshot.status, .detected)
        XCTAssertEqual(snapshot.title, "检测到旧版后台启动项")
        XCTAssertTrue(snapshot.detail.contains("com.voco.daemon.plist"))
        XCTAssertTrue(snapshot.requiresUserAction)
    }

    func testNoLegacyLaunchAgentHasNoUserAction() {
        let snapshot = LegacyInstallSnapshot.notFound(
            launchAgentURL: URL(fileURLWithPath: "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist")
        )

        XCTAssertEqual(snapshot.status, .notFound)
        XCTAssertEqual(snapshot.title, "未检测到旧版启动项")
        XCTAssertFalse(snapshot.requiresUserAction)
    }

    func testRemovalFailureIncludesExactPathAndUnderlyingOSError() {
        let path = "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist"
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES), userInfo: [
            NSLocalizedDescriptionKey: "Permission denied"
        ])

        let error = LegacyInstallCleanupError.removeFailed(path: path, underlying: underlying)

        XCTAssertTrue(error.localizedDescription.contains(path))
        XCTAssertTrue(error.localizedDescription.contains("Permission denied"))
    }

    @MainActor
    func testCoordinatorRefreshesLegacyInstallSnapshot() {
        let provider = FakeLegacyInstallProvider(
            current: .detected(homeDirectory: URL(fileURLWithPath: "/Users/alice"))
        )
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, legacyInstallProvider: provider)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.legacyInstall.status, .detected)
        XCTAssertEqual(provider.refreshCount, 1)
    }

    @MainActor
    func testCoordinatorRemovalIsExplicitAndRefreshesAfterSuccess() async {
        let launchAgent = URL(fileURLWithPath: "/Users/alice/Library/LaunchAgents/com.voco.daemon.plist")
        let provider = FakeLegacyInstallProvider(
            current: .detected(homeDirectory: URL(fileURLWithPath: "/Users/alice")),
            afterRemoval: .notFound(launchAgentURL: launchAgent)
        )
        let coordinator = AppCoordinator(hasCompletedOnboarding: true, legacyInstallProvider: provider)

        await coordinator.removeLegacyLaunchAgentFromUserAction()

        XCTAssertEqual(provider.removeCount, 1)
        XCTAssertEqual(coordinator.legacyInstall.status, .notFound)
        XCTAssertNil(coordinator.lastErrorMessage)
    }
}
```

The fake provider in the test file implements `LegacyInstallProviding` with `currentSnapshot()` and `removeKnownLaunchAgent() async throws`.

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter LegacyInstallModelsTests
```

Expected: compile failure because `LegacyInstallSnapshot`, `LegacyInstallCleanupError`, and `legacyInstallProvider` do not exist.

- [ ] **Step 3: Implement the minimal core model**

Create `native/Sources/VocoAppCore/LegacyInstallModels.swift`:

```swift
import Foundation

public enum LegacyInstallStatus: Equatable, Sendable {
    case notFound
    case detected
    case removalFailed(String)
}

public struct LegacyInstallSnapshot: Equatable, Sendable {
    public static let launchAgentFileName = "com.voco.daemon.plist"

    public let status: LegacyInstallStatus
    public let launchAgentPath: String
    public let title: String
    public let detail: String

    public var requiresUserAction: Bool {
        status == .detected
    }
}

public protocol LegacyInstallProviding: Sendable {
    func currentSnapshot() -> LegacyInstallSnapshot
    func removeKnownLaunchAgent() async throws -> LegacyInstallSnapshot
}
```

Add static constructors `detected(homeDirectory:)`, `notFound(launchAgentURL:)`, and `failed(launchAgentURL:message:)`. Add `LegacyInstallCleanupError.removeFailed(path:underlying:)` with a localized description containing the path and OS error. Add `StaticLegacyInstallProvider` for tests/default coordinator construction.

- [ ] **Step 4: Wire coordinator and diagnostics**

Modify `AppCoordinator` to publish:

```swift
@Published public private(set) var legacyInstall: LegacyInstallSnapshot
private let legacyInstallProvider: any LegacyInstallProviding
```

Refresh `legacyInstall` in `finishLaunching()` and `prepareForSettingsPresentation()`. Add:

```swift
public func refreshLegacyInstall() {
    legacyInstall = legacyInstallProvider.currentSnapshot()
}

public func removeLegacyLaunchAgentFromUserAction() async {
    do {
        legacyInstall = try await legacyInstallProvider.removeKnownLaunchAgent()
        lastErrorMessage = nil
    } catch {
        let message = error.localizedDescription
        legacyInstall = .failed(launchAgentURL: legacyInstall.launchAgentURL, message: message)
        lastErrorMessage = message
    }
}
```

Pass `legacyInstall` into `DiagnosticsSnapshot` and append a `.warning` event when status is `.detected`, or an `.error` event when removal failed.

- [ ] **Step 5: Run GREEN**

Run:

```bash
cd native && swift test --filter LegacyInstallModelsTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git add native/Sources/VocoAppCore/LegacyInstallModels.swift native/Sources/VocoAppCore/AppCoordinator.swift native/Sources/VocoAppCore/DiagnosticsModels.swift native/Tests/VocoAppCoreTests/LegacyInstallModelsTests.swift
git commit -m "feat(native): detect legacy launch agent"
```

## Task 2: Native Settings Migration Notice

**Files:**
- Modify: `native/Sources/VocoApp/SettingsView.swift`

- [ ] **Step 1: Add the migration notice UI**

Insert a `legacyInstallSection` near the top of the settings detail after `statusRow`. The section should:

```swift
if coordinator.legacyInstall.requiresUserAction {
    Label(coordinator.legacyInstall.title, systemImage: "exclamationmark.triangle.fill")
    Text(coordinator.legacyInstall.detail)
    Button(role: .destructive) {
        Task { await coordinator.removeLegacyLaunchAgentFromUserAction() }
    } label: {
        Label("移除旧版启动项", systemImage: "trash")
    }
}
```

Use the same single-card style as existing settings sections: `padding(12)` and `RoundedRectangle(cornerRadius: 8)`. Do not add nested cards.

- [ ] **Step 2: Compile settings UI**

Run:

```bash
cd native && swift test --filter LegacyInstallModelsTests
```

Expected: PASS and the executable target compiles.

## Task 3: Explicit User-Triggered Legacy Removal Action

**Files:**
- Create: `native/Sources/VocoApp/MacLegacyInstallProvider.swift`
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift`
- Test: `native/Tests/VocoAppCoreTests/LegacyInstallModelsTests.swift`

- [ ] **Step 1: Implement the macOS provider**

Create `native/Sources/VocoApp/MacLegacyInstallProvider.swift`:

```swift
import Foundation
import VocoAppCore

struct MacLegacyInstallProvider: LegacyInstallProviding {
    private let fileManager: FileManager
    private let homeDirectory: URL

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }
}
```

`currentSnapshot()` must check only `homeDirectory/Library/LaunchAgents/com.voco.daemon.plist`. `removeKnownLaunchAgent()` must remove only that exact URL when present. If it is absent, return `.notFound`. On failure, throw `LegacyInstallCleanupError.removeFailed(path:underlying:)`.

- [ ] **Step 2: Inject the provider**

Modify `native/Sources/VocoApp/VocoNativeApp.swift`:

```swift
legacyInstallProvider: MacLegacyInstallProvider()
```

The native app still uses `SMAppService.mainApp` for launch-at-login and must not write or install the legacy plist.

- [ ] **Step 3: Verify explicit cleanup behavior through model tests**

Run:

```bash
cd native && swift test --filter LegacyInstallModelsTests
```

Expected: PASS. The tests verify cleanup is explicit, scoped, and failure messages are descriptive.

- [ ] **Step 4: Commit**

Run:

```bash
git add native/Sources/VocoApp/MacLegacyInstallProvider.swift native/Sources/VocoApp/VocoNativeApp.swift native/Sources/VocoApp/SettingsView.swift native/Tests/VocoAppCoreTests/LegacyInstallModelsTests.swift
git commit -m "feat(native): surface legacy cleanup action"
```

## Task 4: CLI/Daemon Packaging Exclusion Verification

**Files:**
- Inspect: `packaging/tests/native_app_bundle_smoke.sh`
- Inspect: `packaging/tests/native_dmg_smoke.sh`

- [ ] **Step 1: Confirm native app bundle excludes legacy executables**

Run:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Expected: PASS and no `Contents/MacOS/voco`, `Contents/MacOS/voco-daemon`, or `Contents/MacOS/voco-hud` exists in `target/native/Voco.app`.

- [ ] **Step 2: Confirm native DMG excludes legacy executables**

Run if local DMG tooling is available:

```bash
packaging/tests/native_dmg_smoke.sh
```

Expected: PASS and mounted `Voco.app` contains only `Contents/MacOS/Voco` under user-facing executables.

- [ ] **Step 3: Leave legacy packaging assets intact**

Do not delete:

```text
packaging/com.voco.daemon.plist.tmpl
packaging/build_app_bundle.sh
crates/voco-cli
crates/voco-daemon
hud/
```

The gate for deleting or archiving these assets is Task 6.

## Task 5: Documentation Updates for Native-Only Install

**Files:**
- Modify: `README.md`
- Modify: `packaging/README.md`

- [ ] **Step 1: Update README user guidance**

Make `README.md` describe the native DMG flow as the user-facing install path:

```bash
packaging/build_native_dmg.sh --profile release --signing-style developer-id
open dist/Voco.dmg
```

Mention that users should drag `Voco.app` to `/Applications`, launch it from the native app, grant permissions, and manage login items through Settings. State that the native app uses `SMAppService` and does not install `~/Library/LaunchAgents/com.voco.daemon.plist`.

- [ ] **Step 2: Archive legacy guidance**

Move old `voco daemon install`, `voco app install`, and `packaging/build_app_bundle.sh` guidance under a development-only or legacy archive heading. Keep the exact commands for developers, but explicitly state they are not the native user install path.

- [ ] **Step 3: Document migration cleanup**

Document that Settings detects:

```text
~/Library/LaunchAgents/com.voco.daemon.plist
```

and offers an explicit removal button. State that cleanup removes only this known user-level plist and never requires `sudo`.

- [ ] **Step 4: Commit docs**

Run:

```bash
git add README.md packaging/README.md
git commit -m "docs(native): update native install guidance"
```

## Task 6: Feature-Parity Gate Before Deleting Legacy Assets

**Files:**
- Modify: `README.md`
- Modify: `packaging/README.md`
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-migration-cleanup.md`

- [ ] **Step 1: Record the deletion gate**

Document that legacy assets remain until all of the following are verified:

```text
native microphone capture
native hotkey recording workflow
native Doubao transcription
native text injection
native HUD overlay
native Keychain credentials
native Settings and Diagnostics
native launch-at-login
native release packaging
Task 8 manual UX verification
```

- [ ] **Step 2: Defer deletion in this task**

Because Task 8 manual UX verification is still pending, leave all legacy crates and packaging assets in place. If this task modifies a legacy packaging test, it may only strengthen native exclusion verification, not remove legacy development assets.

## Task 7: Full Verification and Documentation

**Files:**
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-migration-cleanup.md`

- [ ] **Step 1: Run full native tests**

Run:

```bash
cd native && swift test
```

Expected: PASS.

- [ ] **Step 2: Run native app bundle smoke**

Run:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Expected: PASS and native `Voco.app` excludes legacy `voco`, `voco-daemon`, and `voco-hud` binaries.

- [ ] **Step 3: Run whitespace verification**

Run:

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 4: Append final evidence to this plan**

Append exact command results, commit list, and the explicit concern:

```text
Legacy asset removal deferred because Task 8 manual UX/feature-parity verification is still pending.
```

- [ ] **Step 5: Commit verification docs**

Run:

```bash
git add docs/superpowers/plans/2026-05-06-voco-native-migration-cleanup.md
git commit -m "docs(native): mark migration cleanup verification"
```

## Self-Review

- Spec coverage: Tasks 1-3 cover detection, warning, explicit cleanup, no sudo, scoped plist removal, and descriptive failures. Task 4 covers native bundle exclusion of CLI/daemon/helper binaries. Task 5 updates user-facing install docs. Task 6 records the no-delete feature-parity gate. Task 7 records final verification.
- Placeholder scan: no task contains placeholder markers or an unspecified future implementation step.
- Type consistency: `LegacyInstallSnapshot`, `LegacyInstallStatus`, `LegacyInstallProviding`, `LegacyInstallCleanupError`, `MacLegacyInstallProvider`, and `AppCoordinator.legacyInstall` are named consistently across tests, implementation, UI, and docs.
