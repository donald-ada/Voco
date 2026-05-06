# Voco Native Text Injection Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace native Voco's static text injection placeholder with a fail-loud, diagnostic text injection provider that selects accessibility, Unicode event, or clipboard fallback insertion in-process.

**Architecture:** Keep strategy selection, errors, and provider diagnostics in `VocoAppCore` so behavior is unit-testable without macOS TCC. Put AppKit/ApplicationServices calls in `VocoApp/MacTextInjectionProvider.swift`, then wire `VocoNativeApp` to the real provider while transcription remains intentionally unconfigured until the ASR slice lands.

**Tech Stack:** Swift 6, XCTest, AppKit `NSPasteboard`, ApplicationServices accessibility APIs, CoreGraphics keyboard events, existing `TextInjectionProviding` dependency injection.

---

## Baseline

Run:

```bash
cd native && swift test
```

Expected: all existing native tests pass before this slice starts.

Observed before Task 1: PASS. XCTest executed 48 tests with 0 failures.

## File Structure

- Create `native/Sources/VocoAppCore/TextInjectionModels.swift` — `TextInjectionStrategy`, `TextInjectionSnapshot`, `TextInjectionContext`, `TextInjectionError`, `TextInsertionClient`, and `NativeTextInjectionProvider`.
- Modify `native/Sources/VocoAppCore/RecordingWorkflowModels.swift` — remove old text injection model definitions after moving them to `TextInjectionModels.swift`.
- Create `native/Tests/VocoAppCoreTests/TextInjectionModelsTests.swift` — strategy labels, strategy selection, and localized errors.
- Create `native/Tests/VocoAppCoreTests/TextInjectionProviderTests.swift` — provider behavior with a fake insertion client.
- Create `native/Sources/VocoApp/MacTextInjectionProvider.swift` — macOS accessibility, Unicode event, and clipboard fallback insertion client.
- Modify `native/Sources/VocoApp/VocoNativeApp.swift` — replace `StaticTextInjectionProvider()` with `MacTextInjectionProvider()`.
- Modify this plan with final verification results.

## Task 1: Core Text Injection Models

**Files:**
- Create: `native/Tests/VocoAppCoreTests/TextInjectionModelsTests.swift`
- Create: `native/Sources/VocoAppCore/TextInjectionModels.swift`
- Modify: `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`

- [ ] **Step 1: Write failing model tests**

Create `native/Tests/VocoAppCoreTests/TextInjectionModelsTests.swift`:

```swift
import XCTest
@testable import VocoAppCore

final class TextInjectionModelsTests: XCTestCase {
    func testStrategyTitlesAreUserVisible() {
        XCTAssertEqual(TextInjectionStrategy.directAccessibility.title, "辅助功能直接插入")
        XCTAssertEqual(TextInjectionStrategy.unicodeEvent.title, "Unicode 事件")
        XCTAssertEqual(TextInjectionStrategy.clipboardFallback.title, "剪贴板回退")
        XCTAssertEqual(TextInjectionStrategy.unavailable.title, "不可用")
        XCTAssertEqual(TextInjectionStrategy.skippedEmpty.title, "空文本跳过")
    }

    func testContextSelectsPreferredAvailableStrategy() {
        let allAvailable = TextInjectionContext(
            targetAppName: "Notes",
            isAccessibilityTrusted: true,
            supportsDirectAccessibility: true,
            supportsUnicodeEvents: true,
            supportsClipboardFallback: true
        )
        XCTAssertEqual(allAvailable.preferredStrategy, .directAccessibility)

        let unicodeOnly = TextInjectionContext(
            targetAppName: "Notes",
            isAccessibilityTrusted: true,
            supportsDirectAccessibility: false,
            supportsUnicodeEvents: true,
            supportsClipboardFallback: true
        )
        XCTAssertEqual(unicodeOnly.preferredStrategy, .unicodeEvent)

        let clipboardOnly = TextInjectionContext(
            targetAppName: "Notes",
            isAccessibilityTrusted: true,
            supportsDirectAccessibility: false,
            supportsUnicodeEvents: false,
            supportsClipboardFallback: true
        )
        XCTAssertEqual(clipboardOnly.preferredStrategy, .clipboardFallback)

        let notTrusted = TextInjectionContext(
            targetAppName: "Notes",
            isAccessibilityTrusted: false,
            supportsDirectAccessibility: true,
            supportsUnicodeEvents: true,
            supportsClipboardFallback: true
        )
        XCTAssertNil(notTrusted.preferredStrategy)
    }

    func testErrorsExposeUserVisibleMessages() {
        XCTAssertEqual(
            TextInjectionError.accessibilityPermissionMissing.localizedDescription,
            "无法插入文本：请先在系统设置中允许 Voco 使用辅助功能。"
        )
        XCTAssertEqual(
            TextInjectionError.noSupportedStrategy(targetAppName: "Terminal").localizedDescription,
            "无法插入文本：Terminal 没有可用的文本插入方式。"
        )
        XCTAssertEqual(
            TextInjectionError.clipboardRestoreFailed(message: "write failed").localizedDescription,
            "剪贴板回退后恢复原剪贴板失败：write failed"
        )
    }
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter TextInjectionModelsTests
```

Expected: compile failure because `TextInjectionContext`, `TextInjectionError`, and `TextInjectionStrategy.unavailable` do not exist.

- [ ] **Step 3: Implement text injection models**

Create `native/Sources/VocoAppCore/TextInjectionModels.swift`:

```swift
import Foundation

public enum TextInjectionStrategy: Equatable, Sendable {
    case directAccessibility
    case unicodeEvent
    case clipboardFallback
    case unavailable
    case skippedEmpty

    public var title: String {
        switch self {
        case .directAccessibility:
            "辅助功能直接插入"
        case .unicodeEvent:
            "Unicode 事件"
        case .clipboardFallback:
            "剪贴板回退"
        case .unavailable:
            "不可用"
        case .skippedEmpty:
            "空文本跳过"
        }
    }
}

public struct TextInjectionSnapshot: Equatable, Sendable {
    public let targetAppName: String?
    public let strategy: TextInjectionStrategy
    public let succeeded: Bool
    public let detail: String

    public init(targetAppName: String?, strategy: TextInjectionStrategy, succeeded: Bool, detail: String) {
        self.targetAppName = targetAppName
        self.strategy = strategy
        self.succeeded = succeeded
        self.detail = detail
    }

    public static var skippedEmpty: TextInjectionSnapshot {
        TextInjectionSnapshot(
            targetAppName: nil,
            strategy: .skippedEmpty,
            succeeded: true,
            detail: "Final transcript was empty; skipped text insertion."
        )
    }
}

public struct TextInjectionContext: Equatable, Sendable {
    public let targetAppName: String?
    public let isAccessibilityTrusted: Bool
    public let supportsDirectAccessibility: Bool
    public let supportsUnicodeEvents: Bool
    public let supportsClipboardFallback: Bool

    public init(
        targetAppName: String?,
        isAccessibilityTrusted: Bool,
        supportsDirectAccessibility: Bool,
        supportsUnicodeEvents: Bool,
        supportsClipboardFallback: Bool
    ) {
        self.targetAppName = targetAppName
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.supportsDirectAccessibility = supportsDirectAccessibility
        self.supportsUnicodeEvents = supportsUnicodeEvents
        self.supportsClipboardFallback = supportsClipboardFallback
    }

    public var preferredStrategy: TextInjectionStrategy? {
        guard isAccessibilityTrusted else {
            return nil
        }

        if supportsDirectAccessibility {
            return .directAccessibility
        }

        if supportsUnicodeEvents {
            return .unicodeEvent
        }

        if supportsClipboardFallback {
            return .clipboardFallback
        }

        return nil
    }
}

public enum TextInjectionError: LocalizedError, Equatable, Sendable {
    case accessibilityPermissionMissing
    case noSupportedStrategy(targetAppName: String?)
    case insertionFailed(strategy: TextInjectionStrategy, message: String)
    case clipboardUnavailable(message: String)
    case clipboardRestoreFailed(message: String)
    case eventPostFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "无法插入文本：请先在系统设置中允许 Voco 使用辅助功能。"
        case .noSupportedStrategy(let targetAppName):
            "无法插入文本：\(targetAppName ?? "当前 App") 没有可用的文本插入方式。"
        case .insertionFailed(let strategy, let message):
            "\(strategy.title)失败：\(message)"
        case .clipboardUnavailable(let message):
            "剪贴板不可用：\(message)"
        case .clipboardRestoreFailed(let message):
            "剪贴板回退后恢复原剪贴板失败：\(message)"
        case .eventPostFailed(let message):
            "Unicode 事件发送失败：\(message)"
        }
    }
}
```

Remove the old `TextInjectionStrategy` and `TextInjectionSnapshot` definitions from `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter TextInjectionModelsTests
```

Expected: all `TextInjectionModelsTests` pass.

- [ ] **Step 5: Commit models**

Run:

```bash
git add native/Sources/VocoAppCore/TextInjectionModels.swift native/Sources/VocoAppCore/RecordingWorkflowModels.swift native/Tests/VocoAppCoreTests/TextInjectionModelsTests.swift docs/superpowers/plans/2026-05-06-voco-native-text-injection.md
git commit -m "feat(native): add text injection models"
```

## Task 2: Core Provider Strategy Selection

**Files:**
- Modify: `native/Sources/VocoAppCore/TextInjectionModels.swift`
- Create: `native/Tests/VocoAppCoreTests/TextInjectionProviderTests.swift`

- [ ] **Step 1: Write failing provider tests**

Create `native/Tests/VocoAppCoreTests/TextInjectionProviderTests.swift`:

```swift
import XCTest
@testable import VocoAppCore

final class TextInjectionProviderTests: XCTestCase {
    @MainActor
    func testProviderSkipsEmptyTextWithoutInspectingClient() async throws {
        let client = FakeTextInsertionClient(context: .trusted())
        let provider = NativeTextInjectionProvider(client: client)

        let result = try await provider.insert(" \n ")

        XCTAssertEqual(result, .skippedEmpty)
        XCTAssertEqual(client.contextRequests, 0)
        XCTAssertTrue(client.insertions.isEmpty)
    }

    @MainActor
    func testProviderUsesDirectAccessibilityBeforeFallbacks() async throws {
        let client = FakeTextInsertionClient(context: .trusted(supportsDirectAccessibility: true))
        let provider = NativeTextInjectionProvider(client: client)

        let result = try await provider.insert("hello")

        XCTAssertEqual(client.insertions, [InsertionRequest(text: "hello", strategy: .directAccessibility)])
        XCTAssertEqual(result.targetAppName, "Notes")
        XCTAssertEqual(result.strategy, .directAccessibility)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.detail, "已通过辅助功能直接插入文本。")
    }

    @MainActor
    func testProviderFallsBackToUnicodeThenClipboard() async throws {
        let unicodeClient = FakeTextInsertionClient(
            context: .trusted(supportsDirectAccessibility: false, supportsUnicodeEvents: true)
        )
        let unicodeProvider = NativeTextInjectionProvider(client: unicodeClient)

        let unicodeResult = try await unicodeProvider.insert("hello")

        XCTAssertEqual(unicodeClient.insertions, [InsertionRequest(text: "hello", strategy: .unicodeEvent)])
        XCTAssertEqual(unicodeResult.strategy, .unicodeEvent)

        let clipboardClient = FakeTextInsertionClient(
            context: .trusted(
                supportsDirectAccessibility: false,
                supportsUnicodeEvents: false,
                supportsClipboardFallback: true
            )
        )
        let clipboardProvider = NativeTextInjectionProvider(client: clipboardClient)

        let clipboardResult = try await clipboardProvider.insert("hello")

        XCTAssertEqual(clipboardClient.insertions, [InsertionRequest(text: "hello", strategy: .clipboardFallback)])
        XCTAssertEqual(clipboardResult.strategy, .clipboardFallback)
        XCTAssertEqual(clipboardResult.detail, "已通过剪贴板回退插入文本并恢复剪贴板。")
    }

    @MainActor
    func testProviderReportsPermissionFailureWithoutCallingInsertionClient() async throws {
        let client = FakeTextInsertionClient(context: .untrusted())
        let provider = NativeTextInjectionProvider(client: client)

        let result = try await provider.insert("hello")

        XCTAssertEqual(result.strategy, .unavailable)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.detail, "无法插入文本：请先在系统设置中允许 Voco 使用辅助功能。")
        XCTAssertTrue(client.insertions.isEmpty)
    }

    @MainActor
    func testProviderReturnsFailedSnapshotWhenInsertionFails() async throws {
        let client = FakeTextInsertionClient(context: .trusted(supportsDirectAccessibility: true))
        client.error = TextInjectionError.insertionFailed(strategy: .directAccessibility, message: "AX error -25204")
        let provider = NativeTextInjectionProvider(client: client)

        let result = try await provider.insert("hello")

        XCTAssertEqual(result.targetAppName, "Notes")
        XCTAssertEqual(result.strategy, .directAccessibility)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.detail, "辅助功能直接插入失败：AX error -25204")
    }
}

private struct InsertionRequest: Equatable {
    let text: String
    let strategy: TextInjectionStrategy
}

@MainActor
private final class FakeTextInsertionClient: TextInsertionClient {
    let context: TextInjectionContext
    var error: Error?
    private(set) var contextRequests = 0
    private(set) var insertions: [InsertionRequest] = []

    init(context: TextInjectionContext) {
        self.context = context
    }

    func currentContext() async -> TextInjectionContext {
        contextRequests += 1
        return context
    }

    func insert(_ text: String, using strategy: TextInjectionStrategy) async throws {
        insertions.append(InsertionRequest(text: text, strategy: strategy))

        if let error {
            throw error
        }
    }
}

private extension TextInjectionContext {
    static func trusted(
        supportsDirectAccessibility: Bool = true,
        supportsUnicodeEvents: Bool = true,
        supportsClipboardFallback: Bool = true
    ) -> TextInjectionContext {
        TextInjectionContext(
            targetAppName: "Notes",
            isAccessibilityTrusted: true,
            supportsDirectAccessibility: supportsDirectAccessibility,
            supportsUnicodeEvents: supportsUnicodeEvents,
            supportsClipboardFallback: supportsClipboardFallback
        )
    }

    static func untrusted() -> TextInjectionContext {
        TextInjectionContext(
            targetAppName: "Notes",
            isAccessibilityTrusted: false,
            supportsDirectAccessibility: true,
            supportsUnicodeEvents: true,
            supportsClipboardFallback: true
        )
    }
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter TextInjectionProviderTests
```

Expected: compile failure because `TextInsertionClient` and `NativeTextInjectionProvider` do not exist.

- [ ] **Step 3: Implement provider and client protocol**

Append to `native/Sources/VocoAppCore/TextInjectionModels.swift`:

```swift
@MainActor
public protocol TextInsertionClient {
    func currentContext() async -> TextInjectionContext
    func insert(_ text: String, using strategy: TextInjectionStrategy) async throws
}

public final class NativeTextInjectionProvider: TextInjectionProviding {
    private let client: any TextInsertionClient

    public init(client: any TextInsertionClient) {
        self.client = client
    }

    public func insert(_ text: String) async throws -> TextInjectionSnapshot {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return .skippedEmpty
        }

        let context = await client.currentContext()
        guard context.isAccessibilityTrusted else {
            return failedSnapshot(
                context: context,
                strategy: .unavailable,
                error: TextInjectionError.accessibilityPermissionMissing
            )
        }

        guard let strategy = context.preferredStrategy else {
            return failedSnapshot(
                context: context,
                strategy: .unavailable,
                error: TextInjectionError.noSupportedStrategy(targetAppName: context.targetAppName)
            )
        }

        do {
            try await client.insert(text, using: strategy)
            return TextInjectionSnapshot(
                targetAppName: context.targetAppName,
                strategy: strategy,
                succeeded: true,
                detail: successDetail(for: strategy)
            )
        } catch {
            return failedSnapshot(context: context, strategy: strategy, error: error)
        }
    }

    private func failedSnapshot(
        context: TextInjectionContext,
        strategy: TextInjectionStrategy,
        error: Error
    ) -> TextInjectionSnapshot {
        TextInjectionSnapshot(
            targetAppName: context.targetAppName,
            strategy: strategy,
            succeeded: false,
            detail: error.localizedDescription
        )
    }

    private func successDetail(for strategy: TextInjectionStrategy) -> String {
        switch strategy {
        case .directAccessibility:
            "已通过辅助功能直接插入文本。"
        case .unicodeEvent:
            "已通过 Unicode 事件插入文本。"
        case .clipboardFallback:
            "已通过剪贴板回退插入文本并恢复剪贴板。"
        case .unavailable:
            "没有可用的文本插入方式。"
        case .skippedEmpty:
            "Final transcript was empty; skipped text insertion."
        }
    }
}
```

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter TextInjectionProviderTests
```

Expected: all `TextInjectionProviderTests` pass.

- [ ] **Step 5: Commit provider**

Run:

```bash
git add native/Sources/VocoAppCore/TextInjectionModels.swift native/Tests/VocoAppCoreTests/TextInjectionProviderTests.swift
git commit -m "feat(native): add text injection provider"
```

## Task 3: macOS Text Injection Provider

**Files:**
- Create: `native/Sources/VocoApp/MacTextInjectionProvider.swift`
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift`

- [ ] **Step 1: Implement macOS text insertion client**

Create `native/Sources/VocoApp/MacTextInjectionProvider.swift` with these concrete behaviors:

```swift
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import VocoAppCore

@MainActor
struct MacTextInjectionProvider: TextInjectionProviding {
    private let provider: NativeTextInjectionProvider

    init(client: any TextInsertionClient = MacTextInsertionClient()) {
        self.provider = NativeTextInjectionProvider(client: client)
    }

    func insert(_ text: String) async throws -> TextInjectionSnapshot {
        try await provider.insert(text)
    }
}
```

In the same file, implement `MacTextInsertionClient: TextInsertionClient`:

- `currentContext()` returns the frontmost app name, `AXIsProcessTrusted()`, focused selected-text support, Unicode event support, and clipboard fallback support.
- `insert(_:using:)` dispatches to direct accessibility, Unicode event posting, or clipboard fallback and throws `TextInjectionError.noSupportedStrategy` for `.unavailable` and `.skippedEmpty`.
- Direct accessibility sets `kAXSelectedTextAttribute` on the focused element; failed AX calls throw `TextInjectionError.insertionFailed(strategy: .directAccessibility, message: "AX error <code>")`.
- Unicode event insertion posts key down/up `CGEvent`s for each UTF-16 code unit and throws `TextInjectionError.eventPostFailed` if event creation fails.
- Clipboard fallback captures every pasteboard item's data by type, writes the transcript string, posts Command-V, waits briefly, restores the captured items, and throws `TextInjectionError.clipboardRestoreFailed` when restoration fails.

- [ ] **Step 2: Wire native app to macOS provider**

Modify `native/Sources/VocoApp/VocoNativeApp.swift`:

```swift
recordingWorkflow: NativeRecordingWorkflow(
    audioCapture: MacAudioCaptureEngine(),
    transcription: UnavailableTranscriptionProvider(),
    textInjection: MacTextInjectionProvider()
),
```

- [ ] **Step 3: Run app compile tests**

Run:

```bash
cd native && swift test
```

Expected: all native tests pass and the executable target compiles with `MacTextInjectionProvider`.

- [ ] **Step 4: Commit macOS provider**

Run:

```bash
git add native/Sources/VocoApp/MacTextInjectionProvider.swift native/Sources/VocoApp/VocoNativeApp.swift
git commit -m "feat(native): inject text with macos APIs"
```

## Task 4: Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-text-injection.md`

- [ ] **Step 1: Run full native tests**

Run:

```bash
cd native && swift test
```

Expected: all native tests pass.

- [ ] **Step 2: Run native bundle smoke**

Run from repository root:

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

Expected: no whitespace errors and a valid ad-hoc signature on `target/native/Voco.app`.

- [ ] **Step 4: Record verification results**

Append a `Verification Results` section to this plan with exact command output summaries.

- [ ] **Step 5: Commit verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-05-06-voco-native-text-injection.md
git commit -m "docs(native): mark text injection verification"
```

## Scope Notes

- Covers the native rewrite requirement that `TextInjectionEngine` reports target app, strategy, and failure reason.
- Provides clipboard fallback with explicit restoration and failure reporting.
- Keeps real ASR provider, Keychain credential storage, streaming partials, in-process HUD overlay, and release DMG notarization as separate executable slices.
