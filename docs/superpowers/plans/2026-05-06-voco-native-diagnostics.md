# Voco Native Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. If any subagent is dispatched for this plan, use GPT-5.5 xhigh.

**Goal:** Add a native Diagnostics window and redacted diagnostic bundle export for Voco runtime health, recent failures, and recent audio/transcription/injection state.

**Architecture:** Keep diagnostic categories, severity/status mapping, redaction, serializable bundle data, and file export errors in `VocoAppCore` so they are testable without AppKit. `AppCoordinator` exposes a computed `diagnosticsSnapshot` from existing published runtime state; `VocoApp` adds a presenter, SwiftUI view, and menu item that opens the diagnostics window and exports through core APIs.

**Tech Stack:** Swift 6, XCTest, SwiftUI, AppKit `NSWindow`, Foundation `JSONEncoder`/`Data.write`, existing `AppCoordinator` runtime snapshots.

---

## Baseline

User-provided baseline before this task:

```bash
cd native && swift test
```

Observed: PASS. XCTest executed 99 tests, 1 skipped, 0 failures.

## Constraints

- Work only in `/private/tmp/voco-native-diagnostics` on branch `codex/native-diagnostics`.
- Do not merge to `master`.
- Do not revert or overwrite unrelated work from other agents.
- Do not export raw API keys or transcript body by default.
- Use explicit redaction placeholders: `[redacted secret]` and `[redacted transcript]`.
- IO failures must fail loudly through a descriptive `LocalizedError`; no silent catches.
- SwiftUI visual snapshot tests are not required for this slice.

## File Structure

- Create `native/Sources/VocoAppCore/DiagnosticsModels.swift` — diagnostic categories, severity, events, snapshot construction, redaction helpers.
- Create `native/Sources/VocoAppCore/DiagnosticBundleModels.swift` — `Codable` redacted bundle, JSON data generation, exporter, and export errors.
- Modify `native/Sources/VocoAppCore/AppCoordinator.swift` — expose computed `diagnosticsSnapshot` and export helper from existing runtime state.
- Create `native/Sources/VocoApp/DiagnosticsWindowPresenter.swift` — AppKit window lifecycle matching `SettingsWindowPresenter`.
- Create `native/Sources/VocoApp/DiagnosticsView.swift` — native SwiftUI diagnostics list and export button.
- Modify `native/Sources/VocoApp/VocoNativeApp.swift` — add distinct menu item `打开诊断`.
- Create `native/Tests/VocoAppCoreTests/DiagnosticsModelsTests.swift` — model, coordinator snapshot, redaction, export data, and IO failure coverage.
- Modify this plan with final verification notes after all checks run.

## Task 1: Diagnostic Event Model and Redaction Rules

**Files:**
- Create: `native/Tests/VocoAppCoreTests/DiagnosticsModelsTests.swift`
- Create: `native/Sources/VocoAppCore/DiagnosticsModels.swift`

- [ ] **Step 1: Write failing diagnostic model tests**

Create `native/Tests/VocoAppCoreTests/DiagnosticsModelsTests.swift` with tests that assert:

```swift
let snapshot = DiagnosticsSnapshot(
    generatedAt: Date(timeIntervalSince1970: 1),
    appStatusTitle: "错误",
    events: [
        DiagnosticEvent(category: .permission, severity: .ok, title: "麦克风", detail: "已允许"),
        DiagnosticEvent(category: .audio, severity: .warning, title: "音频", detail: "无近期采样"),
        DiagnosticEvent(category: .hotkey, severity: .ok, title: "快捷键", detail: "监听中"),
        DiagnosticEvent(category: .asr, severity: .error, title: "ASR", detail: "认证失败"),
        DiagnosticEvent(category: .injection, severity: .ok, title: "输入", detail: "已插入"),
        DiagnosticEvent(category: .failure, severity: .error, title: "最近失败", detail: "认证失败")
    ]
)
XCTAssertEqual(snapshot.categories, [.permission, .audio, .hotkey, .asr, .injection, .failure])
XCTAssertEqual(snapshot.overallSeverity, .error)
XCTAssertEqual(DiagnosticCategory.asr.title, "ASR")
XCTAssertEqual(DiagnosticSeverity.warning.systemImage, "exclamationmark.triangle.fill")

let redacted = DiagnosticRedactor.redact(
    "raw key sk-live-abcdef123456 and transcript 你好 Voco",
    secrets: ["sk-live-abcdef123456"],
    transcriptBodies: ["你好 Voco"]
)
XCTAssertFalse(redacted.contains("sk-live-abcdef123456"))
XCTAssertFalse(redacted.contains("你好 Voco"))
XCTAssertTrue(redacted.contains("[redacted secret]"))
XCTAssertTrue(redacted.contains("[redacted transcript]"))
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter DiagnosticsModelsTests
```

Expected: compile failure because `DiagnosticsSnapshot`, `DiagnosticEvent`, `DiagnosticCategory`, `DiagnosticSeverity`, and `DiagnosticRedactor` do not exist.

- [ ] **Step 3: Implement diagnostics model types**

Create `native/Sources/VocoAppCore/DiagnosticsModels.swift` with `DiagnosticCategory`, `DiagnosticSeverity`, `DiagnosticEvent`, `DiagnosticsSnapshot`, and `DiagnosticRedactor`.

Required details:

- `DiagnosticCategory` cases: `.permission`, `.audio`, `.hotkey`, `.asr`, `.injection`, `.failure`.
- Category titles: `权限`, `音频`, `快捷键`, `ASR`, `输入`, `最近失败`.
- `DiagnosticSeverity` cases: `.ok`, `.warning`, `.error`, with comparable rank `0`, `1`, `2`.
- Severity symbols: `checkmark.circle.fill`, `exclamationmark.triangle.fill`, `xmark.octagon.fill`.
- `DiagnosticsSnapshot.categories` preserves the first-seen category order from `events`.
- `DiagnosticsSnapshot.overallSeverity` returns the highest event severity or `.ok`.
- `DiagnosticRedactor.redact` replaces any non-empty secret with `[redacted secret]` and any non-empty transcript body with `[redacted transcript]`.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter DiagnosticsModelsTests
```

Expected: `DiagnosticsModelsTests` pass.

## Task 2: Coordinator Diagnostic Event Capture

**Files:**
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Sources/VocoAppCore/DiagnosticsModels.swift`
- Modify: `native/Tests/VocoAppCoreTests/DiagnosticsModelsTests.swift`

- [ ] **Step 1: Add failing coordinator snapshot tests**

Append tests that construct an `AppCoordinator` with:

```swift
let result = RecordingWorkflowResult(
    audio: CapturedAudioSnapshot(durationSeconds: 1.2, sampleRate: 16_000, peakAmplitude: 0.64),
    transcript: TranscriptSnapshot(
        finalText: "raw transcript body",
        partials: ["raw partial"],
        providerName: "Fake ASR",
        latencyMilliseconds: 42
    ),
    injection: TextInjectionSnapshot(
        targetAppName: "TextEdit",
        strategy: .unicodeEvent,
        succeeded: true,
        detail: "已通过 Unicode 事件插入文本。"
    )
)
let coordinator = AppCoordinator(
    hasCompletedOnboarding: true,
    transcriptionCredentialStore: InMemoryTranscriptionCredentialStore(apiKey: "sk-live-abcdef123456"),
    recordingWorkflow: StaticRecordingWorkflow(result: result, transcriptionStatus: .ready(providerName: "Fake ASR")),
    hotkeyProvider: StaticHotkeyProvider(state: .listening)
)
coordinator.finishLaunching()
await coordinator.toggleRecordingFromUserAction()
await coordinator.toggleRecordingFromUserAction()
```

Assertions:

```swift
let snapshot = coordinator.diagnosticsSnapshot
XCTAssertEqual(snapshot.categories, [.permission, .audio, .hotkey, .asr, .injection, .failure])
XCTAssertTrue(snapshot.events.contains { $0.category == .permission && $0.title.contains("麦克风") })
XCTAssertTrue(snapshot.events.contains { $0.category == .audio && $0.detail.contains("1.20s") })
XCTAssertTrue(snapshot.events.contains { $0.category == .hotkey && $0.detail.contains("Right Command") })
XCTAssertTrue(snapshot.events.contains { $0.category == .asr && $0.title.contains("Fake ASR") })
XCTAssertTrue(snapshot.events.contains { $0.category == .injection && $0.detail.contains("TextEdit") })
XCTAssertTrue(snapshot.events.contains { $0.category == .failure && $0.severity == .ok })
```

Add a second test where `coordinator.fail("provider offline")` makes the `.failure` event `.error` with detail `provider offline`.

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter DiagnosticsModelsTests
```

Expected: compile failure because `AppCoordinator` has no `diagnosticsSnapshot`.

- [ ] **Step 3: Implement coordinator snapshot capture**

Add `public var diagnosticsSnapshot: DiagnosticsSnapshot` to `AppCoordinator`, built from current `snapshot.title`, `permissions`, `lastAudio`, `hotkeyRuntimeState`, `hotkeyBinding`, `hotkeyMode`, `transcriptionProviderStatus`, `transcriptionCredentials`, `lastTranscript`, `lastInjection`, and `lastErrorMessage`.

Add a `DiagnosticsSnapshot` initializer or factory in `DiagnosticsModels.swift` that always emits these categories:

- Permission events: one per `PermissionSnapshot`, severity `.ok` if granted, `.warning` for not determined/unknown, `.error` for denied/restricted required permission.
- Audio event: recent duration/sample rate/peak if available; otherwise warning `无近期采样`.
- Hotkey event: runtime state, binding display name, mode title.
- ASR events: provider status and credential status; transcript event includes provider, character count, partial count, latency, not transcript body.
- Injection event: recent target/strategy/detail or warning if no recent injection.
- Failure event: `.error` with `lastErrorMessage` when present, otherwise `.ok` with `无近期失败`.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter DiagnosticsModelsTests
```

Expected: `DiagnosticsModelsTests` pass.

- [ ] **Step 5: Commit diagnostics models**

Run:

```bash
git add native/Sources/VocoAppCore/DiagnosticsModels.swift native/Sources/VocoAppCore/AppCoordinator.swift native/Tests/VocoAppCoreTests/DiagnosticsModelsTests.swift
git commit -m "feat(native): add diagnostics models"
```

## Task 3: Diagnostics Window Presenter

**Files:**
- Create: `native/Sources/VocoApp/DiagnosticsWindowPresenter.swift`

- [ ] **Step 1: Implement presenter following settings presenter pattern**

Create `DiagnosticsWindowPresenter` as `@MainActor final class` with a `static let shared`, a retained optional `NSWindow`, and `show(coordinator:)`. It should mirror `SettingsWindowPresenter`, use `DiagnosticsView(coordinator:)`, create an `820x560` titled/resizable window, set title `Voco 诊断`, center it, retain it, activate `NSApp`, and call `makeKeyAndOrderFront(nil)`.

- [ ] **Step 2: Build RED-ish to expose missing view**

Run:

```bash
cd native && swift build
```

Expected: compile failure because `DiagnosticsView` does not exist.

## Task 4: DiagnosticsView Rendering

**Files:**
- Create: `native/Sources/VocoApp/DiagnosticsView.swift`

- [ ] **Step 1: Implement DiagnosticsView**

Create `DiagnosticsView` with:

- `@ObservedObject var coordinator: AppCoordinator`
- `@State private var exportMessage: String?`
- Header `Voco 诊断`, generated timestamp/status, and `Label(snapshot.overallSeverity.title, systemImage: snapshot.overallSeverity.systemImage)`.
- A section per `DiagnosticCategory.allCases` with rows for `snapshot.events.filter { $0.category == category }`.
- Rows showing severity icon, title, and wrapped detail text.
- Export button `导出诊断包`; before Task 5 it may set `exportMessage = "诊断导出将在下一步启用。"` so the window commit compiles independently.

- [ ] **Step 2: Run GREEN build**

Run:

```bash
cd native && swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit diagnostics window**

Run:

```bash
git add native/Sources/VocoApp/DiagnosticsWindowPresenter.swift native/Sources/VocoApp/DiagnosticsView.swift
git commit -m "feat(native): show diagnostics window"
```

## Task 5: Redacted Diagnostic Bundle Export

**Files:**
- Create: `native/Sources/VocoAppCore/DiagnosticBundleModels.swift`
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Sources/VocoApp/DiagnosticsView.swift`
- Modify: `native/Tests/VocoAppCoreTests/DiagnosticsModelsTests.swift`

- [ ] **Step 1: Add failing export tests**

Append tests that assert:

```swift
let snapshot = DiagnosticsSnapshot(
    generatedAt: Date(timeIntervalSince1970: 1),
    appStatusTitle: "就绪",
    events: [
        DiagnosticEvent(id: "asr", category: .asr, severity: .ok, title: "Doubao", detail: "stored secret sk-live-abcdef123456"),
        DiagnosticEvent(id: "transcript", category: .asr, severity: .ok, title: "转写", detail: "raw transcript body")
    ]
)
let bundle = DiagnosticBundle(
    snapshot: snapshot,
    redaction: DiagnosticRedactionContext(
        secrets: ["sk-live-abcdef123456"],
        transcriptBodies: ["raw transcript body"]
    )
)
let json = String(decoding: try bundle.jsonData(), as: UTF8.self)
XCTAssertFalse(json.contains("sk-live-abcdef123456"))
XCTAssertFalse(json.contains("raw transcript body"))
XCTAssertTrue(json.contains("[redacted secret]"))
XCTAssertTrue(json.contains("[redacted transcript]"))
```

Add an IO test:

```swift
let bundle = DiagnosticBundle(snapshot: DiagnosticsSnapshot(generatedAt: Date(timeIntervalSince1970: 1), appStatusTitle: "就绪", events: []))
let blockedURL = URL(fileURLWithPath: "/dev/null/voco-diagnostics.json")
XCTAssertThrowsError(try DiagnosticBundleExporter.write(bundle: bundle, to: blockedURL)) { error in
    XCTAssertTrue(error.localizedDescription.contains("导出诊断包失败"))
    XCTAssertTrue(error.localizedDescription.contains(blockedURL.path))
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter DiagnosticsModelsTests
```

Expected: compile failure because `DiagnosticBundle`, `DiagnosticRedactionContext`, and `DiagnosticBundleExporter` do not exist.

- [ ] **Step 3: Implement redacted bundle model and exporter**

Create `DiagnosticBundleModels.swift` with:

- `DiagnosticRedactionContext(secrets: [String] = [], transcriptBodies: [String] = [])`.
- `DiagnosticBundle: Codable, Equatable, Sendable` containing `generatedAt`, `appStatusTitle`, `overallSeverity`, `events`, and `redactionNotice`.
- `DiagnosticBundle.init(snapshot:redaction:)` redacts `appStatusTitle`, every event title, and every event detail.
- `jsonData()` using pretty printed, sorted-key JSON and ISO-8601 dates.
- `DiagnosticBundleExportError.writeFailed(path:message:)` whose `localizedDescription` starts with `导出诊断包失败`.
- `DiagnosticBundleExporter.write(bundle:to:)` that writes atomically and maps any thrown error to `DiagnosticBundleExportError`.

Add `AppCoordinator.diagnosticBundle()` and `AppCoordinator.exportDiagnosticBundle(to:)`. Pass transcript final text and partials into the redaction context. The app only has masked Keychain state, but model tests still verify raw secret redaction.

- [ ] **Step 4: Wire DiagnosticsView export button**

Update the export button to write to:

```swift
FileManager.default.temporaryDirectory
    .appendingPathComponent("voco-diagnostics-\(Int(Date().timeIntervalSince1970)).json")
```

On success set `exportMessage` to `已导出：<path>`. On failure set `exportMessage` to `error.localizedDescription` and call `coordinator.fail(error.localizedDescription)`.

- [ ] **Step 5: Run GREEN**

Run:

```bash
cd native && swift test --filter DiagnosticsModelsTests
cd native && swift build
```

Expected: diagnostics tests and native build pass.

- [ ] **Step 6: Commit redacted export**

Run:

```bash
git add native/Sources/VocoAppCore/DiagnosticBundleModels.swift native/Sources/VocoAppCore/AppCoordinator.swift native/Sources/VocoApp/DiagnosticsView.swift native/Tests/VocoAppCoreTests/DiagnosticsModelsTests.swift
git commit -m "feat(native): export redacted diagnostics bundle"
```

## Task 6: Menu Bar Diagnostics Action

**Files:**
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift`

- [ ] **Step 1: Add diagnostics menu item**

Modify the menu after `检查权限`:

```swift
Button("打开诊断") {
    coordinator.prepareForSettingsPresentation()
    DiagnosticsWindowPresenter.shared.show(coordinator: coordinator)
}
```

This item must be distinct from `打开设置` and `检查权限`.

- [ ] **Step 2: Verify native build**

Run:

```bash
cd native && swift build
```

Expected: build succeeds and `DiagnosticsWindowPresenter` is linked from the app target.

- [ ] **Step 3: Commit menu action**

Run:

```bash
git add native/Sources/VocoApp/VocoNativeApp.swift native/Sources/VocoApp/DiagnosticsWindowPresenter.swift native/Sources/VocoApp/DiagnosticsView.swift
git commit -m "feat(native): show diagnostics window"
```

If the window files were already committed in Task 4, amend or combine this menu item into that same logical commit instead of creating duplicate `feat(native): show diagnostics window` commits.

## Task 7: Full Verification and Documentation

**Files:**
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-diagnostics.md`

- [ ] **Step 1: Run full verification**

Run:

```bash
cd native && swift test
packaging/tests/native_app_bundle_smoke.sh
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Expected:

- `swift test`: all native tests pass.
- `packaging/tests/native_app_bundle_smoke.sh`: native app bundle smoke check passes.
- `git diff --check`: no whitespace errors.
- `codesign --verify --deep --strict target/native/Voco.app`: app bundle signature verifies, or failure is recorded exactly if the local smoke/build process does not produce or sign `target/native/Voco.app`.

- [ ] **Step 2: Update verification notes**

Append:

```markdown
## Verification Notes

- `cd native && swift test`: ...
- `packaging/tests/native_app_bundle_smoke.sh`: ...
- `git diff --check`: ...
- `codesign --verify --deep --strict target/native/Voco.app`: ...
```

- [ ] **Step 3: Commit verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-05-06-voco-native-diagnostics.md
git commit -m "docs(native): mark diagnostics verification"
```

## Spec Coverage Self-Review

- Task 1 covers diagnostic event model and redaction rules.
- Task 2 covers coordinator diagnostic event capture from existing runtime state.
- Task 3 covers Diagnostics window presenter.
- Task 4 covers DiagnosticsView rendering.
- Task 5 covers redacted diagnostic bundle export and loud IO failure mapping.
- Task 6 covers menu bar diagnostics action.
- Task 7 covers full verification and documentation.
- The required categories are permission, audio, hotkey, ASR, injection, and recent failure.
- Raw API key and raw transcript body are excluded from default export by model design and test coverage.

## Verification Notes

- `cd native && swift test`: PASS. XCTest executed 106 tests, 1 skipped, 0 failures.
- `packaging/tests/native_app_bundle_smoke.sh`: PASS. Built native Swift app, generated `target/native/Voco.app/Contents/Resources/Voco.icns`, replaced existing signature, verified bundle, and reported `ok: native Voco.app bundle smoke passed`.
- `git diff --check`: PASS. Command exited 0 with no output.
- `codesign --verify --deep --strict target/native/Voco.app`: PASS. Command exited 0 with no output.

## Review Fix Verification Notes

- `cd native && swift test`: PASS. XCTest executed 110 tests, 1 skipped, 0 failures.
- `packaging/tests/native_app_bundle_smoke.sh`: PASS. Built native Swift app, generated `target/native/Voco.app/Contents/Resources/Voco.icns`, replaced existing signature, verified bundle, and reported `ok: native Voco.app bundle smoke passed`.
- `git diff --check`: PASS. Command exited 0 with no output.
- `codesign --verify --deep --strict target/native/Voco.app`: PASS. Command exited 0 with no output.
