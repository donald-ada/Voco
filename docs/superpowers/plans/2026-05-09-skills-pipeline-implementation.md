# Skills Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Voco's first Skills milestone: a testable transcript post-processing pipeline plus a Filler Cleanup skill that runs after ASR and before text insertion.

**Architecture:** Keep all behavior in `VocoAppCore`: rules, diagnostics, pipeline, settings snapshots, and workflow integration. App-layer code only persists preferences, persists session metadata, and renders the Skills settings page. Model provider registry and local model download are intentionally outside this implementation plan and should get their own plan when Stage 1 is done.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, `UserDefaults`, SQLite through the existing `SQLite3` adapter.

---

## Scope Check

This plan implements Stage 1 from `docs/superpowers/specs/2026-05-09-skills-and-model-roadmap-design.md`:

- Skills navigation
- transcript post-processing pipeline
- Filler Cleanup skill
- global rule settings
- preview
- recent-session traceability

This plan does not implement provider registry, custom cloud provider, dynamic model switching, local model catalog, local model download, or local ASR runtime integration.

## File Structure

- Create `native/Sources/VocoAppCore/TranscriptPostProcessingModels.swift`
  - Owns pipeline input/output, diagnostics, skill protocol, filler rule model, filler settings, and the default filler cleanup implementation.
- Create `native/Sources/VocoAppCore/SkillSettingsModels.swift`
  - Owns Skills page snapshots and actions that SwiftUI can render without business logic.
- Create `native/Sources/VocoApp/MacSkillPreferenceStore.swift`
  - Persists skills settings in `UserDefaults`.
- Modify `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`
  - Adds post-processing to `NativeRecordingWorkflow`, and extends `RecordingWorkflowResult` with the post-processing result.
- Modify `native/Sources/VocoAppCore/VoiceInputSessionModels.swift`
  - Stores processed transcript as the list text while preserving raw transcript and post-processing diagnostics for details.
- Modify `native/Sources/VocoApp/MacVoiceInputSessionStore.swift`
  - Adds SQLite columns for raw transcript and post-processing diagnostics, with a migration that preserves existing rows.
- Modify `native/Sources/VocoAppCore/AppCoordinator.swift`
  - Loads/saves skills settings, exposes Skills snapshots/actions, and refreshes session/history data after recordings.
- Modify `native/Sources/VocoAppCore/SettingsWorkbenchModels.swift`
  - Adds `SettingsWorkbenchSection.skills`, localized title/summary, status, and sidebar icon support.
- Modify `native/Sources/VocoAppCore/VocoStrings.swift`
  - Adds Skills page labels, diagnostics, empty states, and English copy.
- Modify `native/Sources/VocoApp/SettingsView.swift`
  - Routes `.skills` to a dedicated Skills view and exposes shared workbench styling used by split view files.
- Create `native/Sources/VocoApp/SettingsSkillsView.swift`
  - Renders the Skills page, rule list, and preview panel.
- Modify `native/Sources/VocoApp/VocoNativeApp.swift`
  - Instantiates `MacSkillPreferenceStore` and injects it into `AppCoordinator` and `NativeRecordingWorkflow`.
- Add tests under `native/Tests/VocoAppCoreTests` and `native/Tests/VocoAppTests` as listed in each task.

## Task 1: Core Filler Cleanup Models

**Files:**
- Create: `native/Sources/VocoAppCore/TranscriptPostProcessingModels.swift`
- Test: `native/Tests/VocoAppCoreTests/TranscriptPostProcessingModelsTests.swift`

- [ ] **Step 1: Write failing tests for plain text deletion, replacement, disabled rules, deterministic order, and diagnostics**

Add:

```swift
import XCTest
@testable import VocoAppCore

final class TranscriptPostProcessingModelsTests: XCTestCase {
    func testFillerCleanupDeletesPlainTextFillers() {
        let settings = FillerCleanupSettings(
            isEnabled: true,
            rules: [
                FillerCleanupRule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    displayName: "删除嗯",
                    matchText: "嗯",
                    matchType: .plainText,
                    action: .delete,
                    isEnabled: true,
                    order: 0
                )
            ]
        )
        let skill = FillerCleanupSkill(settings: settings)
        let result = skill.process(
            "嗯今天我们开始测试",
            context: TranscriptPostProcessingContext(targetAppName: "Notes")
        )

        XCTAssertEqual(result.processedText, "今天我们开始测试")
        XCTAssertEqual(result.diagnostics.count, 1)
        XCTAssertEqual(result.diagnostics.first?.matchedText, "嗯")
        XCTAssertEqual(result.diagnostics.first?.replacementText, "")
        XCTAssertEqual(result.diagnostics.first?.matchCount, 1)
    }

    func testFillerCleanupCanReplaceWithSpaceAndCustomText() {
        let settings = FillerCleanupSettings(
            isEnabled: true,
            rules: [
                FillerCleanupRule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    displayName: "空格替换",
                    matchText: "然后",
                    matchType: .plainText,
                    action: .replace(" "),
                    isEnabled: true,
                    order: 0
                ),
                FillerCleanupRule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                    displayName: "自定义替换",
                    matchText: "那个",
                    matchType: .plainText,
                    action: .replace("这件事"),
                    isEnabled: true,
                    order: 1
                )
            ]
        )
        let result = FillerCleanupSkill(settings: settings).process(
            "然后那个我们继续",
            context: TranscriptPostProcessingContext(targetAppName: nil)
        )

        XCTAssertEqual(result.processedText, " 这件事我们继续")
        XCTAssertEqual(result.diagnostics.map(\.ruleDisplayName), ["空格替换", "自定义替换"])
    }

    func testDisabledFillerRuleDoesNotChangeText() {
        let settings = FillerCleanupSettings(
            isEnabled: true,
            rules: [
                FillerCleanupRule(
                    displayName: "禁用规则",
                    matchText: "就是",
                    action: .delete,
                    isEnabled: false,
                    order: 0
                )
            ]
        )
        let result = FillerCleanupSkill(settings: settings).process(
            "就是这样",
            context: TranscriptPostProcessingContext(targetAppName: nil)
        )

        XCTAssertEqual(result.processedText, "就是这样")
        XCTAssertTrue(result.diagnostics.isEmpty)
    }

    func testRulesRunInOrder() {
        let settings = FillerCleanupSettings(
            isEnabled: true,
            rules: [
                FillerCleanupRule(displayName: "第二个", matchText: "今天", action: .replace("明天"), isEnabled: true, order: 1),
                FillerCleanupRule(displayName: "第一个", matchText: "嗯", action: .delete, isEnabled: true, order: 0)
            ]
        )
        let result = FillerCleanupSkill(settings: settings).process(
            "嗯今天",
            context: TranscriptPostProcessingContext(targetAppName: nil)
        )

        XCTAssertEqual(result.processedText, "明天")
        XCTAssertEqual(result.diagnostics.map(\.ruleDisplayName), ["第一个", "第二个"])
    }

    func testPipelinePreservesOriginalAndProcessedText() {
        let pipeline = TranscriptPostProcessingPipeline(
            settings: SkillSettings(
                isEnabled: true,
                fillerCleanup: FillerCleanupSettings(
                    isEnabled: true,
                    rules: [FillerCleanupRule(displayName: "删除啊", matchText: "啊", action: .delete, isEnabled: true, order: 0)]
                )
            )
        )
        let result = pipeline.process(
            "啊开始",
            context: TranscriptPostProcessingContext(targetAppName: "Notes")
        )

        XCTAssertEqual(result.originalText, "啊开始")
        XCTAssertEqual(result.processedText, "开始")
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.diagnostics.first?.skillID, FillerCleanupSkill.skillID)
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --package-path native --filter TranscriptPostProcessingModelsTests
```

Expected: build fails because `FillerCleanupSettings`, `FillerCleanupRule`, `FillerCleanupSkill`, `SkillSettings`, and `TranscriptPostProcessingPipeline` do not exist.

- [ ] **Step 3: Add the minimal core models and implementation**

Create `native/Sources/VocoAppCore/TranscriptPostProcessingModels.swift`:

```swift
import Foundation

public struct TranscriptPostProcessingContext: Equatable, Sendable {
    public let targetAppName: String?

    public init(targetAppName: String?) {
        self.targetAppName = targetAppName
    }
}

public struct TranscriptPostProcessingDiagnostic: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let skillID: String
    public let ruleID: UUID
    public let ruleDisplayName: String
    public let matchedText: String
    public let replacementText: String
    public let matchCount: Int

    public init(
        id: UUID = UUID(),
        skillID: String,
        ruleID: UUID,
        ruleDisplayName: String,
        matchedText: String,
        replacementText: String,
        matchCount: Int
    ) {
        self.id = id
        self.skillID = skillID
        self.ruleID = ruleID
        self.ruleDisplayName = ruleDisplayName
        self.matchedText = matchedText
        self.replacementText = replacementText
        self.matchCount = matchCount
    }
}

public struct TranscriptPostProcessingResult: Codable, Equatable, Sendable {
    public static func unchanged(_ text: String) -> TranscriptPostProcessingResult {
        TranscriptPostProcessingResult(originalText: text, processedText: text, diagnostics: [])
    }

    public let originalText: String
    public let processedText: String
    public let diagnostics: [TranscriptPostProcessingDiagnostic]

    public init(
        originalText: String,
        processedText: String,
        diagnostics: [TranscriptPostProcessingDiagnostic]
    ) {
        self.originalText = originalText
        self.processedText = processedText
        self.diagnostics = diagnostics
    }

    public var changed: Bool {
        originalText != processedText
    }
}

public enum FillerCleanupMatchType: String, Codable, Equatable, Sendable {
    case plainText
    case regex
}

public enum FillerCleanupAction: Codable, Equatable, Sendable {
    case delete
    case replace(String)

    public var replacementText: String {
        switch self {
        case .delete:
            ""
        case .replace(let value):
            value
        }
    }
}

public struct FillerCleanupRule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var displayName: String
    public var matchText: String
    public var matchType: FillerCleanupMatchType
    public var action: FillerCleanupAction
    public var isEnabled: Bool
    public var order: Int

    public init(
        id: UUID = UUID(),
        displayName: String,
        matchText: String,
        matchType: FillerCleanupMatchType = .plainText,
        action: FillerCleanupAction,
        isEnabled: Bool,
        order: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.matchText = matchText
        self.matchType = matchType
        self.action = action
        self.isEnabled = isEnabled
        self.order = order
    }
}

public struct FillerCleanupSettings: Codable, Equatable, Sendable {
    public static let defaultRules: [FillerCleanupRule] = [
        FillerCleanupRule(displayName: "嗯", matchText: "嗯", action: .delete, isEnabled: true, order: 0),
        FillerCleanupRule(displayName: "呃", matchText: "呃", action: .delete, isEnabled: true, order: 1),
        FillerCleanupRule(displayName: "啊", matchText: "啊", action: .delete, isEnabled: true, order: 2),
        FillerCleanupRule(displayName: "这个", matchText: "这个", action: .delete, isEnabled: true, order: 3),
        FillerCleanupRule(displayName: "那个", matchText: "那个", action: .delete, isEnabled: true, order: 4),
        FillerCleanupRule(displayName: "就是", matchText: "就是", action: .delete, isEnabled: true, order: 5),
        FillerCleanupRule(displayName: "然后", matchText: "然后", action: .delete, isEnabled: true, order: 6)
    ]

    public static let `default` = FillerCleanupSettings(isEnabled: false, rules: defaultRules)

    public var isEnabled: Bool
    public var rules: [FillerCleanupRule]

    public init(isEnabled: Bool, rules: [FillerCleanupRule]) {
        self.isEnabled = isEnabled
        self.rules = rules
    }
}

public struct SkillSettings: Codable, Equatable, Sendable {
    public static let `default` = SkillSettings(isEnabled: true, fillerCleanup: .default)

    public var isEnabled: Bool
    public var fillerCleanup: FillerCleanupSettings

    public init(isEnabled: Bool, fillerCleanup: FillerCleanupSettings) {
        self.isEnabled = isEnabled
        self.fillerCleanup = fillerCleanup
    }
}

public protocol TranscriptPostProcessingSkill: Sendable {
    var id: String { get }
    func process(_ text: String, context: TranscriptPostProcessingContext) -> SkillProcessingOutput
}

public struct SkillProcessingOutput: Equatable, Sendable {
    public let processedText: String
    public let diagnostics: [TranscriptPostProcessingDiagnostic]

    public init(processedText: String, diagnostics: [TranscriptPostProcessingDiagnostic]) {
        self.processedText = processedText
        self.diagnostics = diagnostics
    }
}

public struct FillerCleanupSkill: TranscriptPostProcessingSkill {
    public static let skillID = "fillerCleanup"

    public let settings: FillerCleanupSettings

    public init(settings: FillerCleanupSettings) {
        self.settings = settings
    }

    public var id: String { Self.skillID }

    public func process(_ text: String, context: TranscriptPostProcessingContext) -> SkillProcessingOutput {
        guard settings.isEnabled else {
            return SkillProcessingOutput(processedText: text, diagnostics: [])
        }

        var processedText = text
        var diagnostics: [TranscriptPostProcessingDiagnostic] = []

        for rule in settings.rules.sorted(by: { $0.order == $1.order ? $0.displayName < $1.displayName : $0.order < $1.order }) {
            guard rule.isEnabled, !rule.matchText.isEmpty, rule.matchType == .plainText else {
                continue
            }

            let matchCount = processedText.components(separatedBy: rule.matchText).count - 1
            guard matchCount > 0 else {
                continue
            }

            let replacement = rule.action.replacementText
            processedText = processedText.replacingOccurrences(of: rule.matchText, with: replacement)
            diagnostics.append(
                TranscriptPostProcessingDiagnostic(
                    skillID: Self.skillID,
                    ruleID: rule.id,
                    ruleDisplayName: rule.displayName,
                    matchedText: rule.matchText,
                    replacementText: replacement,
                    matchCount: matchCount
                )
            )
        }

        return SkillProcessingOutput(processedText: processedText, diagnostics: diagnostics)
    }
}

public struct TranscriptPostProcessingPipeline: Sendable {
    public let settings: SkillSettings

    public init(settings: SkillSettings = .default) {
        self.settings = settings
    }

    public func process(
        _ text: String,
        context: TranscriptPostProcessingContext
    ) -> TranscriptPostProcessingResult {
        guard settings.isEnabled else {
            return .unchanged(text)
        }

        let fillerOutput = FillerCleanupSkill(settings: settings.fillerCleanup).process(text, context: context)
        return TranscriptPostProcessingResult(
            originalText: text,
            processedText: fillerOutput.processedText,
            diagnostics: fillerOutput.diagnostics
        )
    }
}
```

- [ ] **Step 4: Run focused tests and verify they pass**

Run:

```bash
swift test --package-path native --filter TranscriptPostProcessingModelsTests
```

Expected: all `TranscriptPostProcessingModelsTests` pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add native/Sources/VocoAppCore/TranscriptPostProcessingModels.swift \
  native/Tests/VocoAppCoreTests/TranscriptPostProcessingModelsTests.swift
git commit -m "Add transcript post-processing models"
```

## Task 2: Skills Preference Store

**Files:**
- Modify: `native/Sources/VocoAppCore/TranscriptPostProcessingModels.swift`
- Create: `native/Sources/VocoApp/MacSkillPreferenceStore.swift`
- Test: `native/Tests/VocoAppTests/MacSkillPreferenceStoreTests.swift`
- Test: `native/Tests/VocoAppCoreTests/TranscriptPostProcessingModelsTests.swift`

- [ ] **Step 1: Add failing persistence tests**

Append to `TranscriptPostProcessingModelsTests`:

```swift
func testNoOpSkillPreferenceStoreReturnsDefaultSettings() {
    XCTAssertEqual(NoOpSkillPreferenceStore().skillSettings, .default)
}
```

Create `native/Tests/VocoAppTests/MacSkillPreferenceStoreTests.swift`:

```swift
import XCTest
@testable import VocoApp
@testable import VocoAppCore

@MainActor
final class MacSkillPreferenceStoreTests: XCTestCase {
    func testSkillSettingsRoundTripThroughUserDefaults() throws {
        let suiteName = "MacSkillPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = MacSkillPreferenceStore(defaults: defaults)
        let ruleID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let settings = SkillSettings(
            isEnabled: true,
            fillerCleanup: FillerCleanupSettings(
                isEnabled: true,
                rules: [
                    FillerCleanupRule(
                        id: ruleID,
                        displayName: "自定义",
                        matchText: "就是说",
                        action: .replace(""),
                        isEnabled: true,
                        order: 0
                    )
                ]
            )
        )

        store.saveSkillSettings(settings)

        XCTAssertEqual(MacSkillPreferenceStore(defaults: defaults).skillSettings, settings)
    }

    func testInvalidStoredSkillSettingsFallsBackToDefault() throws {
        let suiteName = "MacSkillPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: "skills.settings")

        XCTAssertEqual(MacSkillPreferenceStore(defaults: defaults).skillSettings, .default)
    }
}
```

- [ ] **Step 2: Run focused tests and verify they fail**

Run:

```bash
swift test --package-path native --filter SkillPreferenceStore
```

Expected: build fails because `SkillPreferenceStoring`, `NoOpSkillPreferenceStore`, and `MacSkillPreferenceStore` do not exist.

- [ ] **Step 3: Add core preference protocol and no-op store**

Append to `TranscriptPostProcessingModels.swift`:

```swift
@MainActor
public protocol SkillPreferenceStoring: AnyObject {
    var skillSettings: SkillSettings { get }
    func saveSkillSettings(_ settings: SkillSettings)
}

public final class NoOpSkillPreferenceStore: SkillPreferenceStoring {
    public init() {}

    public var skillSettings: SkillSettings {
        .default
    }

    public func saveSkillSettings(_ settings: SkillSettings) {}
}
```

- [ ] **Step 4: Add native UserDefaults store**

Create `native/Sources/VocoApp/MacSkillPreferenceStore.swift`:

```swift
import Foundation
import VocoAppCore

@MainActor
final class MacSkillPreferenceStore: SkillPreferenceStoring {
    private enum Keys {
        static let settings = "skills.settings"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var skillSettings: SkillSettings {
        guard let data = defaults.data(forKey: Keys.settings),
              let settings = try? decoder.decode(SkillSettings.self, from: data)
        else {
            return .default
        }

        return settings
    }

    func saveSkillSettings(_ settings: SkillSettings) {
        do {
            let data = try encoder.encode(settings)
            defaults.set(data, forKey: Keys.settings)
        } catch {
            NSLog("Voco: Unable to save skill settings: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 5: Run focused tests and verify they pass**

Run:

```bash
swift test --package-path native --filter SkillPreferenceStore
```

Expected: store tests pass.

- [ ] **Step 6: Commit Task 2**

```bash
git add native/Sources/VocoAppCore/TranscriptPostProcessingModels.swift \
  native/Sources/VocoApp/MacSkillPreferenceStore.swift \
  native/Tests/VocoAppTests/MacSkillPreferenceStoreTests.swift \
  native/Tests/VocoAppCoreTests/TranscriptPostProcessingModelsTests.swift
git commit -m "Persist skills settings"
```

## Task 3: Wire Pipeline Into Recording Workflow

**Files:**
- Modify: `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`
- Test: `native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift`

- [ ] **Step 1: Add failing workflow test**

Append to `RecordingWorkflowTests`:

```swift
func testStopRecordingPostProcessesTranscriptBeforeInsertion() async throws {
    let audio = CapturedAudioSnapshot(
        durationSeconds: 1,
        sampleRate: 16_000,
        peakAmplitude: 0.1,
        pcm16Samples: [1, 2, 3]
    )
    let audioCapture = StubAudioCaptureProvider(audio: audio)
    let transcription = StaticTranscriptionProvider(
        transcript: TranscriptSnapshot(
            finalText: "嗯今天开始",
            partials: [],
            providerName: "TestProvider",
            latencyMilliseconds: 12
        )
    )
    let injection = CapturingTextInjectionProvider()
    let workflow = NativeRecordingWorkflow(
        audioCapture: audioCapture,
        transcription: transcription,
        textInjection: injection,
        postProcessingSettingsProvider: {
            SkillSettings(
                isEnabled: true,
                fillerCleanup: FillerCleanupSettings(
                    isEnabled: true,
                    rules: [
                        FillerCleanupRule(displayName: "删除嗯", matchText: "嗯", action: .delete, isEnabled: true, order: 0)
                    ]
                )
            )
        }
    )

    try await workflow.startRecording()
    let result = try await workflow.stopRecording()

    XCTAssertEqual(injection.insertedTexts, ["今天开始"])
    XCTAssertEqual(result.transcript.finalText, "嗯今天开始")
    XCTAssertEqual(result.postProcessing.originalText, "嗯今天开始")
    XCTAssertEqual(result.postProcessing.processedText, "今天开始")
}
```

Add these private helpers at the bottom of `RecordingWorkflowTests`:

```swift
@MainActor
private final class StubAudioCaptureProvider: AudioCaptureProviding {
    private let audio: CapturedAudioSnapshot

    init(audio: CapturedAudioSnapshot) {
        self.audio = audio
    }

    func startCapture() async throws {}

    func stopCapture() async throws -> CapturedAudioSnapshot {
        audio
    }
}

@MainActor
private final class CapturingTextInjectionProvider: TextInjectionProviding {
    private(set) var insertedTexts: [String] = []

    func insert(_ text: String) async throws -> TextInjectionSnapshot {
        insertedTexts.append(text)
        return .success(targetAppName: "Notes", strategy: .clipboardPaste)
    }
}
```

- [ ] **Step 2: Run focused test and verify it fails**

Run:

```bash
swift test --package-path native --filter RecordingWorkflowTests/testStopRecordingPostProcessesTranscriptBeforeInsertion
```

Expected: build fails because `NativeRecordingWorkflow` has no `postProcessingSettingsProvider` parameter and `RecordingWorkflowResult` has no `postProcessing`.

- [ ] **Step 3: Extend `RecordingWorkflowResult`**

Modify `RecordingWorkflowResult` in `RecordingWorkflowModels.swift`:

```swift
public struct RecordingWorkflowResult: Equatable, Sendable {
    public let audio: CapturedAudioSnapshot
    public let transcript: TranscriptSnapshot
    public let postProcessing: TranscriptPostProcessingResult
    public let injection: TextInjectionSnapshot

    public init(
        audio: CapturedAudioSnapshot,
        transcript: TranscriptSnapshot,
        postProcessing: TranscriptPostProcessingResult? = nil,
        injection: TextInjectionSnapshot
    ) {
        self.audio = audio
        self.transcript = transcript
        self.postProcessing = postProcessing ?? .unchanged(transcript.finalText)
        self.injection = injection
    }
}
```

- [ ] **Step 4: Add pipeline dependency to `NativeRecordingWorkflow`**

Modify `NativeRecordingWorkflow` stored properties and initializer:

```swift
private let postProcessingSettingsProvider: @MainActor () -> SkillSettings

public init(
    audioCapture: any AudioCaptureProviding,
    transcription: any TranscriptionProviding,
    textInjection: any TextInjectionProviding,
    postProcessingSettingsProvider: @escaping @MainActor () -> SkillSettings = { .default }
) {
    self.audioCapture = audioCapture
    self.transcription = transcription
    self.textInjection = textInjection
    self.postProcessingSettingsProvider = postProcessingSettingsProvider
}
```

- [ ] **Step 5: Process transcript before insertion**

Replace `insertionSnapshot(for:)` with:

```swift
private func insertionSnapshot(for processedText: String) async throws -> TextInjectionSnapshot {
    let trimmedText = processedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else {
        return .skippedEmpty
    }

    return try await textInjection.insert(processedText)
}
```

In both `stopRecording` branches, compute:

```swift
let postProcessing = TranscriptPostProcessingPipeline(settings: postProcessingSettingsProvider()).process(
    transcript.finalText,
    context: TranscriptPostProcessingContext(targetAppName: nil)
)
let insertion = try await insertionSnapshot(for: postProcessing.processedText)
return RecordingWorkflowResult(
    audio: audio,
    transcript: transcript,
    postProcessing: postProcessing,
    injection: insertion
)
```

For the silent/too-short branch, the unchanged empty transcript should flow through the same code path so `postProcessing` is `.unchanged("")`.

- [ ] **Step 6: Run focused workflow tests**

Run:

```bash
swift test --package-path native --filter RecordingWorkflowTests
```

Expected: all workflow tests pass.

- [ ] **Step 7: Commit Task 3**

```bash
git add native/Sources/VocoAppCore/RecordingWorkflowModels.swift \
  native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift
git commit -m "Run transcript post-processing before insertion"
```

## Task 4: Session Snapshot and SQLite Traceability

**Files:**
- Modify: `native/Sources/VocoAppCore/VoiceInputSessionModels.swift`
- Modify: `native/Sources/VocoApp/MacVoiceInputSessionStore.swift`
- Test: `native/Tests/VocoAppCoreTests/VoiceInputSessionModelsTests.swift`
- Test: `native/Tests/VocoAppTests/MacVoiceInputSessionStoreTests.swift`

- [ ] **Step 1: Add failing session model test**

Append to `VoiceInputSessionModelsTests`:

```swift
func testSessionSnapshotUsesProcessedTextAndKeepsRawTranscriptAndDiagnostics() {
    let result = RecordingWorkflowResult(
        audio: CapturedAudioSnapshot(durationSeconds: 2, sampleRate: 16_000, peakAmplitude: 0.2),
        transcript: TranscriptSnapshot(finalText: "嗯今天开始", partials: [], providerName: "TestProvider", latencyMilliseconds: 10),
        postProcessing: TranscriptPostProcessingResult(
            originalText: "嗯今天开始",
            processedText: "今天开始",
            diagnostics: [
                TranscriptPostProcessingDiagnostic(
                    skillID: FillerCleanupSkill.skillID,
                    ruleID: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                    ruleDisplayName: "删除嗯",
                    matchedText: "嗯",
                    replacementText: "",
                    matchCount: 1
                )
            ]
        ),
        injection: .success(targetAppName: "Notes", strategy: .clipboardPaste)
    )

    let session = VoiceInputSessionSnapshot(result: result)

    XCTAssertEqual(session.transcriptText, "今天开始")
    XCTAssertEqual(session.rawTranscriptText, "嗯今天开始")
    XCTAssertEqual(session.postProcessingDiagnostics.first?.ruleDisplayName, "删除嗯")
    XCTAssertEqual(session.wordCount, 4)
}
```

- [ ] **Step 2: Add failing SQLite round-trip test**

Append to `MacVoiceInputSessionStoreTests`:

```swift
func testSQLiteStorePersistsRawTranscriptAndPostProcessingDiagnostics() throws {
    let databaseURL = temporaryDatabaseURL()
    let store = try MacVoiceInputSessionStore(databaseURL: databaseURL)
    let session = VoiceInputSessionSnapshot(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
        transcriptText: "今天开始",
        rawTranscriptText: "嗯今天开始",
        postProcessingDiagnostics: [
            TranscriptPostProcessingDiagnostic(
                skillID: FillerCleanupSkill.skillID,
                ruleID: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
                ruleDisplayName: "删除嗯",
                matchedText: "嗯",
                replacementText: "",
                matchCount: 1
            )
        ],
        wordCount: 4,
        durationSeconds: 2,
        createdAt: Date(timeIntervalSince1970: 100),
        targetAppName: "Notes",
        providerName: "TestProvider"
    )

    try store.save(session)

    let loaded = try store.loadRecentSessions(limit: 10)
    XCTAssertEqual(loaded, [session])
}
```

Add this private helper to `MacVoiceInputSessionStoreTests`:

```swift
private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Voco-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("sessions.sqlite")
}
```

- [ ] **Step 3: Run focused tests and verify they fail**

Run:

```bash
swift test --package-path native --filter VoiceInputSessionModelsTests/testSessionSnapshotUsesProcessedTextAndKeepsRawTranscriptAndDiagnostics
swift test --package-path native --filter MacVoiceInputSessionStoreTests/testSQLiteStorePersistsRawTranscriptAndPostProcessingDiagnostics
```

Expected: build fails because `VoiceInputSessionSnapshot` does not have raw transcript and diagnostics fields.

- [ ] **Step 4: Extend `VoiceInputSessionSnapshot`**

Modify `VoiceInputSessionSnapshot`:

```swift
public struct VoiceInputSessionSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let transcriptText: String
    public let rawTranscriptText: String
    public let postProcessingDiagnostics: [TranscriptPostProcessingDiagnostic]
    public let wordCount: Int
    public let durationSeconds: Double
    public let createdAt: Date
    public let targetAppName: String?
    public let providerName: String

    public init(
        id: UUID = UUID(),
        transcriptText: String,
        rawTranscriptText: String? = nil,
        postProcessingDiagnostics: [TranscriptPostProcessingDiagnostic] = [],
        wordCount: Int,
        durationSeconds: Double,
        createdAt: Date = Date(),
        targetAppName: String?,
        providerName: String
    ) {
        self.id = id
        self.transcriptText = transcriptText
        self.rawTranscriptText = rawTranscriptText ?? transcriptText
        self.postProcessingDiagnostics = postProcessingDiagnostics
        self.wordCount = wordCount
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.targetAppName = targetAppName
        self.providerName = providerName
    }
}
```

Modify `init(result:)`:

```swift
let processedText = result.postProcessing.processedText.trimmingCharacters(in: .whitespacesAndNewlines)
self.init(
    id: id,
    transcriptText: processedText,
    rawTranscriptText: result.postProcessing.originalText,
    postProcessingDiagnostics: result.postProcessing.diagnostics,
    wordCount: processedText.count,
    durationSeconds: result.audio.durationSeconds,
    createdAt: createdAt,
    targetAppName: result.injection.targetAppName,
    providerName: result.transcript.providerName
)
```

- [ ] **Step 5: Add SQLite columns and JSON encoding**

In `MacVoiceInputSessionStore.migrate()`, after the existing `CREATE TABLE`, add:

```swift
try addColumnIfMissing(name: "raw_transcript_text", definition: "TEXT")
try addColumnIfMissing(name: "post_processing_diagnostics_json", definition: "TEXT NOT NULL DEFAULT '[]'")
try execute(
    """
    UPDATE voice_input_sessions
    SET raw_transcript_text = transcript_text
    WHERE raw_transcript_text IS NULL;
    """
)
```

Add helpers:

```swift
private func addColumnIfMissing(name: String, definition: String) throws {
    let existingColumns = try tableColumns(tableName: "voice_input_sessions")
    guard !existingColumns.contains(name) else {
        return
    }

    try execute("ALTER TABLE voice_input_sessions ADD COLUMN \(name) \(definition);")
}

private func tableColumns(tableName: String) throws -> Set<String> {
    let statement = try prepare("PRAGMA table_info(\(tableName));")
    defer { sqlite3_finalize(statement) }

    var columns = Set<String>()
    while sqlite3_step(statement) == SQLITE_ROW {
        if let name = columnText(statement, 1) {
            columns.insert(name)
        }
    }
    return columns
}

private func diagnosticsJSON(_ diagnostics: [TranscriptPostProcessingDiagnostic]) throws -> String {
    do {
        let data = try JSONEncoder().encode(diagnostics)
        return String(decoding: data, as: UTF8.self)
    } catch {
        throw VoiceInputSessionStoreError.saveFailed(message: error.localizedDescription)
    }
}

private func decodeDiagnostics(_ json: String?) throws -> [TranscriptPostProcessingDiagnostic] {
    guard let json, let data = json.data(using: .utf8) else {
        return []
    }
    do {
        return try JSONDecoder().decode([TranscriptPostProcessingDiagnostic].self, from: data)
    } catch {
        throw VoiceInputSessionStoreError.loadFailed(message: error.localizedDescription)
    }
}
```

Update `SELECT`, `INSERT`, bind indices, and `readSession` to include:

```swift
raw_transcript_text,
post_processing_diagnostics_json
```

When reading:

```swift
let rawTranscriptText = columnText(statement, 7) ?? transcriptText
let diagnostics = try decodeDiagnostics(columnText(statement, 8))
return VoiceInputSessionSnapshot(
    id: id,
    transcriptText: transcriptText,
    rawTranscriptText: rawTranscriptText,
    postProcessingDiagnostics: diagnostics,
    wordCount: Int(sqlite3_column_int64(statement, 2)),
    durationSeconds: sqlite3_column_double(statement, 3),
    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
    targetAppName: targetAppName,
    providerName: providerName
)
```

- [ ] **Step 6: Run focused session tests**

Run:

```bash
swift test --package-path native --filter VoiceInputSessionModelsTests
swift test --package-path native --filter MacVoiceInputSessionStoreTests
```

Expected: both suites pass.

- [ ] **Step 7: Commit Task 4**

```bash
git add native/Sources/VocoAppCore/VoiceInputSessionModels.swift \
  native/Sources/VocoApp/MacVoiceInputSessionStore.swift \
  native/Tests/VocoAppCoreTests/VoiceInputSessionModelsTests.swift \
  native/Tests/VocoAppTests/MacVoiceInputSessionStoreTests.swift
git commit -m "Persist processed transcript diagnostics"
```

## Task 5: Coordinator Skills State and Actions

**Files:**
- Create: `native/Sources/VocoAppCore/SkillSettingsModels.swift`
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Test: `native/Tests/VocoAppCoreTests/SkillSettingsModelsTests.swift`
- Test: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Add failing snapshot/action tests**

Create `native/Tests/VocoAppCoreTests/SkillSettingsModelsTests.swift`:

```swift
import XCTest
@testable import VocoAppCore

final class SkillSettingsModelsTests: XCTestCase {
    func testSkillSettingsSnapshotUsesEnglishCopyAndPreview() {
        let settings = SkillSettings(
            isEnabled: true,
            fillerCleanup: FillerCleanupSettings(
                isEnabled: true,
                rules: [FillerCleanupRule(displayName: "删除嗯", matchText: "嗯", action: .delete, isEnabled: true, order: 0)]
            )
        )
        let snapshot = SkillSettingsSnapshot(
            settings: settings,
            previewInput: "嗯hello",
            strings: VocoStrings(language: .en)
        )

        XCTAssertEqual(snapshot.title, "Skills")
        XCTAssertEqual(snapshot.fillerCleanupTitle, "Filler Cleanup")
        XCTAssertEqual(snapshot.preview.originalText, "嗯hello")
        XCTAssertEqual(snapshot.preview.processedText, "hello")
        XCTAssertEqual(snapshot.preview.matchedRuleTitles, ["删除嗯"])
    }
}
```

Append to `AppCoordinatorTests`:

```swift
func testCoordinatorLoadsAndPersistsSkillSettings() {
    let store = FakeSkillPreferenceStore(
        skillSettings: SkillSettings(
            isEnabled: true,
            fillerCleanup: FillerCleanupSettings(isEnabled: false, rules: [])
        )
    )
    let coordinator = AppCoordinator(skillPreferenceStore: store)

    XCTAssertFalse(coordinator.skillSettings.fillerCleanup.isEnabled)

    var updated = coordinator.skillSettings
    updated.fillerCleanup.isEnabled = true
    coordinator.saveSkillSettings(updated)

    XCTAssertTrue(coordinator.skillSettings.fillerCleanup.isEnabled)
    XCTAssertEqual(store.savedSkillSettings.last, updated)
}
```

Add test helper:

```swift
@MainActor
private final class FakeSkillPreferenceStore: SkillPreferenceStoring {
    private(set) var skillSettings: SkillSettings
    private(set) var savedSkillSettings: [SkillSettings] = []

    init(skillSettings: SkillSettings = .default) {
        self.skillSettings = skillSettings
    }

    func saveSkillSettings(_ settings: SkillSettings) {
        skillSettings = settings
        savedSkillSettings.append(settings)
    }
}
```

- [ ] **Step 2: Run focused tests and verify they fail**

Run:

```bash
swift test --package-path native --filter SkillSettingsModelsTests
swift test --package-path native --filter AppCoordinatorTests/testCoordinatorLoadsAndPersistsSkillSettings
```

Expected: build fails because `SkillSettingsSnapshot`, `skillPreferenceStore`, and coordinator skill actions do not exist.

- [ ] **Step 3: Add Skills snapshot models**

Create `native/Sources/VocoAppCore/SkillSettingsModels.swift`:

```swift
import Foundation

public struct SkillPreviewSnapshot: Equatable, Sendable {
    public let originalText: String
    public let processedText: String
    public let matchedRuleTitles: [String]

    public init(result: TranscriptPostProcessingResult) {
        self.originalText = result.originalText
        self.processedText = result.processedText
        self.matchedRuleTitles = result.diagnostics.map(\.ruleDisplayName)
    }
}

public struct SkillSettingsSnapshot: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let isEnabled: Bool
    public let fillerCleanupTitle: String
    public let fillerCleanupDetail: String
    public let isFillerCleanupEnabled: Bool
    public let rules: [FillerCleanupRule]
    public let preview: SkillPreviewSnapshot

    public init(
        settings: SkillSettings,
        previewInput: String,
        strings: VocoStrings = VocoStrings()
    ) {
        let result = TranscriptPostProcessingPipeline(settings: settings).process(
            previewInput,
            context: TranscriptPostProcessingContext(targetAppName: nil)
        )
        self.title = strings.skills.title
        self.detail = strings.skills.detail
        self.isEnabled = settings.isEnabled
        self.fillerCleanupTitle = strings.skills.fillerCleanupTitle
        self.fillerCleanupDetail = strings.skills.fillerCleanupDetail
        self.isFillerCleanupEnabled = settings.fillerCleanup.isEnabled
        self.rules = settings.fillerCleanup.rules.sorted { $0.order < $1.order }
        self.preview = SkillPreviewSnapshot(result: result)
    }
}
```

- [ ] **Step 4: Add coordinator state and actions**

In `AppCoordinator`, add published state:

```swift
@Published public private(set) var skillSettings: SkillSettings
```

Add private dependency:

```swift
private let skillPreferenceStore: any SkillPreferenceStoring
```

Update initializer signature:

```swift
skillPreferenceStore: any SkillPreferenceStoring = NoOpSkillPreferenceStore(),
```

Load and assign:

```swift
let initialSkillSettings = skillPreferenceStore.skillSettings
self.skillPreferenceStore = skillPreferenceStore
self.skillSettings = initialSkillSettings
```

Add snapshot and action:

```swift
public func skillSettingsSnapshot(previewInput: String) -> SkillSettingsSnapshot {
    SkillSettingsSnapshot(settings: skillSettings, previewInput: previewInput, strings: strings)
}

public func saveSkillSettings(_ settings: SkillSettings) {
    skillSettings = settings
    skillPreferenceStore.saveSkillSettings(settings)
}
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
swift test --package-path native --filter SkillSettingsModelsTests
swift test --package-path native --filter AppCoordinatorTests/testCoordinatorLoadsAndPersistsSkillSettings
```

Expected: both tests pass.

- [ ] **Step 6: Commit Task 5**

```bash
git add native/Sources/VocoAppCore/SkillSettingsModels.swift \
  native/Sources/VocoAppCore/AppCoordinator.swift \
  native/Tests/VocoAppCoreTests/SkillSettingsModelsTests.swift \
  native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift
git commit -m "Expose skills settings state"
```

## Task 6: Localized Skills Navigation and Copy

**Files:**
- Modify: `native/Sources/VocoAppCore/SettingsWorkbenchModels.swift`
- Modify: `native/Sources/VocoAppCore/VocoStrings.swift`
- Modify: `native/Sources/VocoApp/SettingsView.swift`
- Test: `native/Tests/VocoAppCoreTests/SettingsWorkbenchModelsTests.swift`
- Test: `native/Tests/VocoAppCoreTests/SkillSettingsModelsTests.swift`

- [ ] **Step 1: Add failing localization/navigation tests**

Append to `SettingsWorkbenchModelsTests`:

```swift
func testWorkbenchSectionsIncludeSkillsInApprovedOrder() {
    XCTAssertEqual(SettingsWorkbenchSection.allCases, [.overview, .model, .skills, .statistics, .settings])
}

func testSkillsSectionUsesEnglishCopy() {
    let strings = VocoStrings(language: .en)
    XCTAssertEqual(SettingsWorkbenchSection.skills.title(strings: strings), "Skills")
    XCTAssertEqual(SettingsWorkbenchSection.skills.summary(strings: strings), "Transcript cleanup and actions")
}
```

Append to `SkillSettingsModelsTests`:

```swift
func testSkillSettingsSnapshotUsesChineseCopyByDefault() {
    let snapshot = SkillSettingsSnapshot(settings: .default, previewInput: "嗯测试")
    XCTAssertEqual(snapshot.title, "技能")
    XCTAssertEqual(snapshot.fillerCleanupTitle, "语气词清理")
}
```

- [ ] **Step 2: Run focused tests and verify they fail**

Run:

```bash
swift test --package-path native --filter SettingsWorkbenchModelsTests/testWorkbenchSectionsIncludeSkillsInApprovedOrder
swift test --package-path native --filter SkillSettingsModelsTests/testSkillSettingsSnapshotUsesChineseCopyByDefault
```

Expected: first test fails because `.skills` does not exist; second fails until `VocoStrings.skills` exists.

- [ ] **Step 3: Add `.skills` workbench section**

Modify `SettingsWorkbenchSection`:

```swift
public enum SettingsWorkbenchSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case model
    case skills
    case statistics
    case settings
}
```

Add to `title(strings:)`:

```swift
case .skills:
    strings.language == .zhHans ? "技能" : "Skills"
```

Add to `summary(strings:)`:

```swift
case .skills:
    strings.language == .zhHans ? "转写清理和动作" : "Transcript cleanup and actions"
```

Where section statuses are built in `SettingsWorkbenchSnapshot.make`, set:

```swift
.skills: .neutral
```

- [ ] **Step 4: Add skills strings**

In `VocoStrings`, add:

```swift
public var skills: SkillStrings { SkillStrings(language: language) }
```

Add near other string structs:

```swift
public struct SkillStrings {
    let language: AppLanguage

    public var title: String { language == .zhHans ? "技能" : "Skills" }
    public var detail: String { language == .zhHans ? "清理和调整转写文本，再插入到目标 App。" : "Clean and adjust transcripts before inserting them into the target app." }
    public var enabledTitle: String { language == .zhHans ? "启用技能" : "Enable Skills" }
    public var fillerCleanupTitle: String { language == .zhHans ? "语气词清理" : "Filler Cleanup" }
    public var fillerCleanupDetail: String { language == .zhHans ? "删除或替换常见口语填充词。" : "Delete or replace common spoken filler words." }
    public var rulesTitle: String { language == .zhHans ? "规则" : "Rules" }
    public var previewTitle: String { language == .zhHans ? "测试预览" : "Preview" }
    public var originalTextTitle: String { language == .zhHans ? "原文" : "Original" }
    public var processedTextTitle: String { language == .zhHans ? "处理后" : "Processed" }
    public var matchedRulesTitle: String { language == .zhHans ? "命中规则" : "Matched Rules" }
    public var noMatchedRulesTitle: String { language == .zhHans ? "没有命中规则" : "No matched rules" }
    public var addRuleButton: String { language == .zhHans ? "新增规则" : "Add Rule" }
    public var deleteActionTitle: String { language == .zhHans ? "删除" : "Delete" }
    public var replaceActionTitle: String { language == .zhHans ? "替换" : "Replace" }
    public var replacementEmptyTitle: String { language == .zhHans ? "空字符串" : "Empty String" }
    public var replacementSpaceTitle: String { language == .zhHans ? "空格" : "Space" }
}
```

- [ ] **Step 5: Add sidebar icon mapping**

In `SettingsView.swift`, update `SettingsWorkbenchSection.sidebarSystemImage`:

```swift
case .skills:
    "wand.and.stars"
```

Update `detailContent(for:)` with a temporary placeholder until Task 7:

```swift
case .skills:
    Text(strings.skills.title)
```

- [ ] **Step 6: Run focused tests**

Run:

```bash
swift test --package-path native --filter SettingsWorkbenchModelsTests
swift test --package-path native --filter SkillSettingsModelsTests
```

Expected: tests pass.

- [ ] **Step 7: Commit Task 6**

```bash
git add native/Sources/VocoAppCore/SettingsWorkbenchModels.swift \
  native/Sources/VocoAppCore/VocoStrings.swift \
  native/Sources/VocoApp/SettingsView.swift \
  native/Tests/VocoAppCoreTests/SettingsWorkbenchModelsTests.swift \
  native/Tests/VocoAppCoreTests/SkillSettingsModelsTests.swift
git commit -m "Add skills navigation copy"
```

## Task 7: Skills Settings UI

**Files:**
- Create: `native/Sources/VocoApp/SettingsSkillsView.swift`
- Modify: `native/Sources/VocoApp/SettingsView.swift`
- Test: `native/Tests/VocoAppTests/SettingsSkillsViewTests.swift`

- [ ] **Step 1: Add minimal UI policy tests**

Create `native/Tests/VocoAppTests/SettingsSkillsViewTests.swift`:

```swift
import XCTest
@testable import VocoApp
@testable import VocoAppCore

final class SettingsSkillsViewTests: XCTestCase {
    func testReplacementPresetTitlesAreLocalized() {
        XCTAssertEqual(FillerCleanupReplacementPreset.empty.title(strings: VocoStrings(language: .zhHans)), "空字符串")
        XCTAssertEqual(FillerCleanupReplacementPreset.space.title(strings: VocoStrings(language: .en)), "Space")
        XCTAssertEqual(FillerCleanupReplacementPreset.custom.title(strings: VocoStrings(language: .en)), "Custom")
    }

    func testReplacementPresetMapsToReplacementText() {
        XCTAssertEqual(FillerCleanupReplacementPreset.empty.replacementText(customText: "x"), "")
        XCTAssertEqual(FillerCleanupReplacementPreset.space.replacementText(customText: "x"), " ")
        XCTAssertEqual(FillerCleanupReplacementPreset.custom.replacementText(customText: "x"), "x")
    }
}
```

- [ ] **Step 2: Run focused tests and verify they fail**

Run:

```bash
swift test --package-path native --filter SettingsSkillsViewTests
```

Expected: build fails because `FillerCleanupReplacementPreset` does not exist.

- [ ] **Step 3: Expose shared workbench styling for split view files**

In `SettingsView.swift`, change:

```swift
private enum SettingsWorkbenchVisual {
```

to:

```swift
enum SettingsWorkbenchVisual {
```

Change:

```swift
private struct SettingsWorkbenchSecondaryButtonStyle: ButtonStyle {
```

to:

```swift
struct SettingsWorkbenchSecondaryButtonStyle: ButtonStyle {
```

This keeps the new Skills page visually consistent while allowing it to live outside the oversized `SettingsView.swift`.

- [ ] **Step 4: Create Skills view with replacement preset helper**

Create `native/Sources/VocoApp/SettingsSkillsView.swift`:

```swift
import SwiftUI
import VocoAppCore

enum FillerCleanupReplacementPreset: String, CaseIterable, Identifiable {
    case empty
    case space
    case custom

    var id: String { rawValue }

    func title(strings: VocoStrings) -> String {
        switch self {
        case .empty:
            strings.skills.replacementEmptyTitle
        case .space:
            strings.skills.replacementSpaceTitle
        case .custom:
            strings.language == .zhHans ? "自定义" : "Custom"
        }
    }

    func replacementText(customText: String) -> String {
        switch self {
        case .empty:
            ""
        case .space:
            " "
        case .custom:
            customText
        }
    }
}

struct SettingsSkillsView: View {
    @ObservedObject var coordinator: AppCoordinator
    let strings: VocoStrings

    @State private var previewInput = "嗯今天我们开始测试"
    @State private var draftCustomReplacement = ""
    @State private var replacementPreset: FillerCleanupReplacementPreset = .empty

    private var snapshot: SkillSettingsSnapshot {
        coordinator.skillSettingsSnapshot(previewInput: previewInput)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSkillsHeader(snapshot: snapshot, strings: strings)
            SettingsSkillsFillerPanel(
                coordinator: coordinator,
                snapshot: snapshot,
                strings: strings,
                previewInput: $previewInput,
                replacementPreset: $replacementPreset,
                draftCustomReplacement: $draftCustomReplacement
            )
        }
    }
}
```

Add subviews in the same file for the first implementation pass:

```swift
private struct SettingsSkillsHeader: View {
    let snapshot: SkillSettingsSnapshot
    let strings: VocoStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SKILLS")
                .font(SettingsWorkbenchVisual.eyebrowFont)
                .foregroundStyle(SettingsWorkbenchVisual.tertiaryText)
            Text(snapshot.title)
                .font(SettingsWorkbenchVisual.pageTitleFont)
                .foregroundStyle(SettingsWorkbenchVisual.primaryText)
            Text(snapshot.detail)
                .font(SettingsWorkbenchVisual.bodyFont)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
        }
    }
}

private struct SettingsSkillsFillerPanel: View {
    @ObservedObject var coordinator: AppCoordinator
    let snapshot: SkillSettingsSnapshot
    let strings: VocoStrings
    @Binding var previewInput: String
    @Binding var replacementPreset: FillerCleanupReplacementPreset
    @Binding var draftCustomReplacement: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(snapshot.fillerCleanupTitle, isOn: fillerEnabledBinding)
            Text(snapshot.fillerCleanupDetail)
                .font(SettingsWorkbenchVisual.captionFont)
                .foregroundStyle(SettingsWorkbenchVisual.secondaryText)

            ForEach(snapshot.rules) { rule in
                HStack {
                    Text(rule.displayName)
                    Spacer()
                    Text(rule.matchText)
                    Text(actionTitle(rule.action))
                }
                .font(SettingsWorkbenchVisual.captionFont)
                .padding(10)
                .background(SettingsWorkbenchVisual.smallCardBackground, in: RoundedRectangle(cornerRadius: 8))
            }

            Button {
                addRule()
            } label: {
                Label(strings.skills.addRuleButton, systemImage: "plus")
            }
            .buttonStyle(SettingsWorkbenchSecondaryButtonStyle())

            VStack(alignment: .leading, spacing: 8) {
                Text(strings.skills.previewTitle)
                    .font(SettingsWorkbenchVisual.controlFont)
                TextEditor(text: $previewInput)
                    .frame(minHeight: 72)
                Text(strings.skills.processedTextTitle)
                    .font(SettingsWorkbenchVisual.captionSemiboldFont)
                Text(snapshot.preview.processedText.isEmpty ? "--" : snapshot.preview.processedText)
                    .font(SettingsWorkbenchVisual.bodyFont)
                Text(snapshot.preview.matchedRuleTitles.isEmpty ? strings.skills.noMatchedRulesTitle : snapshot.preview.matchedRuleTitles.joined(separator: ", "))
                    .font(SettingsWorkbenchVisual.captionFont)
                    .foregroundStyle(SettingsWorkbenchVisual.secondaryText)
            }
        }
        .padding(18)
        .background(SettingsWorkbenchVisual.panelBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SettingsWorkbenchVisual.subtleBorder))
    }

    private var fillerEnabledBinding: Binding<Bool> {
        Binding(
            get: { coordinator.skillSettings.fillerCleanup.isEnabled },
            set: { enabled in
                var settings = coordinator.skillSettings
                settings.fillerCleanup.isEnabled = enabled
                coordinator.saveSkillSettings(settings)
            }
        )
    }

    private func actionTitle(_ action: FillerCleanupAction) -> String {
        switch action {
        case .delete:
            strings.skills.deleteActionTitle
        case .replace:
            strings.skills.replaceActionTitle
        }
    }

    private func addRule() {
        var settings = coordinator.skillSettings
        let nextOrder = (settings.fillerCleanup.rules.map(\.order).max() ?? -1) + 1
        let replacement = replacementPreset.replacementText(customText: draftCustomReplacement)
        settings.fillerCleanup.rules.append(
            FillerCleanupRule(
                displayName: previewInput,
                matchText: previewInput,
                action: replacement.isEmpty ? .delete : .replace(replacement),
                isEnabled: true,
                order: nextOrder
            )
        )
        coordinator.saveSkillSettings(settings)
    }
}
```

- [ ] **Step 5: Route settings workbench to Skills view**

In `SettingsView.detailContent(for:)`, replace the Task 6 placeholder with:

```swift
case .skills:
    SettingsSkillsView(coordinator: coordinator, strings: strings)
```

- [ ] **Step 6: Run UI helper tests and build**

Run:

```bash
swift test --package-path native --filter SettingsSkillsViewTests
swift build --package-path native
```

Expected: tests pass and build succeeds.

- [ ] **Step 7: Commit Task 7**

```bash
git add native/Sources/VocoApp/SettingsSkillsView.swift \
  native/Sources/VocoApp/SettingsView.swift \
  native/Tests/VocoAppTests/SettingsSkillsViewTests.swift
git commit -m "Add skills settings page"
```

## Task 8: Inject Skill Store Into App and Workflow

**Files:**
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift`
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Test: `native/Tests/VocoAppTests/VocoNativeAppTests.swift`

- [ ] **Step 1: Add app composition test**

Append this test to `VocoNativeAppTests`:

```swift
func testNativeAppDependenciesIncludeSkillPreferenceStore() {
    let dependencies = VocoNativeAppDependencies.make()

    XCTAssertNotNil(dependencies.skillPreferenceStore as? MacSkillPreferenceStore)
}
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
swift test --package-path native --filter VocoNativeAppTests/testNativeAppDependenciesIncludeSkillPreferenceStore
```

Expected: build fails because `VocoNativeAppDependencies` does not exist.

- [ ] **Step 3: Add dependency composition helper and inject stores**

In `VocoNativeApp.swift`, add:

```swift
@MainActor
struct VocoNativeAppDependencies {
    let coordinator: AppCoordinator
    let skillPreferenceStore: any SkillPreferenceStoring
    let displayInDockEnabled: Bool

    static func make() -> VocoNativeAppDependencies {
        let permissionProvider = MacPermissionProvider()
        let credentialStore = MacKeychainCredentialStore()
        let voiceInputPreferences = MacVoiceInputPreferenceStore()
        let appPreferences = MacAppPreferenceStore()
        let skillPreferenceStore = MacSkillPreferenceStore()
        let voiceInputSessionStore = MacVoiceInputSessionStore.makeDefault()
        let transcriptionProvider = MacVolcengineTranscriptionProvider(credentialStore: credentialStore)
        let audioCapture = MacAudioCaptureEngine()
        if let audioInputDevice = voiceInputPreferences.audioInputDevice {
            audioCapture.setInputDevice(audioInputDevice)
        }
        let recordingWorkflow = NativeRecordingWorkflow(
            audioCapture: audioCapture,
            transcription: transcriptionProvider,
            textInjection: MacTextInjectionProvider(),
            postProcessingSettingsProvider: {
                skillPreferenceStore.skillSettings
            }
        )
        let coordinator = AppCoordinator(
            permissionProvider: permissionProvider,
            launchAtLoginProvider: MacLaunchAtLoginProvider(),
            transcriptionCredentialStore: credentialStore,
            recordingWorkflow: recordingWorkflow,
            hotkeyProvider: MacHotkeyProvider(),
            installLocationProvider: MacInstallLocationProvider(),
            legacyInstallProvider: MacLegacyInstallProvider(),
            voiceInputPreferenceStore: voiceInputPreferences,
            appPreferenceStore: appPreferences,
            skillPreferenceStore: skillPreferenceStore,
            voiceInputSessionStore: voiceInputSessionStore,
            hotkeyBinding: voiceInputPreferences.hotkeyPreset?.binding ?? .default,
            hotkeyMode: voiceInputPreferences.hotkeyMode ?? .toggle
        )
        return VocoNativeAppDependencies(
            coordinator: coordinator,
            skillPreferenceStore: skillPreferenceStore,
            displayInDockEnabled: appPreferences.displayInDockEnabled
        )
    }
}
```

Then update the app initializer to use:

```swift
SettingsWorkbenchFontRegistrar.registerBundledFonts()
let dependencies = VocoNativeAppDependencies.make()
MacDockPresentationController.apply(displayInDockEnabled: dependencies.displayInDockEnabled)
dependencies.coordinator.finishLaunching()
HUDOverlayPresenter.shared.attach(coordinator: dependencies.coordinator)
_coordinator = StateObject(wrappedValue: dependencies.coordinator)
appDelegate.coordinator = dependencies.coordinator
appDelegate.coordinatorDidBecomeAvailable()
```

- [ ] **Step 4: Add a focused test for live settings reads**

Append to `RecordingWorkflowTests`:

```swift
func testWorkflowReadsLatestPostProcessingSettingsOnStop() async throws {
    var settings = SkillSettings(
        isEnabled: true,
        fillerCleanup: FillerCleanupSettings(isEnabled: false, rules: [])
    )
    let audio = CapturedAudioSnapshot(durationSeconds: 1, sampleRate: 16_000, peakAmplitude: 0.1, pcm16Samples: [1])
    let injection = CapturingTextInjectionProvider()
    let workflow = NativeRecordingWorkflow(
        audioCapture: StubAudioCaptureProvider(audio: audio),
        transcription: StaticTranscriptionProvider(
            transcript: TranscriptSnapshot(finalText: "嗯今天", partials: [], providerName: "TestProvider", latencyMilliseconds: nil)
        ),
        textInjection: injection,
        postProcessingSettingsProvider: { settings }
    )

    settings.fillerCleanup = FillerCleanupSettings(
        isEnabled: true,
        rules: [FillerCleanupRule(displayName: "删除嗯", matchText: "嗯", action: .delete, isEnabled: true, order: 0)]
    )

    try await workflow.startRecording()
    _ = try await workflow.stopRecording()

    XCTAssertEqual(injection.insertedTexts, ["今天"])
}
```

Run:

```bash
swift test --package-path native --filter RecordingWorkflowTests/testWorkflowReadsLatestPostProcessingSettingsOnStop
```

Expected: test passes because `NativeRecordingWorkflow` calls `postProcessingSettingsProvider()` inside `stopRecording`.

- [ ] **Step 5: Run composition test**

Run:

```bash
swift test --package-path native --filter VocoNativeAppTests
```

Expected: app tests pass.

- [ ] **Step 6: Commit Task 8**

```bash
git add native/Sources/VocoApp/VocoNativeApp.swift \
  native/Sources/VocoAppCore/AppCoordinator.swift \
  native/Tests/VocoAppTests/VocoNativeAppTests.swift
git commit -m "Inject skills settings into native app"
```

## Task 9: Session Detail UI Traceability

**Files:**
- Modify: `native/Sources/VocoApp/SettingsView.swift`
- Test: `native/Tests/VocoAppTests/VoiceInputSessionDetailSheetTests.swift`

- [ ] **Step 1: Add detail policy tests**

Create `native/Tests/VocoAppTests/VoiceInputSessionDetailSheetTests.swift`:

```swift
import XCTest
@testable import VocoApp
@testable import VocoAppCore

final class VoiceInputSessionDetailSheetTests: XCTestCase {
    func testSessionDetailSummaryShowsProcessedRawAndMatchedRules() {
        let session = VoiceInputSessionSnapshot(
            transcriptText: "今天开始",
            rawTranscriptText: "嗯今天开始",
            postProcessingDiagnostics: [
                TranscriptPostProcessingDiagnostic(
                    skillID: FillerCleanupSkill.skillID,
                    ruleID: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
                    ruleDisplayName: "删除嗯",
                    matchedText: "嗯",
                    replacementText: "",
                    matchCount: 1
                )
            ],
            wordCount: 4,
            durationSeconds: 2,
            targetAppName: "Notes",
            providerName: "TestProvider"
        )

        let summary = VoiceInputSessionDetailSummary(session: session, strings: VocoStrings(language: .zhHans))

        XCTAssertEqual(summary.processedTextTitle, "处理后")
        XCTAssertEqual(summary.processedText, "今天开始")
        XCTAssertEqual(summary.rawTextTitle, "原始转写")
        XCTAssertEqual(summary.rawText, "嗯今天开始")
        XCTAssertEqual(summary.matchedRulesTitle, "命中规则")
        XCTAssertEqual(summary.matchedRules, ["删除嗯：嗯 -> 空字符串 x1"])
    }
}
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
swift test --package-path native --filter VoiceInputSessionDetailSheetTests
```

Expected: build fails because `VoiceInputSessionDetailSummary` does not exist.

- [ ] **Step 3: Add summary model near the sheet**

In `SettingsView.swift`, near `VoiceInputSessionDetailSheet`, add:

```swift
struct VoiceInputSessionDetailSummary: Equatable {
    let processedTextTitle: String
    let processedText: String
    let rawTextTitle: String
    let rawText: String
    let matchedRulesTitle: String
    let matchedRules: [String]

    init(session: VoiceInputSessionSnapshot, strings: VocoStrings) {
        self.processedTextTitle = strings.skills.processedTextTitle
        self.processedText = session.transcriptText
        self.rawTextTitle = strings.language == .zhHans ? "原始转写" : "Raw Transcript"
        self.rawText = session.rawTranscriptText
        self.matchedRulesTitle = strings.skills.matchedRulesTitle
        self.matchedRules = session.postProcessingDiagnostics.map { diagnostic in
            let replacement = diagnostic.replacementText.isEmpty
                ? strings.skills.replacementEmptyTitle
                : diagnostic.replacementText
            return "\(diagnostic.ruleDisplayName)：\(diagnostic.matchedText) -> \(replacement) x\(diagnostic.matchCount)"
        }
    }
}
```

Update `VoiceInputSessionDetailSheet` to render processed text first, then raw transcript and matched rules when diagnostics are present.

- [ ] **Step 4: Run focused test**

Run:

```bash
swift test --package-path native --filter VoiceInputSessionDetailSheetTests
```

Expected: test passes.

- [ ] **Step 5: Commit Task 9**

```bash
git add native/Sources/VocoApp/SettingsView.swift \
  native/Tests/VocoAppTests/VoiceInputSessionDetailSheetTests.swift
git commit -m "Show skill traceability in session details"
```

## Task 10: Full Verification and Bundle Smoke

**Files:**
- No new files expected.

- [ ] **Step 1: Run full XCTest**

Run:

```bash
swift test --package-path native
```

Expected: all tests pass; the live Volcengine smoke test may remain skipped unless `VOCO_LIVE_VOLCENGINE_ASR=1` is explicitly set.

- [ ] **Step 2: Build native debug app bundle**

Run:

```bash
packaging/build_native_app_bundle.sh --profile debug
```

Expected: `target/native/Voco.app` is built and verified.

- [ ] **Step 3: Run bundle smoke**

Run:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Expected: bundle smoke passes.

- [ ] **Step 4: Check whitespace and final status**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` has no output. `git status --short` shows only intended tracked changes if the final commit has not been made.

- [ ] **Step 5: Confirm all implementation changes are committed**

```bash
git status --short
```

Expected: no tracked implementation changes remain. Untracked local planning files may remain only if they existed before this execution and were deliberately left out.
