# Voco Native macOS App Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first native Voco app slice: a pure Swift/SwiftUI menu bar `Voco.app` shell that does not appear in the Dock and has an on-demand settings window.

**Architecture:** Create a new `native/` Swift Package instead of extending the old CLI or HUD helper. Put app-independent state in `VocoAppCore`, put SwiftUI/AppKit shell code in `VocoApp`, and package the built executable into a native `.app` bundle with `LSUIElement=true`. This phase deliberately ships no CLI, daemon, hotkey, audio, ASR, injection, or HUD runtime code.

**Tech Stack:** Swift 6.0, Swift Package Manager, SwiftUI `MenuBarExtra`, AppKit `NSWindow`, XCTest, shell-based bundle smoke tests, macOS 14+.

---

## File Structure

- Create: `native/Package.swift` — SwiftPM package for the native app.
- Create: `native/Sources/VocoAppCore/AppCoordinator.swift` — observable app state and menu-bar snapshot logic.
- Create: `native/Sources/VocoAppCore/SettingsSection.swift` — stable settings section model for the shell.
- Create: `native/Sources/VocoApp/VocoNativeApp.swift` — SwiftUI app entry point and menu bar commands.
- Create: `native/Sources/VocoApp/SettingsView.swift` — SwiftUI settings content.
- Create: `native/Sources/VocoApp/SettingsWindowPresenter.swift` — AppKit window owner for on-demand settings.
- Create: `native/Resources/Info.plist` — native app bundle metadata with `LSUIElement=true`.
- Create: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift` — app state tests.
- Create: `native/Tests/VocoAppCoreTests/SettingsSectionTests.swift` — settings section tests.
- Create: `packaging/build_native_app_bundle.sh` — builds `target/native/Voco.app`.
- Create: `packaging/tests/native_app_bundle_smoke.sh` — validates native app bundle shape.
- Modify: `packaging/README.md` — documents the native app shell build and smoke test.
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-macos-app-shell.md` — record verification results at the end.

## Follow-Up Plan Boundaries

This plan only produces the shell. Separate implementation plans should cover:

- permission onboarding;
- launch-at-login via `SMAppService.mainApp`;
- global hotkey capture;
- `AVAudioEngine` capture;
- transcription provider abstraction;
- text injection;
- in-process HUD overlay;
- signed, notarized DMG release.

## Task 1: Native Swift Package Red Tests

**Files:**
- Create: `native/Package.swift`
- Create: `native/Sources/VocoAppCore/BuildAnchor.swift`
- Create: `native/Sources/VocoApp/BuildAnchor.swift`
- Create: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Create package and failing core tests**

Create `native/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VocoNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VocoAppCore", targets: ["VocoAppCore"]),
        .executable(name: "Voco", targets: ["VocoApp"])
    ],
    targets: [
        .target(
            name: "VocoAppCore",
            path: "Sources/VocoAppCore"
        ),
        .executableTarget(
            name: "VocoApp",
            dependencies: ["VocoAppCore"],
            path: "Sources/VocoApp"
        ),
        .testTarget(
            name: "VocoAppCoreTests",
            dependencies: ["VocoAppCore"],
            path: "Tests/VocoAppCoreTests"
        )
    ]
)
```

Create `native/Sources/VocoAppCore/BuildAnchor.swift`:

```swift
public enum VocoAppCoreBuildAnchor {}
```

Create `native/Sources/VocoApp/BuildAnchor.swift`:

```swift
@main
struct VocoBuildAnchor {
    static func main() {}
}
```

Create `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`:

```swift
import XCTest
@testable import VocoAppCore

final class AppCoordinatorTests: XCTestCase {
    @MainActor
    func testFinishingLaunchWithoutOnboardingShowsSetupState() {
        let coordinator = AppCoordinator(hasCompletedOnboarding: false)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.status, .needsOnboarding)
        XCTAssertEqual(coordinator.snapshot.title, "需要设置")
        XCTAssertEqual(coordinator.snapshot.systemImage, "exclamationmark.triangle")
        XCTAssertTrue(coordinator.snapshot.canOpenSettings)
    }

    @MainActor
    func testFinishingLaunchWithOnboardingShowsReadyState() {
        let coordinator = AppCoordinator(hasCompletedOnboarding: true)

        coordinator.finishLaunching()

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertEqual(coordinator.snapshot.title, "就绪")
        XCTAssertEqual(coordinator.snapshot.systemImage, "waveform")
        XCTAssertTrue(coordinator.snapshot.isRecordingActionEnabled)
    }

    @MainActor
    func testMenuRecordingToggleMovesThroughRecordingAndTranscribing() {
        let coordinator = AppCoordinator(hasCompletedOnboarding: true)
        coordinator.finishLaunching()

        coordinator.toggleRecordingFromMenu()

        XCTAssertEqual(coordinator.status, .recording)
        XCTAssertEqual(coordinator.snapshot.title, "录音中")
        XCTAssertEqual(coordinator.snapshot.systemImage, "record.circle")

        coordinator.toggleRecordingFromMenu()

        XCTAssertEqual(coordinator.status, .transcribing)
        XCTAssertEqual(coordinator.snapshot.title, "转写中")
        XCTAssertEqual(coordinator.snapshot.systemImage, "ellipsis.bubble")
    }

    @MainActor
    func testTranscriptionCompletionReturnsToReadyOrError() {
        let coordinator = AppCoordinator(hasCompletedOnboarding: true)
        coordinator.finishLaunching()
        coordinator.toggleRecordingFromMenu()
        coordinator.toggleRecordingFromMenu()

        coordinator.finishTranscribing(result: .success)

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertNil(coordinator.lastErrorMessage)

        coordinator.fail("provider offline")

        XCTAssertEqual(coordinator.status, .error)
        XCTAssertEqual(coordinator.lastErrorMessage, "provider offline")
        XCTAssertEqual(coordinator.snapshot.title, "错误")
        XCTAssertEqual(coordinator.snapshot.systemImage, "xmark.octagon")
    }

    @MainActor
    func testLaunchAtLoginToggleIsStatefulForTheShell() {
        let coordinator = AppCoordinator(hasCompletedOnboarding: true)

        XCTAssertFalse(coordinator.launchAtLoginEnabled)

        coordinator.setLaunchAtLoginEnabled(true)

        XCTAssertTrue(coordinator.launchAtLoginEnabled)

        coordinator.setLaunchAtLoginEnabled(false)

        XCTAssertFalse(coordinator.launchAtLoginEnabled)
    }
}
```

- [ ] **Step 2: Run tests and confirm RED**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: FAIL to compile with errors that `AppCoordinator`, `AppRuntimeStatus`, or related members are not defined.

- [ ] **Step 3: Commit red tests**

Run:

```bash
git add native/Package.swift native/Sources/VocoAppCore/BuildAnchor.swift native/Sources/VocoApp/BuildAnchor.swift native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift
git commit -m "test(native): cover app coordinator shell state"
```

## Task 2: App Coordinator Core

**Files:**
- Delete: `native/Sources/VocoAppCore/BuildAnchor.swift`
- Create: `native/Sources/VocoAppCore/AppCoordinator.swift`

- [ ] **Step 1: Implement coordinator state**

Delete `native/Sources/VocoAppCore/BuildAnchor.swift`.

Create `native/Sources/VocoAppCore/AppCoordinator.swift`:

```swift
import Combine
import Foundation

public enum AppRuntimeStatus: Equatable, Sendable {
    case launching
    case needsOnboarding
    case ready
    case recording
    case transcribing
    case permissionNeeded
    case providerOffline
    case error
}

public enum TranscriptionCompletionResult: Equatable, Sendable {
    case success
    case failure(String)
}

public struct MenuBarSnapshot: Equatable, Sendable {
    public let status: AppRuntimeStatus
    public let title: String
    public let systemImage: String
    public let isRecordingActionEnabled: Bool
    public let canOpenSettings: Bool

    public init(
        status: AppRuntimeStatus,
        title: String,
        systemImage: String,
        isRecordingActionEnabled: Bool,
        canOpenSettings: Bool
    ) {
        self.status = status
        self.title = title
        self.systemImage = systemImage
        self.isRecordingActionEnabled = isRecordingActionEnabled
        self.canOpenSettings = canOpenSettings
    }
}

@MainActor
public final class AppCoordinator: ObservableObject {
    @Published public private(set) var status: AppRuntimeStatus
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var launchAtLoginEnabled: Bool

    private let hasCompletedOnboarding: Bool

    public init(
        hasCompletedOnboarding: Bool = false,
        launchAtLoginEnabled: Bool = false
    ) {
        self.status = .launching
        self.lastErrorMessage = nil
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public var snapshot: MenuBarSnapshot {
        MenuBarSnapshot(
            status: status,
            title: status.menuBarTitle,
            systemImage: status.systemImage,
            isRecordingActionEnabled: status == .ready,
            canOpenSettings: true
        )
    }

    public var isRecording: Bool {
        status == .recording
    }

    public func finishLaunching() {
        lastErrorMessage = nil
        status = hasCompletedOnboarding ? .ready : .needsOnboarding
    }

    public func toggleRecordingFromMenu() {
        switch status {
        case .ready:
            lastErrorMessage = nil
            status = .recording
        case .recording:
            status = .transcribing
        default:
            break
        }
    }

    public func finishTranscribing(result: TranscriptionCompletionResult) {
        switch result {
        case .success:
            lastErrorMessage = nil
            status = .ready
        case .failure(let message):
            fail(message)
        }
    }

    public func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginEnabled = enabled
    }

    public func fail(_ message: String) {
        lastErrorMessage = message
        status = .error
    }
}

private extension AppRuntimeStatus {
    var menuBarTitle: String {
        switch self {
        case .launching:
            "启动中"
        case .needsOnboarding:
            "需要设置"
        case .ready:
            "就绪"
        case .recording:
            "录音中"
        case .transcribing:
            "转写中"
        case .permissionNeeded:
            "需要权限"
        case .providerOffline:
            "服务离线"
        case .error:
            "错误"
        }
    }

    var systemImage: String {
        switch self {
        case .launching:
            "hourglass"
        case .needsOnboarding:
            "exclamationmark.triangle"
        case .ready:
            "waveform"
        case .recording:
            "record.circle"
        case .transcribing:
            "ellipsis.bubble"
        case .permissionNeeded:
            "lock.shield"
        case .providerOffline:
            "wifi.slash"
        case .error:
            "xmark.octagon"
        }
    }
}
```

- [ ] **Step 2: Run focused tests and confirm GREEN**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests
```

Expected: PASS with all `AppCoordinatorTests` green.

- [ ] **Step 3: Run native package tests**

Run:

```bash
cd native && swift test
```

Expected: PASS.

- [ ] **Step 4: Commit coordinator implementation**

Run:

```bash
git add native/Sources/VocoAppCore native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift
git commit -m "feat(native): add app coordinator shell state"
```

## Task 3: Settings Section Model

**Files:**
- Create: `native/Tests/VocoAppCoreTests/SettingsSectionTests.swift`
- Create: `native/Sources/VocoAppCore/SettingsSection.swift`

- [ ] **Step 1: Add failing settings section tests**

Create `native/Tests/VocoAppCoreTests/SettingsSectionTests.swift`:

```swift
import XCTest
@testable import VocoAppCore

final class SettingsSectionTests: XCTestCase {
    func testSettingsSectionsStayInProductOrder() {
        XCTAssertEqual(
            SettingsSection.allCases,
            [
                .general,
                .hotkey,
                .audio,
                .transcription,
                .injection,
                .hud,
                .privacy,
                .diagnostics
            ]
        )
    }

    func testSettingsSectionsHaveUserVisibleTitlesAndSymbols() {
        XCTAssertEqual(SettingsSection.general.title, "通用")
        XCTAssertEqual(SettingsSection.general.systemImage, "gearshape")
        XCTAssertEqual(SettingsSection.hotkey.title, "快捷键")
        XCTAssertEqual(SettingsSection.audio.systemImage, "mic")
        XCTAssertEqual(SettingsSection.diagnostics.title, "诊断")
        XCTAssertEqual(SettingsSection.diagnostics.systemImage, "stethoscope")
    }
}
```

- [ ] **Step 2: Run settings tests and confirm RED**

Run:

```bash
cd native && swift test --filter SettingsSectionTests
```

Expected: FAIL to compile because `SettingsSection` is not defined.

- [ ] **Step 3: Implement settings section model**

Create `native/Sources/VocoAppCore/SettingsSection.swift`:

```swift
import Foundation

public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case hotkey
    case audio
    case transcription
    case injection
    case hud
    case privacy
    case diagnostics

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .general:
            "通用"
        case .hotkey:
            "快捷键"
        case .audio:
            "音频"
        case .transcription:
            "转写"
        case .injection:
            "输入"
        case .hud:
            "HUD"
        case .privacy:
            "隐私"
        case .diagnostics:
            "诊断"
        }
    }

    public var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .hotkey:
            "keyboard"
        case .audio:
            "mic"
        case .transcription:
            "text.bubble"
        case .injection:
            "text.cursor"
        case .hud:
            "rectangle.inset.filled"
        case .privacy:
            "lock"
        case .diagnostics:
            "stethoscope"
        }
    }
}
```

- [ ] **Step 4: Run settings tests and confirm GREEN**

Run:

```bash
cd native && swift test --filter SettingsSectionTests
```

Expected: PASS.

- [ ] **Step 5: Run all native tests**

Run:

```bash
cd native && swift test
```

Expected: PASS.

- [ ] **Step 6: Commit settings model**

Run:

```bash
git add native/Sources/VocoAppCore/SettingsSection.swift native/Tests/VocoAppCoreTests/SettingsSectionTests.swift
git commit -m "feat(native): define settings sections"
```

## Task 4: Menu Bar App and Settings Window

**Files:**
- Delete: `native/Sources/VocoApp/BuildAnchor.swift`
- Create: `native/Sources/VocoApp/VocoNativeApp.swift`
- Create: `native/Sources/VocoApp/SettingsView.swift`
- Create: `native/Sources/VocoApp/SettingsWindowPresenter.swift`

- [ ] **Step 1: Add SwiftUI app entry point**

Delete `native/Sources/VocoApp/BuildAnchor.swift`.

Create `native/Sources/VocoApp/VocoNativeApp.swift`:

```swift
import AppKit
import SwiftUI
import VocoAppCore

@main
@MainActor
struct VocoNativeApp: App {
    @StateObject private var coordinator: AppCoordinator

    var body: some Scene {
        MenuBarExtra {
            Button(coordinator.isRecording ? "停止录音" : "开始录音") {
                coordinator.toggleRecordingFromMenu()
            }
            .disabled(!coordinator.snapshot.isRecordingActionEnabled && !coordinator.isRecording)

            Divider()

            Button("打开设置") {
                SettingsWindowPresenter.shared.show(coordinator: coordinator)
            }

            Toggle(
                "登录时启动",
                isOn: Binding(
                    get: { coordinator.launchAtLoginEnabled },
                    set: { coordinator.setLaunchAtLoginEnabled($0) }
                )
            )

            Divider()

            Button("退出 Voco") {
                NSApp.terminate(nil)
            }
        } label: {
            Label(coordinator.snapshot.title, systemImage: coordinator.snapshot.systemImage)
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        NSApp.setActivationPolicy(.accessory)
        let appCoordinator = AppCoordinator()
        appCoordinator.finishLaunching()
        _coordinator = StateObject(wrappedValue: appCoordinator)
    }
}
```

- [ ] **Step 2: Add settings window presenter**

Create `native/Sources/VocoApp/SettingsWindowPresenter.swift`:

```swift
import AppKit
import SwiftUI
import VocoAppCore

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?

    private init() {}

    func show(coordinator: AppCoordinator) {
        if window == nil {
            let view = SettingsView(coordinator: coordinator)
            let hostingController = NSHostingController(rootView: view)
            let settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow.title = "Voco 设置"
            settingsWindow.center()
            settingsWindow.contentViewController = hostingController
            settingsWindow.isReleasedWhenClosed = false
            window = settingsWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 3: Add settings SwiftUI view**

Create `native/Sources/VocoApp/SettingsView.swift`:

```swift
import SwiftUI
import VocoAppCore

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
            }
            .navigationTitle("Voco")
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                Text("Voco 设置")
                    .font(.title2)
                    .fontWeight(.semibold)

                statusRow

                Text("当前版本包含 native macOS app shell：菜单栏状态、设置窗口和登录项开关的界面入口。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 480, minHeight: 360, alignment: .topLeading)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: coordinator.snapshot.systemImage)
                .foregroundStyle(.yellow)
            Text(coordinator.snapshot.title)
                .font(.headline)
            if let message = coordinator.lastErrorMessage {
                Text(message)
                    .foregroundStyle(.red)
            }
        }
    }
}
```

- [ ] **Step 4: Build native executable**

Run:

```bash
cd native && swift build
```

Expected: PASS and build product `Voco`.

- [ ] **Step 5: Run native tests**

Run:

```bash
cd native && swift test
```

Expected: PASS.

- [ ] **Step 6: Commit app shell**

Run:

```bash
git add native/Sources/VocoApp
git commit -m "feat(native): add menu bar app shell"
```

## Task 5: Native App Bundle Packaging

**Files:**
- Create: `native/Resources/Info.plist`
- Create: `packaging/build_native_app_bundle.sh`
- Create: `packaging/tests/native_app_bundle_smoke.sh`

- [ ] **Step 1: Add native Info.plist**

Create `native/Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>

  <key>CFBundleDisplayName</key>
  <string>Voco</string>

  <key>CFBundleExecutable</key>
  <string>Voco</string>

  <key>CFBundleIdentifier</key>
  <string>com.voco.app</string>

  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>

  <key>CFBundleName</key>
  <string>Voco</string>

  <key>CFBundlePackageType</key>
  <string>APPL</string>

  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>

  <key>CFBundleVersion</key>
  <string>0.2.0</string>

  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>

  <key>LSUIElement</key>
  <true/>

  <key>NSMicrophoneUsageDescription</key>
  <string>Voco needs microphone access to transcribe your speech into text.</string>
</dict>
</plist>
```

- [ ] **Step 2: Add native bundle build script**

Create `packaging/build_native_app_bundle.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: packaging/build_native_app_bundle.sh --profile <debug|release>

Builds target/native/Voco.app from the Swift native app package.
USAGE
}

PROFILE="debug"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      PROFILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

case "${PROFILE}" in
  debug)
    SWIFT_CONFIG="debug"
    ;;
  release)
    SWIFT_CONFIG="release"
    ;;
  *)
    echo "invalid profile: ${PROFILE}" >&2
    usage
    exit 64
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NATIVE_DIR="${REPO_ROOT}/native"
BUNDLE_PATH="${REPO_ROOT}/target/native/Voco.app"
CONTENTS_DIR="${BUNDLE_PATH}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
INFO_PLIST="${CONTENTS_DIR}/Info.plist"
PLIST_TEMPLATE="${NATIVE_DIR}/Resources/Info.plist"
BINARY="${NATIVE_DIR}/.build/${SWIFT_CONFIG}/Voco"

if [[ ! -f "${PLIST_TEMPLATE}" ]]; then
  echo "missing required file: ${PLIST_TEMPLATE}" >&2
  exit 66
fi

swift build --package-path "${NATIVE_DIR}" -c "${SWIFT_CONFIG}" --product Voco
echo "ok: built native Swift app: ${SWIFT_CONFIG}"

if [[ ! -x "${BINARY}" ]]; then
  echo "missing executable: ${BINARY}" >&2
  exit 66
fi

rm -rf "${BUNDLE_PATH}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${PLIST_TEMPLATE}" "${INFO_PLIST}"
cp "${BINARY}" "${MACOS_DIR}/Voco"
chmod 755 "${MACOS_DIR}/Voco"

plutil -lint "${INFO_PLIST}" >/dev/null
codesign --force --deep --sign - "${BUNDLE_PATH}" >/dev/null
codesign --verify --deep --strict "${BUNDLE_PATH}"

echo "ok: verified native Voco.app bundle: target/native/Voco.app"
```

- [ ] **Step 3: Make build script executable**

Run:

```bash
chmod +x packaging/build_native_app_bundle.sh
```

Expected: `packaging/build_native_app_bundle.sh` is executable.

- [ ] **Step 4: Add native app bundle smoke test**

Create `packaging/tests/native_app_bundle_smoke.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUNDLE_PATH="${REPO_ROOT}/target/native/Voco.app"
INFO_PLIST="${BUNDLE_PATH}/Contents/Info.plist"
MACOS_DIR="${BUNDLE_PATH}/Contents/MacOS"

"${REPO_ROOT}/packaging/build_native_app_bundle.sh" --profile debug

test -d "${BUNDLE_PATH}"
test -f "${INFO_PLIST}"
test -x "${MACOS_DIR}/Voco"

for entry in "${MACOS_DIR}"/*; do
  name="$(basename "${entry}")"
  case "${name}" in
    voco|voco-daemon|voco-hud)
      echo "legacy executable must not be present: ${name}" >&2
      exit 1
      ;;
  esac
done

plutil -lint "${INFO_PLIST}" >/dev/null
codesign --verify --deep --strict "${BUNDLE_PATH}"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${INFO_PLIST}")"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${INFO_PLIST}")"
LS_UI_ELEMENT="$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "${INFO_PLIST}")"
MIC_USAGE="$(/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "${INFO_PLIST}")"

if [[ "${BUNDLE_ID}" != "com.voco.app" ]]; then
  echo "unexpected CFBundleIdentifier: ${BUNDLE_ID}" >&2
  exit 1
fi

if [[ "${EXECUTABLE}" != "Voco" ]]; then
  echo "unexpected CFBundleExecutable: ${EXECUTABLE}" >&2
  exit 1
fi

if [[ "${LS_UI_ELEMENT}" != "true" ]]; then
  echo "unexpected LSUIElement: ${LS_UI_ELEMENT}" >&2
  exit 1
fi

if [[ -z "${MIC_USAGE}" ]]; then
  echo "NSMicrophoneUsageDescription must not be empty" >&2
  exit 1
fi

echo "ok: native Voco.app bundle smoke passed"
```

- [ ] **Step 5: Make smoke test executable**

Run:

```bash
chmod +x packaging/tests/native_app_bundle_smoke.sh
```

Expected: `packaging/tests/native_app_bundle_smoke.sh` is executable.

- [ ] **Step 6: Run native bundle smoke**

Run:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Expected: PASS and final line `ok: native Voco.app bundle smoke passed`.

- [ ] **Step 7: Commit packaging**

Run:

```bash
git add native/Resources/Info.plist packaging/build_native_app_bundle.sh packaging/tests/native_app_bundle_smoke.sh
git commit -m "feat(packaging): build native app bundle"
```

## Task 6: Packaging Documentation and Final Verification

**Files:**
- Modify: `packaging/README.md`
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-macos-app-shell.md`

- [ ] **Step 1: Update packaging README**

Add this section near the top of `packaging/README.md`, before the old LaunchAgent section:

````markdown
## Native App Shell

Build the native Swift/SwiftUI app shell:

```bash
packaging/build_native_app_bundle.sh --profile debug
```

The generated bundle is:

```text
target/native/Voco.app
```

It contains only the native app executable:

```text
Contents/Info.plist
Contents/MacOS/Voco
```

It does not contain the legacy CLI, daemon, or HUD helper binaries:

```text
Contents/MacOS/voco
Contents/MacOS/voco-daemon
Contents/MacOS/voco-hud
```

Run the native app bundle smoke test:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

This native app shell is the starting point for the rewrite. The older
LaunchAgent and development app bundle workflows remain documented below while
the native rewrite reaches feature parity.
````

- [ ] **Step 2: Run native tests**

Run:

```bash
cd native && swift test
```

Expected: PASS.

- [ ] **Step 3: Run native build**

Run:

```bash
cd native && swift build
```

Expected: PASS.

- [ ] **Step 4: Run native bundle smoke**

Run:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Expected: PASS.

- [ ] **Step 5: Run repository whitespace check**

Run:

```bash
git diff --check
```

Expected: no output and exit 0.

- [ ] **Step 6: Record verification in this plan**

Append this section to `docs/superpowers/plans/2026-05-06-voco-native-macos-app-shell.md`:

```markdown
## Verification Results

- `cd native && swift test` passed.
- `cd native && swift build` passed.
- `packaging/tests/native_app_bundle_smoke.sh` passed.
- `git diff --check` passed.
```

- [ ] **Step 7: Commit docs and verification**

Run:

```bash
git add packaging/README.md docs/superpowers/plans/2026-05-06-voco-native-macos-app-shell.md
git commit -m "docs(native): document app shell packaging"
```

## Final Verification Gate

Run:

```bash
cd native && swift test
cd native && swift build
packaging/tests/native_app_bundle_smoke.sh
git diff --check
```

Expected:

- native Swift tests pass;
- native Swift executable builds;
- `target/native/Voco.app` exists;
- `Contents/MacOS/Voco` is executable;
- `Contents/MacOS/voco`, `Contents/MacOS/voco-daemon`, and `Contents/MacOS/voco-hud` do not exist;
- `LSUIElement` is `true`;
- ad-hoc signature verifies;
- no whitespace errors are reported.

## Verification Results

- `cd native && swift test` passed.
- `cd native && swift build` passed.
- `packaging/tests/native_app_bundle_smoke.sh` passed.
- `git diff --check` passed.
