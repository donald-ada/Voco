# Voco Native HUD Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-process native SwiftUI HUD overlay driven directly by `AppCoordinator`, replacing the old helper-process HUD shape for the native app path.

**Architecture:** Keep HUD state mapping in `VocoAppCore` so it is unit-testable without AppKit. Put the visual SwiftUI surface and non-activating `NSPanel` lifecycle in `VocoApp`, then attach the presenter from `VocoNativeApp` to observe coordinator state.

**Tech Stack:** Swift 6, XCTest, SwiftUI, AppKit `NSPanel`, Combine, existing `AppCoordinator` observable state.

---

## Baseline

Run:

```bash
cd native && swift test
```

Expected: all existing native tests pass before this slice starts.

Observed before Task 1: PASS. XCTest executed 56 tests with 0 failures.

## File Structure

- Create `native/Sources/VocoAppCore/HUDModels.swift` — `HUDPhase`, `HUDSnapshot`, and status-to-HUD mapping.
- Create `native/Tests/VocoAppCoreTests/HUDModelsTests.swift` — core HUD visibility, title, transcript preview, success, and error mapping.
- Modify `native/Sources/VocoAppCore/AppCoordinator.swift` — expose computed `hudSnapshot`.
- Modify `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift` — prove coordinator exposes recording and failure HUD snapshots.
- Create `native/Sources/VocoApp/HUDOverlayView.swift` — compact SwiftUI HUD surface.
- Create `native/Sources/VocoApp/HUDOverlayPresenter.swift` — non-activating transparent `NSPanel` controller that observes coordinator state.
- Modify `native/Sources/VocoApp/VocoNativeApp.swift` — attach `HUDOverlayPresenter` during app startup.
- Modify this plan with final verification results.

## Task 1: HUD Core Snapshot Model

**Files:**
- Create: `native/Tests/VocoAppCoreTests/HUDModelsTests.swift`
- Create: `native/Sources/VocoAppCore/HUDModels.swift`

- [x] **Step 1: Write failing HUD model tests**

Create `native/Tests/VocoAppCoreTests/HUDModelsTests.swift`:

```swift
import XCTest
@testable import VocoAppCore

final class HUDModelsTests: XCTestCase {
    func testReadyWithoutRecentResultIsHidden() {
        let snapshot = HUDSnapshot(
            status: .ready,
            lastTranscript: nil,
            lastInjection: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.phase, .hidden)
        XCTAssertFalse(snapshot.isVisible)
    }

    func testRecordingAndTranscribingAreVisible() {
        let recording = HUDSnapshot(
            status: .recording,
            lastTranscript: nil,
            lastInjection: nil,
            lastErrorMessage: nil
        )
        XCTAssertEqual(recording.phase, .recording)
        XCTAssertEqual(recording.title, "正在听")
        XCTAssertEqual(recording.systemImage, "waveform.circle.fill")
        XCTAssertTrue(recording.isVisible)

        let transcribing = HUDSnapshot(
            status: .transcribing,
            lastTranscript: nil,
            lastInjection: nil,
            lastErrorMessage: nil
        )
        XCTAssertEqual(transcribing.phase, .transcribing)
        XCTAssertEqual(transcribing.title, "正在转写")
        XCTAssertTrue(transcribing.isVisible)
    }

    func testSuccessShowsInjectionTargetAndTranscriptPreview() {
        let transcript = TranscriptSnapshot(
            finalText: "hello from Voco",
            partials: ["hello"],
            providerName: "Fake ASR",
            latencyMilliseconds: 42
        )
        let injection = TextInjectionSnapshot(
            targetAppName: "Notes",
            strategy: .directAccessibility,
            succeeded: true,
            detail: "Inserted"
        )

        let snapshot = HUDSnapshot(
            status: .ready,
            lastTranscript: transcript,
            lastInjection: injection,
            lastErrorMessage: nil
        )

        XCTAssertEqual(snapshot.phase, .success)
        XCTAssertEqual(snapshot.title, "已插入")
        XCTAssertEqual(snapshot.detail, "Notes · 辅助功能直接插入")
        XCTAssertEqual(snapshot.transcriptPreview, "hello from Voco")
        XCTAssertEqual(snapshot.autoHideAfterSeconds, 1.4)
    }

    func testFailureUsesErrorMessageAndFailedInjectionDetail() {
        let injection = TextInjectionSnapshot(
            targetAppName: "Terminal",
            strategy: .clipboardFallback,
            succeeded: false,
            detail: "clipboard restore failed"
        )
        let failedInjection = HUDSnapshot(
            status: .error,
            lastTranscript: nil,
            lastInjection: injection,
            lastErrorMessage: nil
        )
        XCTAssertEqual(failedInjection.phase, .error)
        XCTAssertEqual(failedInjection.detail, "clipboard restore failed")

        let explicitError = HUDSnapshot(
            status: .providerOffline,
            lastTranscript: nil,
            lastInjection: nil,
            lastErrorMessage: "转写服务未配置"
        )
        XCTAssertEqual(explicitError.phase, .error)
        XCTAssertEqual(explicitError.title, "需要处理")
        XCTAssertEqual(explicitError.detail, "转写服务未配置")
        XCTAssertNil(explicitError.autoHideAfterSeconds)
    }
}
```

- [x] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter HUDModelsTests
```

Expected: compile failure because `HUDSnapshot` and `HUDPhase` do not exist.

- [x] **Step 3: Implement HUD models**

Create `native/Sources/VocoAppCore/HUDModels.swift` with:

```swift
import Foundation

public enum HUDPhase: Equatable, Sendable {
    case hidden
    case recording
    case transcribing
    case injecting
    case success
    case error
}

public struct HUDSnapshot: Equatable, Sendable {
    public let phase: HUDPhase
    public let title: String
    public let detail: String
    public let systemImage: String
    public let transcriptPreview: String?
    public let autoHideAfterSeconds: Double?

    public var isVisible: Bool {
        phase != .hidden
    }

    public init(
        status: AppRuntimeStatus,
        lastTranscript: TranscriptSnapshot?,
        lastInjection: TextInjectionSnapshot?,
        lastErrorMessage: String?
    ) {
        switch status {
        case .recording:
            self = HUDSnapshot(
                phase: .recording,
                title: "正在听",
                detail: "松开或再次按下快捷键结束录音",
                systemImage: "waveform.circle.fill",
                transcriptPreview: nil,
                autoHideAfterSeconds: nil
            )
        case .transcribing:
            self = HUDSnapshot(
                phase: .transcribing,
                title: "正在转写",
                detail: "正在生成文字...",
                systemImage: "ellipsis.bubble.fill",
                transcriptPreview: transcriptPreview(from: lastTranscript),
                autoHideAfterSeconds: nil
            )
        case .injecting:
            self = HUDSnapshot(
                phase: .injecting,
                title: "正在插入",
                detail: "正在把转写文本插入当前 App",
                systemImage: "text.cursor",
                transcriptPreview: transcriptPreview(from: lastTranscript),
                autoHideAfterSeconds: nil
            )
        case .providerOffline, .error:
            self = HUDSnapshot(
                phase: .error,
                title: "需要处理",
                detail: lastErrorMessage ?? lastInjection?.detail ?? "Voco 遇到错误。",
                systemImage: "exclamationmark.triangle.fill",
                transcriptPreview: nil,
                autoHideAfterSeconds: nil
            )
        case .ready:
            if let lastInjection, lastInjection.succeeded, lastInjection.strategy != .skippedEmpty {
                self = HUDSnapshot(
                    phase: .success,
                    title: "已插入",
                    detail: "\(lastInjection.targetAppName ?? "当前 App") · \(lastInjection.strategy.title)",
                    systemImage: "checkmark.circle.fill",
                    transcriptPreview: transcriptPreview(from: lastTranscript),
                    autoHideAfterSeconds: 1.4
                )
            } else {
                self = .hidden
            }
        case .launching, .needsOnboarding, .permissionNeeded:
            self = .hidden
        }
    }

    private init(
        phase: HUDPhase,
        title: String,
        detail: String,
        systemImage: String,
        transcriptPreview: String?,
        autoHideAfterSeconds: Double?
    ) {
        self.phase = phase
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.transcriptPreview = transcriptPreview
        self.autoHideAfterSeconds = autoHideAfterSeconds
    }

    public static var hidden: HUDSnapshot {
        HUDSnapshot(
            phase: .hidden,
            title: "",
            detail: "",
            systemImage: "waveform",
            transcriptPreview: nil,
            autoHideAfterSeconds: nil
        )
    }
}

private func transcriptPreview(from transcript: TranscriptSnapshot?) -> String? {
    guard let transcript else {
        return nil
    }

    let source = transcript.finalText.isEmpty ? transcript.partials.last ?? "" : transcript.finalText
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    if trimmed.count <= 80 {
        return trimmed
    }

    let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 80)
    return "\(trimmed[..<endIndex])..."
}
```

- [x] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter HUDModelsTests
```

Expected: all `HUDModelsTests` pass.

- [x] **Step 5: Commit HUD models**

Run:

```bash
git add native/Sources/VocoAppCore/HUDModels.swift native/Tests/VocoAppCoreTests/HUDModelsTests.swift docs/superpowers/plans/2026-05-06-voco-native-hud-overlay.md
git commit -m "feat(native): add hud snapshot models"
```

## Task 2: Coordinator HUD Snapshot

**Files:**
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`

- [x] **Step 1: Write failing coordinator tests**

Add to `AppCoordinatorTests`:

```swift
@MainActor
func testCoordinatorPublishesRecordingHUDSnapshot() async {
    let coordinator = AppCoordinator(hasCompletedOnboarding: true)
    coordinator.finishLaunching()

    await coordinator.toggleRecordingFromUserAction()

    XCTAssertEqual(coordinator.hudSnapshot.phase, .recording)
    XCTAssertTrue(coordinator.hudSnapshot.isVisible)
}

@MainActor
func testCoordinatorPublishesFailureHUDSnapshot() async {
    let recordingWorkflow = FakeRecordingWorkflow(stopError: TranscriptionProviderError.notConfigured)
    let coordinator = AppCoordinator(hasCompletedOnboarding: true, recordingWorkflow: recordingWorkflow)
    coordinator.finishLaunching()

    await coordinator.toggleRecordingFromUserAction()
    await coordinator.toggleRecordingFromUserAction()

    XCTAssertEqual(coordinator.hudSnapshot.phase, .error)
    XCTAssertEqual(coordinator.hudSnapshot.detail, "转写服务未配置：请先在设置中配置 ASR provider。")
}
```

- [x] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests/testCoordinatorPublishes
```

Expected: compile failure because `AppCoordinator.hudSnapshot` does not exist.

- [x] **Step 3: Add computed HUD snapshot**

Add to `AppCoordinator` near `snapshot`:

```swift
public var hudSnapshot: HUDSnapshot {
    HUDSnapshot(
        status: status,
        lastTranscript: lastTranscript,
        lastInjection: lastInjection,
        lastErrorMessage: lastErrorMessage
    )
}
```

- [x] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests/testCoordinatorPublishes
```

Expected: new coordinator HUD tests pass.

- [x] **Step 5: Commit coordinator wiring**

Run:

```bash
git add native/Sources/VocoAppCore/AppCoordinator.swift native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift
git commit -m "feat(native): expose hud snapshot"
```

## Task 3: AppKit HUD Overlay

**Files:**
- Create: `native/Sources/VocoApp/HUDOverlayView.swift`
- Create: `native/Sources/VocoApp/HUDOverlayPresenter.swift`
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift`

- [x] **Step 1: Add SwiftUI HUD view**

Create `native/Sources/VocoApp/HUDOverlayView.swift`:

```swift
import SwiftUI
import VocoAppCore

struct HUDOverlayView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        let snapshot = coordinator.hudSnapshot

        HStack(spacing: 12) {
            Image(systemName: snapshot.systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(iconTint(snapshot.phase))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.title)
                    .font(.system(size: 13, weight: .semibold))

                Text(snapshot.transcriptPreview ?? snapshot.detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 360, minHeight: 72, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
    }

    private func iconTint(_ phase: HUDPhase) -> Color {
        switch phase {
        case .recording:
            .red
        case .transcribing, .injecting:
            .blue
        case .success:
            .green
        case .error:
            .orange
        case .hidden:
            .secondary
        }
    }
}
```

- [x] **Step 2: Add non-activating panel presenter**

Create `native/Sources/VocoApp/HUDOverlayPresenter.swift`:

```swift
import AppKit
import Combine
import SwiftUI
import VocoAppCore

@MainActor
final class HUDOverlayPresenter {
    static let shared = HUDOverlayPresenter()

    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var autoHideTask: Task<Void, Never>?
    private var lastSnapshot: HUDSnapshot = .hidden

    private init() {}

    func attach(coordinator: AppCoordinator) {
        if panel == nil {
            createPanel(coordinator: coordinator)
        }

        cancellables.removeAll()
        coordinator.objectWillChange
            .sink { [weak self, weak coordinator] _ in
                Task { @MainActor in
                    guard let coordinator else {
                        return
                    }
                    self?.update(with: coordinator.hudSnapshot)
                }
            }
            .store(in: &cancellables)

        update(with: coordinator.hudSnapshot)
    }

    private func createPanel(coordinator: AppCoordinator) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 84),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = NSHostingController(rootView: HUDOverlayView(coordinator: coordinator))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
    }

    private func update(with snapshot: HUDSnapshot) {
        autoHideTask?.cancel()
        lastSnapshot = snapshot

        guard snapshot.isVisible else {
            panel?.orderOut(nil)
            return
        }

        positionPanel()
        panel?.orderFrontRegardless()

        if let seconds = snapshot.autoHideAfterSeconds {
            scheduleAutoHide(after: seconds, snapshot: snapshot)
        }
    }

    private func positionPanel() {
        guard let panel else {
            return
        }

        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let panelSize = NSSize(width: 360, height: 84)
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.maxY - panelSize.height - 24
        )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    private func scheduleAutoHide(after seconds: Double, snapshot: HUDSnapshot) {
        autoHideTask = Task { [weak self] in
            let nanoseconds = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            await MainActor.run {
                guard self?.lastSnapshot == snapshot else {
                    return
                }
                self?.panel?.orderOut(nil)
            }
        }
    }
}
```

- [x] **Step 3: Attach presenter in native app**

Modify `native/Sources/VocoApp/VocoNativeApp.swift` after `appCoordinator.finishLaunching()`:

```swift
HUDOverlayPresenter.shared.attach(coordinator: appCoordinator)
```

- [x] **Step 4: Run app compile tests**

Run:

```bash
cd native && swift test
```

Expected: all native tests pass and `VocoApp` compiles with `HUDOverlayPresenter`.

- [x] **Step 5: Commit overlay presenter**

Run:

```bash
git add native/Sources/VocoApp/HUDOverlayView.swift native/Sources/VocoApp/HUDOverlayPresenter.swift native/Sources/VocoApp/VocoNativeApp.swift
git commit -m "feat(native): show in-process hud overlay"
```

## Task 4: Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-hud-overlay.md`

- [x] **Step 1: Run full native tests**

Run:

```bash
cd native && swift test
```

Expected: all native tests pass.

- [x] **Step 2: Run native bundle smoke**

Run from repository root:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Expected: native bundle builds, signs, verifies, and launches for smoke validation.

- [x] **Step 3: Run diff and signature checks**

Run:

```bash
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Expected: no whitespace errors and a valid ad-hoc signature on `target/native/Voco.app`.

- [x] **Step 4: Record verification results**

Append a `Verification Results` section to this plan with exact command output summaries.

- [x] **Step 5: Commit verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-05-06-voco-native-hud-overlay.md
git commit -m "docs(native): mark hud overlay verification"
```

## Scope Notes

- Covers the native rewrite requirement that HUD state lives in-process and reads directly from `AppCoordinator`.
- Creates the AppKit `NSPanel` shape needed for a non-activating overlay that can join all Spaces.
- Keeps streaming partial transcript delivery, polished notch geometry, Keychain credential storage, real ASR provider, and release DMG notarization as separate slices.

## Verification Results

```bash
cd native && swift test
```

Result: PASS. XCTest executed 62 tests with 0 failures across `AppCoordinatorTests`, `AudioCaptureBufferTests`, `HUDModelsTests`, `HotkeyModelsTests`, `LaunchAtLoginModelsTests`, `PermissionModelsTests`, `RecordingWorkflowTests`, `SettingsSectionTests`, `TextInjectionModelsTests`, `TextInjectionProviderTests`, and `TranscriptionModelsTests`.

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Result: PASS. The command built the native debug app, generated `target/native/Voco.app/Contents/Resources/Voco.icns`, replaced the ad-hoc signature, verified the bundle, and exited with `ok: native Voco.app bundle smoke passed`.

```bash
git diff --check
```

Result: PASS. No whitespace errors.

```bash
codesign --verify --deep --strict target/native/Voco.app
```

Result: PASS. The ad-hoc signed native app bundle verified successfully.
