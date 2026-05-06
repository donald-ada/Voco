# Voco Native Doubao ASR Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the native Doubao ASR provider foundation and streaming transcript path so Keychain credentials drive a real provider, provider failures are typed and visible, and partial transcripts can reach `AppCoordinator` and the HUD.

**Architecture:** Keep streaming transcript models, request/auth builders, server response parsing, and error mapping in `VocoAppCore` so behavior is testable without live network credentials. Keep the macOS provider in `VocoApp` as the bridge from `TranscriptionCredentialStoring` to an injectable Doubao transport. The default transport performs the WebSocket upgrade with official Doubao headers and fails loudly for the remaining native wire-protocol gap instead of returning fake success.

**Tech Stack:** Swift 6, XCTest, Foundation `URLSessionWebSocketTask`, macOS Keychain through the existing `TranscriptionCredentialStoring`, existing `NativeRecordingWorkflow`, `AppCoordinator`, and `HUDSnapshot`.

---

## Source Notes

- Official Doubao large-model streaming ASR docs: `https://www.volcengine.com/docs/6561/1354869?lang=zh`.
- Official Doubao classic streaming ASR docs: `https://www.volcengine.com/docs/6561/80818?lang=zh`.
- In this environment both official pages render as a JavaScript shell, while the official search index confirms the large-model endpoint family, WebSocket usage, and headers such as `X-Api-App-Key` and `X-Api-Resource-Id`.
- Existing Rust implementation under `crates/voco-asr/src/doubao/` already documents and tests the binary frame protocol, auth headers, default endpoint, resource ID, response parsing, and server error code mapping. Native Swift must not pretend the live binary protocol is complete unless the Swift transport actually receives and parses a final server result.

## File Structure

- Create `native/Sources/VocoApp/MacDoubaoTranscriptionProvider.swift`
  - Reads Doubao API key from `TranscriptionCredentialStoring`.
  - Builds a sanitized `DoubaoTranscriptionRequest`.
  - Delegates network work to an injectable `DoubaoTranscriptionTransporting`.
  - Maps missing credentials and credential read errors to user-visible provider errors.
- Modify `native/Sources/VocoAppCore/TranscriptionModels.swift`
  - Adds `TranscriptPartialSnapshot`, `TranscriptionProgressHandler`, Doubao request/auth/config structs, response parser, server error mapper, and transport protocol.
- Modify `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`
  - Adds streaming callbacks to `TranscriptionProviding` and `RecordingWorkflowing`.
  - Keeps the old no-progress call shape through convenience extensions.
  - Keeps `UnavailableTranscriptionProvider` available for tests.
- Modify `native/Sources/VocoAppCore/AppCoordinator.swift`
  - Stores streaming partials in `lastTranscript` while status is `.transcribing`.
  - Keeps `hudSnapshot` using `TranscriptSnapshot.partials.last` through existing HUD preview logic.
- Modify `native/Sources/VocoApp/VocoNativeApp.swift`
  - Wires `MacDoubaoTranscriptionProvider(credentialStore:)` instead of hard-coded `UnavailableTranscriptionProvider()`.
- Modify `native/Tests/VocoAppCoreTests/TranscriptionModelsTests.swift`
  - Covers partial snapshot behavior, Doubao auth request construction, redaction, response parsing, and server error mapping.
- Modify `native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift`
  - Covers progress callback forwarding from workflow to transcription provider.
- Modify `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`
  - Covers partial transcript state entering `AppCoordinator` and `HUDSnapshot`.
- Modify this plan with verification notes after full verification.

## Task 1: Transcript Streaming Core Models

**Files:**
- Modify: `native/Sources/VocoAppCore/TranscriptionModels.swift`
- Modify: `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`
- Modify: `native/Tests/VocoAppCoreTests/TranscriptionModelsTests.swift`

- [ ] **Step 1: Write failing partial model tests**

Add tests to `native/Tests/VocoAppCoreTests/TranscriptionModelsTests.swift`:

```swift
func testTranscriptSnapshotAppendsNonEmptyPartials() {
    let base = TranscriptSnapshot(
        finalText: "",
        partials: [],
        providerName: "Doubao",
        latencyMilliseconds: nil
    )

    let updated = base.appendingPartial(
        TranscriptPartialSnapshot(text: "你好", stablePrefixLength: 0, providerName: "Doubao")
    )

    XCTAssertEqual(updated.finalText, "")
    XCTAssertEqual(updated.partials, ["你好"])
    XCTAssertEqual(updated.providerName, "Doubao")
}

func testTranscriptSnapshotIgnoresBlankPartials() {
    let base = TranscriptSnapshot(
        finalText: "",
        partials: ["你好"],
        providerName: "Doubao",
        latencyMilliseconds: nil
    )

    let updated = base.appendingPartial(
        TranscriptPartialSnapshot(text: " \n ", stablePrefixLength: 0, providerName: "Doubao")
    )

    XCTAssertEqual(updated.partials, ["你好"])
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter TranscriptionModelsTests/testTranscriptSnapshot
```

Expected: compile failure because `TranscriptPartialSnapshot` and `TranscriptSnapshot.appendingPartial` do not exist.

- [ ] **Step 3: Implement minimal streaming models**

Update `native/Sources/VocoAppCore/TranscriptionModels.swift`:

```swift
public struct TranscriptPartialSnapshot: Equatable, Sendable {
    public let text: String
    public let stablePrefixLength: Int
    public let providerName: String

    public init(text: String, stablePrefixLength: Int, providerName: String) {
        self.text = text
        self.stablePrefixLength = max(0, stablePrefixLength)
        self.providerName = providerName
    }
}

public typealias TranscriptionProgressHandler = @MainActor @Sendable (TranscriptPartialSnapshot) -> Void
```

Update `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`:

```swift
public extension TranscriptSnapshot {
    func appendingPartial(_ partial: TranscriptPartialSnapshot) -> TranscriptSnapshot {
        let trimmed = partial.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return self
        }

        return TranscriptSnapshot(
            finalText: finalText,
            partials: partials + [trimmed],
            providerName: partial.providerName,
            latencyMilliseconds: latencyMilliseconds
        )
    }
}
```

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter TranscriptionModelsTests/testTranscriptSnapshot
```

Expected: the new partial model tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add native/Sources/VocoAppCore/TranscriptionModels.swift native/Sources/VocoAppCore/RecordingWorkflowModels.swift native/Tests/VocoAppCoreTests/TranscriptionModelsTests.swift
git commit -m "feat(native): add streaming transcription models"
```

## Task 2: Recording Workflow Streaming Callbacks

**Files:**
- Modify: `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`
- Modify: `native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift`

- [ ] **Step 1: Write failing workflow callback test**

Add to `RecordingWorkflowTests`:

```swift
@MainActor
func testStopRecordingForwardsPartialProgress() async throws {
    let partial = TranscriptPartialSnapshot(text: "hello", stablePrefixLength: 0, providerName: "Fake ASR")
    let transcription = FakeTranscriptionEngine(
        transcript: TranscriptSnapshot(
            finalText: "hello world",
            partials: ["hello"],
            providerName: "Fake ASR",
            latencyMilliseconds: 9
        ),
        partialsToEmit: [partial]
    )
    let workflow = NativeRecordingWorkflow(
        audioCapture: FakeAudioCaptureEngine(),
        transcription: transcription,
        textInjection: FakeTextInjectionEngine()
    )
    var received: [TranscriptPartialSnapshot] = []

    _ = try await workflow.stopRecording { progress in
        received.append(progress)
    }

    XCTAssertEqual(received, [partial])
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter RecordingWorkflowTests/testStopRecordingForwardsPartialProgress
```

Expected: compile failure because `stopRecording(progress:)` and `transcribe(_:progress:)` do not exist.

- [ ] **Step 3: Implement workflow callback plumbing**

Change protocols in `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`:

```swift
@MainActor
public protocol TranscriptionProviding {
    var status: TranscriptionProviderStatus { get }
    func transcribe(
        _ audio: CapturedAudioSnapshot,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot
}

public extension TranscriptionProviding {
    func transcribe(_ audio: CapturedAudioSnapshot) async throws -> TranscriptSnapshot {
        try await transcribe(audio, progress: nil)
    }
}

@MainActor
public protocol RecordingWorkflowing: AnyObject {
    var transcriptionStatus: TranscriptionProviderStatus { get }
    func startRecording() async throws
    func stopRecording(progress: TranscriptionProgressHandler?) async throws -> RecordingWorkflowResult
}

public extension RecordingWorkflowing {
    func stopRecording() async throws -> RecordingWorkflowResult {
        try await stopRecording(progress: nil)
    }
}
```

Update `NativeRecordingWorkflow.stopRecording`:

```swift
public func stopRecording(progress: TranscriptionProgressHandler? = nil) async throws -> RecordingWorkflowResult {
    let audio = try await audioCapture.stopCapture()
    let transcript = try await transcription.transcribe(audio, progress: progress)
    let insertion = try await insertionSnapshot(for: transcript)

    return RecordingWorkflowResult(audio: audio, transcript: transcript, injection: insertion)
}
```

Update `StaticTranscriptionProvider`, `UnavailableTranscriptionProvider`, `StaticRecordingWorkflow`, and test fakes to implement the new required methods.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter RecordingWorkflowTests/testStopRecordingForwardsPartialProgress
```

Expected: callback test passes.

- [ ] **Step 5: Commit**

Run:

```bash
git add native/Sources/VocoAppCore/RecordingWorkflowModels.swift native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift
git commit -m "feat(native): add recording workflow transcript progress"
```

## Task 3: Coordinator Partial Transcript State

**Files:**
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Write failing coordinator HUD partial test**

Add to `AppCoordinatorTests`:

```swift
@MainActor
func testCoordinatorPublishesPartialTranscriptToHUDWhileTranscribing() async {
    let partial = TranscriptPartialSnapshot(text: "live words", stablePrefixLength: 0, providerName: "Fake ASR")
    let recordingWorkflow = FakeRecordingWorkflow(partialsToEmit: [partial])
    let coordinator = AppCoordinator(hasCompletedOnboarding: true, recordingWorkflow: recordingWorkflow)
    coordinator.finishLaunching()

    await coordinator.toggleRecordingFromUserAction()
    await coordinator.toggleRecordingFromUserAction()

    XCTAssertEqual(coordinator.lastTranscript?.partials, ["live words"])
    XCTAssertEqual(coordinator.hudSnapshot.transcriptPreview, "live words")
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests/testCoordinatorPublishesPartialTranscriptToHUDWhileTranscribing
```

Expected: failure because `AppCoordinator.stopRecording` does not pass progress into the workflow.

- [ ] **Step 3: Implement coordinator partial state**

Update `AppCoordinator.stopRecording`:

```swift
let result = try await recordingWorkflow.stopRecording { [weak self] partial in
    self?.publishTranscriptPartial(partial)
}
```

Add a helper:

```swift
private func publishTranscriptPartial(_ partial: TranscriptPartialSnapshot) {
    let base = lastTranscript ?? TranscriptSnapshot(
        finalText: "",
        partials: [],
        providerName: partial.providerName,
        latencyMilliseconds: nil
    )
    lastTranscript = base.appendingPartial(partial)
}
```

Keep final result assignment after `stopRecording` returns so the final transcript replaces the partial-only snapshot.

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests/testCoordinatorPublishesPartialTranscriptToHUDWhileTranscribing
```

Expected: coordinator test passes and `hudSnapshot.transcriptPreview` uses the latest partial.

- [ ] **Step 5: Commit**

Run:

```bash
git add native/Sources/VocoAppCore/AppCoordinator.swift native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift
git commit -m "feat(native): wire partial transcripts into coordinator"
```

## Task 4: Doubao Provider Request, Auth, and Error Mapping

**Files:**
- Create: `native/Sources/VocoApp/MacDoubaoTranscriptionProvider.swift`
- Modify: `native/Sources/VocoAppCore/TranscriptionModels.swift`
- Modify: `native/Tests/VocoAppCoreTests/TranscriptionModelsTests.swift`
- Modify: `native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift`

- [ ] **Step 1: Write failing request/auth/error tests**

Add to `TranscriptionModelsTests`:

```swift
func testDoubaoRequestBuilderUsesAPIKeyHeadersWithoutLeakingSecret() throws {
    let request = try DoubaoTranscriptionRequest.make(
        apiKey: " sk-test-secret ",
        audio: CapturedAudioSnapshot(durationSeconds: 1, sampleRate: 16_000, peakAmplitude: 0.2, pcm16Samples: [1, 2])
    )

    XCTAssertEqual(request.endpoint.absoluteString, "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")
    XCTAssertEqual(request.resourceID, "volc.seedasr.sauc.duration")
    XCTAssertEqual(request.headers["X-Api-Key"], "sk-test-secret")
    XCTAssertEqual(request.headers["X-Api-Resource-Id"], "volc.seedasr.sauc.duration")
    XCTAssertNil(request.safeDebugDescription.range(of: "sk-test-secret"))
    XCTAssertTrue(request.safeDebugDescription.contains("wss://openspeech.bytedance.com"))
}

func testDoubaoRequestBuilderRejectsMissingCredentialAndAudio() {
    XCTAssertThrowsError(
        try DoubaoTranscriptionRequest.make(
            apiKey: " ",
            audio: CapturedAudioSnapshot(durationSeconds: 1, sampleRate: 16_000, peakAmplitude: 0.2, pcm16Samples: [1])
        )
    ) { error in
        XCTAssertEqual(error as? TranscriptionProviderError, .authentication(providerName: "Doubao", message: "Keychain 中没有保存 Doubao API Key。"))
    }

    XCTAssertThrowsError(
        try DoubaoTranscriptionRequest.make(
            apiKey: "sk-test",
            audio: CapturedAudioSnapshot(durationSeconds: 0, sampleRate: 16_000, peakAmplitude: 0, pcm16Samples: [])
        )
    ) { error in
        XCTAssertEqual(error as? TranscriptionProviderError, .emptyAudio)
    }
}

func testDoubaoServerErrorCodesMapToProviderErrors() {
    XCTAssertEqual(
        DoubaoTranscriptionErrorMapper.providerError(code: 45000002, message: "empty audio"),
        .emptyAudio
    )
    XCTAssertEqual(
        DoubaoTranscriptionErrorMapper.providerError(code: 45000081, message: "timeout"),
        .transport(providerName: "Doubao", message: "server timeout (45000081): timeout", retryable: true)
    )
    XCTAssertEqual(
        DoubaoTranscriptionErrorMapper.providerError(code: 55000031, message: "busy"),
        .transport(providerName: "Doubao", message: "server busy (55000031): busy", retryable: true)
    )
}

func testDoubaoResponseParserExtractsPartialAndFinalText() throws {
    let partial = try DoubaoServerResponse.parsePartial(
        Data(#"{"result":{"utterances":[{"text":"你好","start_time":0,"end_time":500,"definite":false}]}}"#.utf8)
    )
    XCTAssertEqual(partial, TranscriptPartialSnapshot(text: "你好", stablePrefixLength: 0, providerName: "Doubao"))

    let final = try DoubaoServerResponse.parseFinalText(
        Data(#"{"result":{"text":"你好世界","utterances":[{"text":"你好","start_time":0,"end_time":500,"definite":true},{"text":"世界","start_time":500,"end_time":900,"definite":true}]}}"#.utf8)
    )
    XCTAssertEqual(final, "你好世界")
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter TranscriptionModelsTests/testDoubao
```

Expected: compile failure because Doubao request, parser, and mapper types do not exist.

- [ ] **Step 3: Implement request/auth/parser/error foundation**

Add focused types to `native/Sources/VocoAppCore/TranscriptionModels.swift`:

```swift
public struct DoubaoTranscriptionRequest: Equatable, Sendable {
    public let endpoint: URL
    public let resourceID: String
    public let headers: [String: String]
    public let audio: CapturedAudioSnapshot
    public let safeDebugDescription: String

    public static func make(apiKey: String?, audio: CapturedAudioSnapshot) throws -> DoubaoTranscriptionRequest
}

public enum DoubaoTranscriptionErrorMapper {
    public static func providerError(code: Int, message: String) -> TranscriptionProviderError
    public static func transportError(_ error: Error, endpoint: URL) -> TranscriptionProviderError
}

public enum DoubaoServerResponse {
    public static func parsePartial(_ data: Data) throws -> TranscriptPartialSnapshot?
    public static func parseFinalText(_ data: Data) throws -> String
}

@MainActor
public protocol DoubaoTranscriptionTransporting {
    func transcribe(
        request: DoubaoTranscriptionRequest,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot
}
```

Use constants:

```swift
private let doubaoProviderName = "Doubao"
private let doubaoDefaultEndpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
private let doubaoDefaultResourceID = "volc.seedasr.sauc.duration"
```

The request must add `X-Api-Key`, `X-Api-Resource-Id`, `X-Api-Request-Id`, and `X-Api-Connect-Id`. `safeDebugDescription` must never contain the API key.

- [ ] **Step 4: Write failing provider credential tests through workflow**

Add to `RecordingWorkflowTests` a core fake transport and a provider-shaped fake only if importing `VocoApp` from tests is not needed. The behavior to prove is:

```swift
@MainActor
func testTranscriptionProviderMissingCredentialsFailsBeforeTransport() async {
    let provider = CredentialBackedTranscriptionProviderForTest(
        credentialStore: InMemoryTranscriptionCredentialStore(),
        transport: FakeDoubaoTransport()
    )

    do {
        _ = try await provider.transcribe(
            CapturedAudioSnapshot(durationSeconds: 1, sampleRate: 16_000, peakAmplitude: 0.2, pcm16Samples: [1])
        )
        XCTFail("Expected missing credential failure")
    } catch {
        XCTAssertEqual(
            error.localizedDescription,
            "Doubao 认证失败：Keychain 中没有保存 Doubao API Key。"
        )
    }
}
```

- [ ] **Step 5: Implement app provider and default transport**

Create `native/Sources/VocoApp/MacDoubaoTranscriptionProvider.swift`:

```swift
import Foundation
import VocoAppCore

@MainActor
final class MacDoubaoTranscriptionProvider: TranscriptionProviding {
    private let credentialStore: any TranscriptionCredentialStoring
    private let transport: any DoubaoTranscriptionTransporting

    init(
        credentialStore: any TranscriptionCredentialStoring,
        transport: any DoubaoTranscriptionTransporting = URLSessionDoubaoTranscriptionTransport()
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
    }

    var status: TranscriptionProviderStatus {
        let snapshot = credentialStore.currentSnapshot()
        if snapshot.hasAPIKey {
            return .ready(providerName: "Doubao")
        }
        if let message = snapshot.lastErrorMessage {
            return .failed(providerName: "Doubao", message: message)
        }
        return .authenticationRequired(providerName: "Doubao")
    }

    func transcribe(
        _ audio: CapturedAudioSnapshot,
        progress: TranscriptionProgressHandler?
    ) async throws -> TranscriptSnapshot {
        let apiKey = try await credentialStore.apiKey(for: .doubao)
        let request = try DoubaoTranscriptionRequest.make(apiKey: apiKey, audio: audio)
        return try await transport.transcribe(request: request, progress: progress)
    }
}
```

In the same file, implement `URLSessionDoubaoTranscriptionTransport` to:

- Build a `URLRequest` from `DoubaoTranscriptionRequest`.
- Attach all request headers.
- Start `URLSession.webSocketTask(with:)`.
- Call `resume()`.
- Throw `DoubaoTranscriptionErrorMapper.transportError` when the WebSocket handshake or first send fails.
- Throw `.provider(providerName: "Doubao", message: "Native Doubao WebSocket handshake succeeded, but binary audio streaming is not enabled in this build.")` after a successful handshake instead of returning a fake transcript.

- [ ] **Step 6: Run GREEN**

Run:

```bash
cd native && swift test --filter TranscriptionModelsTests/testDoubao
cd native && swift test --filter RecordingWorkflowTests
```

Expected: Doubao builder/parser/error tests and workflow tests pass.

- [ ] **Step 7: Commit**

Run:

```bash
git add native/Sources/VocoAppCore/TranscriptionModels.swift native/Sources/VocoApp/MacDoubaoTranscriptionProvider.swift native/Tests/VocoAppCoreTests/TranscriptionModelsTests.swift native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift
git commit -m "feat(native): add doubao transcription provider"
```

## Task 5: App Wiring From Keychain Credentials to Provider

**Files:**
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift`
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Write wiring expectation test**

The app target is not currently imported by `VocoAppCoreTests`, so validate the user-visible wiring contract at coordinator level:

```swift
@MainActor
func testCoordinatorShowsReadyProviderWhenCredentialBackedWorkflowIsReady() {
    let recordingWorkflow = FakeRecordingWorkflow(transcriptionStatus: .ready(providerName: "Doubao"))
    let credentialStore = InMemoryTranscriptionCredentialStore(apiKey: "sk-test-abcdef")
    let coordinator = AppCoordinator(
        hasCompletedOnboarding: true,
        transcriptionCredentialStore: credentialStore,
        recordingWorkflow: recordingWorkflow
    )

    coordinator.finishLaunching()

    XCTAssertEqual(coordinator.transcriptionProviderStatus, .ready(providerName: "Doubao"))
    XCTAssertTrue(coordinator.transcriptionCredentials.hasAPIKey)
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests/testCoordinatorShowsReadyProviderWhenCredentialBackedWorkflowIsReady
```

Expected: pass may already occur because prior credential and provider status plumbing exists. If it passes before code changes, keep it as a regression guard and verify wiring by source diff in Step 4.

- [ ] **Step 3: Wire native app**

Modify `native/Sources/VocoApp/VocoNativeApp.swift`:

```swift
let credentialStore = MacKeychainCredentialStore()
let transcriptionProvider = MacDoubaoTranscriptionProvider(credentialStore: credentialStore)
let appCoordinator = AppCoordinator(
    hasCompletedOnboarding: true,
    permissionProvider: MacPermissionProvider(),
    launchAtLoginProvider: MacLaunchAtLoginProvider(),
    transcriptionCredentialStore: credentialStore,
    recordingWorkflow: NativeRecordingWorkflow(
        audioCapture: MacAudioCaptureEngine(),
        transcription: transcriptionProvider,
        textInjection: MacTextInjectionProvider()
    ),
    hotkeyProvider: MacHotkeyProvider()
)
```

- [ ] **Step 4: Run GREEN and source guard**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests/testCoordinatorShowsReadyProviderWhenCredentialBackedWorkflowIsReady
rg "transcription: UnavailableTranscriptionProvider\\(\\)" native/Sources/VocoApp/VocoNativeApp.swift
```

Expected: Swift test passes and `rg` exits non-zero because the app no longer hard-codes `UnavailableTranscriptionProvider()`.

- [ ] **Step 5: Amend provider commit or create focused wiring commit**

If Task 4 commit already exists, create:

```bash
git add native/Sources/VocoApp/VocoNativeApp.swift native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift
git commit -m "feat(native): wire doubao provider into native app"
```

The user-requested commit list groups app wiring into provider work, so this commit is acceptable if Task 4 stayed focused on provider types.

## Task 6: Opt-In Live Provider Smoke Test

**Files:**
- Modify: `native/Tests/VocoAppCoreTests/TranscriptionModelsTests.swift`

- [ ] **Step 1: Write opt-in live smoke test**

Add to `TranscriptionModelsTests`:

```swift
func testLiveDoubaoSmokeIsExplicitlyOptIn() throws {
    guard ProcessInfo.processInfo.environment["VOCO_LIVE_DOUBAO_ASR"] == "1" else {
        throw XCTSkip("Set VOCO_LIVE_DOUBAO_ASR=1 to run the live Doubao native smoke test.")
    }

    guard let apiKey = ProcessInfo.processInfo.environment["VOCO_DOUBAO_API_KEY"], !apiKey.isEmpty else {
        XCTFail("VOCO_LIVE_DOUBAO_ASR=1 requires VOCO_DOUBAO_API_KEY.")
        return
    }

    let request = try DoubaoTranscriptionRequest.make(
        apiKey: apiKey,
        audio: CapturedAudioSnapshot(durationSeconds: 0.1, sampleRate: 16_000, peakAmplitude: 0.1, pcm16Samples: [0, 0, 0, 0])
    )

    XCTAssertEqual(request.headers["X-Api-Resource-Id"], "volc.seedasr.sauc.duration")
    XCTAssertNil(request.safeDebugDescription.range(of: apiKey))
}
```

This opt-in smoke test verifies credential/config construction without sending live audio while the Swift transport has a documented binary protocol gap.

- [ ] **Step 2: Run default GREEN**

Run:

```bash
cd native && swift test --filter TranscriptionModelsTests/testLiveDoubaoSmokeIsExplicitlyOptIn
```

Expected: skipped unless `VOCO_LIVE_DOUBAO_ASR=1`.

- [ ] **Step 3: Run missing-credential opt-in failure locally without secrets**

Run:

```bash
cd native && VOCO_LIVE_DOUBAO_ASR=1 swift test --filter TranscriptionModelsTests/testLiveDoubaoSmokeIsExplicitlyOptIn
```

Expected: fails clearly with `VOCO_LIVE_DOUBAO_ASR=1 requires VOCO_DOUBAO_API_KEY.`

- [ ] **Step 4: Keep test in provider commit**

Run:

```bash
git add native/Tests/VocoAppCoreTests/TranscriptionModelsTests.swift
git commit --amend --no-edit
```

Use amend only if it touches the unpushed provider commit in this worktree. Otherwise create a focused commit with subject `feat(native): add doubao live smoke guard`.

## Task 7: Full Verification and Documentation

**Files:**
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-doubao-asr-provider.md`

- [ ] **Step 1: Run required verification**

Run from repository root:

```bash
cd native && swift test
packaging/tests/native_app_bundle_smoke.sh
git diff --check
codesign --verify --deep --strict target/native/Voco.app
```

Expected:

- `swift test` passes all native tests.
- Native app bundle smoke creates or validates `target/native/Voco.app`.
- `git diff --check` reports no whitespace errors.
- `codesign --verify --deep --strict target/native/Voco.app` exits 0.

- [ ] **Step 2: Write verification notes in this plan**

Append a `## Verification Notes` section with exact command outputs:

```markdown
## Verification Notes

- Status: DONE_WITH_CONCERNS
- `cd native && swift test`: [result]
- `packaging/tests/native_app_bundle_smoke.sh`: [result]
- `git diff --check`: [result]
- `codesign --verify --deep --strict target/native/Voco.app`: [result]
- Live Doubao ASR: default test skips unless `VOCO_LIVE_DOUBAO_ASR=1`; Swift native transport performs request/auth/network foundation but does not claim full binary audio streaming success.
- Concern: official Doubao docs were not directly readable in this environment because the pages require JavaScript. Native implementation is conservative and points reviewers to the existing Rust protocol implementation for the remaining live protocol work.
```

Replace each bracketed result with the concrete output observed during verification.

- [ ] **Step 3: Commit verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-05-06-voco-native-doubao-asr-provider.md
git commit -m "docs(native): mark doubao asr verification"
```

## Completion Criteria

- `UnavailableTranscriptionProvider` still exists and still throws `.notConfigured`.
- `TranscriptionProviding` supports streaming progress without breaking existing no-progress calls.
- `NativeRecordingWorkflow` forwards partial transcript progress.
- `AppCoordinator` stores partial transcript state during transcription.
- `HUDSnapshot` can preview the latest partial via `lastTranscript.partials.last`.
- `MacDoubaoTranscriptionProvider` reads Doubao API key via `TranscriptionCredentialStoring`.
- Missing credentials surface as a localized auth/configuration error.
- Network failures include the endpoint and underlying URLSession error text.
- `VocoNativeApp` no longer wires `UnavailableTranscriptionProvider()` as the production transcription provider.
- Live-provider smoke is opt-in with `VOCO_LIVE_DOUBAO_ASR=1` and does not leak raw API keys.
- Final report uses status `DONE_WITH_CONCERNS` unless full binary audio streaming is implemented and verified with live Doubao credentials.
