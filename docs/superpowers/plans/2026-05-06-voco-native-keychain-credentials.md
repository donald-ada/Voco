# Voco Native Keychain Credentials Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Keychain-backed ASR credential storage so native Voco can save, clear, and diagnose provider API keys without exposing secrets.

**Architecture:** Keep credential state, masking, store protocol, and coordinator wiring in `VocoAppCore` for unit tests. Put Security framework calls in `VocoApp/MacKeychainCredentialStore.swift`, then expose save/clear controls in Settings while the real ASR provider remains a later slice.

**Tech Stack:** Swift 6, XCTest, SwiftUI, Security Keychain Services, existing `AppCoordinator` dependency injection.

---

## Baseline

Run:

```bash
cd native && swift test
```

Expected: all existing native tests pass before this slice starts.

Observed before Task 1: PASS. XCTest executed 62 tests with 0 failures.

## File Structure

- Create `native/Sources/VocoAppCore/TranscriptionCredentialModels.swift` — provider identity, masked credential snapshot, credential errors, store protocol, and in-memory store for tests/defaults.
- Create `native/Tests/VocoAppCoreTests/TranscriptionCredentialModelsTests.swift` — snapshot masking and error messages.
- Modify `native/Sources/VocoAppCore/AppCoordinator.swift` — publish credential snapshot and save/clear/refresh methods.
- Modify `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift` — fake credential store tests for save, clear, and failure surfacing.
- Create `native/Sources/VocoApp/MacKeychainCredentialStore.swift` — real Keychain read/save/delete implementation.
- Modify `native/Sources/VocoApp/VocoNativeApp.swift` — inject Keychain store.
- Modify `native/Sources/VocoApp/SettingsView.swift` — render credential status plus save/clear controls.
- Modify this plan with final verification results.

## Task 1: Credential Core Models

**Files:**
- Create: `native/Tests/VocoAppCoreTests/TranscriptionCredentialModelsTests.swift`
- Create: `native/Sources/VocoAppCore/TranscriptionCredentialModels.swift`

- [ ] **Step 1: Write failing credential model tests**

Create `native/Tests/VocoAppCoreTests/TranscriptionCredentialModelsTests.swift`:

```swift
import XCTest
@testable import VocoAppCore

final class TranscriptionCredentialModelsTests: XCTestCase {
    func testStoredSnapshotMasksAPIKey() {
        let snapshot = TranscriptionCredentialSnapshot.stored(
            provider: .doubao,
            apiKey: "sk-test-1234567890"
        )

        XCTAssertEqual(snapshot.provider.title, "Doubao")
        XCTAssertTrue(snapshot.hasAPIKey)
        XCTAssertEqual(snapshot.maskedAPIKey, "sk-t...7890")
        XCTAssertEqual(snapshot.statusTitle, "Doubao 凭证已保存")
        XCTAssertNil(snapshot.lastErrorMessage)
    }

    func testMissingAndFailedSnapshotsAreUserVisible() {
        let missing = TranscriptionCredentialSnapshot.missing(provider: .doubao)
        XCTAssertFalse(missing.hasAPIKey)
        XCTAssertEqual(missing.statusTitle, "Doubao 凭证未保存")
        XCTAssertEqual(missing.storageDetail, "Keychain 中没有保存 API Key。")

        let failed = TranscriptionCredentialSnapshot.failed(provider: .doubao, message: "read failed")
        XCTAssertFalse(failed.hasAPIKey)
        XCTAssertEqual(failed.statusTitle, "Doubao 凭证读取失败")
        XCTAssertEqual(failed.lastErrorMessage, "read failed")
    }

    func testCredentialErrorsAreLocalized() {
        XCTAssertEqual(
            TranscriptionCredentialError.emptyAPIKey.localizedDescription,
            "ASR API Key 不能为空。"
        )
        XCTAssertEqual(
            TranscriptionCredentialError.storeFailed(message: "OSStatus -50").localizedDescription,
            "保存 ASR 凭证失败：OSStatus -50"
        )
    }

    @MainActor
    func testInMemoryCredentialStoreSavesAndDeletesKey() async throws {
        let store = InMemoryTranscriptionCredentialStore()

        XCTAssertEqual(store.currentSnapshot(), .missing(provider: .doubao))

        let stored = try await store.saveAPIKey("  sk-test-abcdef  ", for: .doubao)
        XCTAssertTrue(stored.hasAPIKey)
        XCTAssertEqual(try await store.apiKey(for: .doubao), "sk-test-abcdef")

        let missing = try await store.deleteCredentials(for: .doubao)
        XCTAssertEqual(missing, .missing(provider: .doubao))
        XCTAssertNil(try await store.apiKey(for: .doubao))
    }
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter TranscriptionCredentialModelsTests
```

Expected: compile failure because credential models and store do not exist.

- [ ] **Step 3: Implement credential models and in-memory store**

Create `native/Sources/VocoAppCore/TranscriptionCredentialModels.swift`:

```swift
import Foundation

public enum TranscriptionCredentialProvider: String, CaseIterable, Identifiable, Sendable {
    case doubao

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .doubao:
            "Doubao"
        }
    }
}

public struct TranscriptionCredentialSnapshot: Equatable, Sendable {
    public let provider: TranscriptionCredentialProvider
    public let hasAPIKey: Bool
    public let maskedAPIKey: String?
    public let storageDetail: String
    public let lastErrorMessage: String?

    public var statusTitle: String {
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            "\(provider.title) 凭证读取失败"
        } else if hasAPIKey {
            "\(provider.title) 凭证已保存"
        } else {
            "\(provider.title) 凭证未保存"
        }
    }

    public static func missing(provider: TranscriptionCredentialProvider) -> TranscriptionCredentialSnapshot {
        TranscriptionCredentialSnapshot(
            provider: provider,
            hasAPIKey: false,
            maskedAPIKey: nil,
            storageDetail: "Keychain 中没有保存 API Key。",
            lastErrorMessage: nil
        )
    }

    public static func stored(
        provider: TranscriptionCredentialProvider,
        apiKey: String
    ) -> TranscriptionCredentialSnapshot {
        TranscriptionCredentialSnapshot(
            provider: provider,
            hasAPIKey: true,
            maskedAPIKey: maskAPIKey(apiKey),
            storageDetail: "API Key 已安全保存在 Keychain。",
            lastErrorMessage: nil
        )
    }

    public static func failed(
        provider: TranscriptionCredentialProvider,
        message: String
    ) -> TranscriptionCredentialSnapshot {
        TranscriptionCredentialSnapshot(
            provider: provider,
            hasAPIKey: false,
            maskedAPIKey: nil,
            storageDetail: "Keychain 访问失败：\(message)",
            lastErrorMessage: message
        )
    }
}

public enum TranscriptionCredentialError: LocalizedError, Equatable, Sendable {
    case emptyAPIKey
    case readFailed(message: String)
    case storeFailed(message: String)
    case deleteFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            "ASR API Key 不能为空。"
        case .readFailed(let message):
            "读取 ASR 凭证失败：\(message)"
        case .storeFailed(let message):
            "保存 ASR 凭证失败：\(message)"
        case .deleteFailed(let message):
            "删除 ASR 凭证失败：\(message)"
        }
    }
}

@MainActor
public protocol TranscriptionCredentialStoring {
    func currentSnapshot() -> TranscriptionCredentialSnapshot
    func saveAPIKey(_ apiKey: String, for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredentialSnapshot
    func deleteCredentials(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredentialSnapshot
    func apiKey(for provider: TranscriptionCredentialProvider) async throws -> String?
}

@MainActor
public final class InMemoryTranscriptionCredentialStore: TranscriptionCredentialStoring {
    private let provider: TranscriptionCredentialProvider
    private var storedAPIKey: String?

    public init(provider: TranscriptionCredentialProvider = .doubao, apiKey: String? = nil) {
        self.provider = provider
        self.storedAPIKey = apiKey
    }

    public func currentSnapshot() -> TranscriptionCredentialSnapshot {
        guard let storedAPIKey, !storedAPIKey.isEmpty else {
            return .missing(provider: provider)
        }

        return .stored(provider: provider, apiKey: storedAPIKey)
    }

    public func saveAPIKey(
        _ apiKey: String,
        for provider: TranscriptionCredentialProvider
    ) async throws -> TranscriptionCredentialSnapshot {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionCredentialError.emptyAPIKey
        }

        self.storedAPIKey = trimmed
        return .stored(provider: provider, apiKey: trimmed)
    }

    public func deleteCredentials(for provider: TranscriptionCredentialProvider) async throws -> TranscriptionCredentialSnapshot {
        storedAPIKey = nil
        return .missing(provider: provider)
    }

    public func apiKey(for provider: TranscriptionCredentialProvider) async throws -> String? {
        storedAPIKey
    }
}

private func maskAPIKey(_ apiKey: String) -> String {
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 8 else {
        return String(repeating: "•", count: max(trimmed.count, 4))
    }

    return "\(trimmed.prefix(4))...\(trimmed.suffix(4))"
}
```

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter TranscriptionCredentialModelsTests
```

Expected: all credential model tests pass.

- [ ] **Step 5: Commit credential models**

Run:

```bash
git add native/Sources/VocoAppCore/TranscriptionCredentialModels.swift native/Tests/VocoAppCoreTests/TranscriptionCredentialModelsTests.swift docs/superpowers/plans/2026-05-06-voco-native-keychain-credentials.md
git commit -m "feat(native): add transcription credential models"
```

## Task 2: Coordinator Credential State

**Files:**
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`

- [ ] **Step 1: Write failing coordinator tests**

Add to `AppCoordinatorTests`:

```swift
@MainActor
func testCoordinatorPublishesTranscriptionCredentialSnapshot() {
    let credentialStore = InMemoryTranscriptionCredentialStore(apiKey: "sk-test-abcdef")
    let coordinator = AppCoordinator(hasCompletedOnboarding: true, transcriptionCredentialStore: credentialStore)

    coordinator.finishLaunching()

    XCTAssertTrue(coordinator.transcriptionCredentials.hasAPIKey)
    XCTAssertEqual(coordinator.transcriptionCredentials.maskedAPIKey, "sk-t...cdef")
}

@MainActor
func testCoordinatorSavesAndClearsTranscriptionCredentials() async {
    let credentialStore = InMemoryTranscriptionCredentialStore()
    let coordinator = AppCoordinator(hasCompletedOnboarding: true, transcriptionCredentialStore: credentialStore)

    await coordinator.saveTranscriptionAPIKey("sk-test-abcdef")

    XCTAssertTrue(coordinator.transcriptionCredentials.hasAPIKey)
    XCTAssertNil(coordinator.lastErrorMessage)

    await coordinator.clearTranscriptionCredentials()

    XCTAssertFalse(coordinator.transcriptionCredentials.hasAPIKey)
    XCTAssertNil(try await credentialStore.apiKey(for: .doubao))
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests/testCoordinator
```

Expected: compile failure because `AppCoordinator` has no credential store injection or credential methods.

- [ ] **Step 3: Implement coordinator credential wiring**

In `AppCoordinator`:

- Add `@Published public private(set) var transcriptionCredentials: TranscriptionCredentialSnapshot`.
- Add private `credentialStore: any TranscriptionCredentialStoring`.
- Add init parameter `transcriptionCredentialStore: any TranscriptionCredentialStoring = InMemoryTranscriptionCredentialStore()`.
- Initialize `transcriptionCredentials = transcriptionCredentialStore.currentSnapshot()`.
- Refresh credentials in `finishLaunching()` and `prepareForSettingsPresentation()`.
- Add:

```swift
public func refreshTranscriptionCredentials() {
    transcriptionCredentials = credentialStore.currentSnapshot()
    if let message = transcriptionCredentials.lastErrorMessage {
        lastErrorMessage = message
    }
}

public func saveTranscriptionAPIKey(_ apiKey: String) async {
    do {
        transcriptionCredentials = try await credentialStore.saveAPIKey(apiKey, for: .doubao)
        lastErrorMessage = nil
    } catch {
        let message = error.localizedDescription
        transcriptionCredentials = .failed(provider: .doubao, message: message)
        lastErrorMessage = message
    }
}

public func clearTranscriptionCredentials() async {
    do {
        transcriptionCredentials = try await credentialStore.deleteCredentials(for: .doubao)
        lastErrorMessage = nil
    } catch {
        let message = error.localizedDescription
        transcriptionCredentials = .failed(provider: .doubao, message: message)
        lastErrorMessage = message
    }
}
```

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests/testCoordinator
```

Expected: coordinator credential tests pass.

- [ ] **Step 5: Commit coordinator state**

Run:

```bash
git add native/Sources/VocoAppCore/AppCoordinator.swift native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift
git commit -m "feat(native): publish transcription credentials"
```

## Task 3: macOS Keychain Store and Settings UI

**Files:**
- Create: `native/Sources/VocoApp/MacKeychainCredentialStore.swift`
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift`
- Modify: `native/Sources/VocoApp/SettingsView.swift`

- [ ] **Step 1: Add Keychain credential store**

Create `native/Sources/VocoApp/MacKeychainCredentialStore.swift` with a `MacKeychainCredentialStore: TranscriptionCredentialStoring` that:

- uses service `com.voco.app.asr`;
- uses account `provider.rawValue`;
- reads generic password data with `SecItemCopyMatching`;
- saves by `SecItemUpdate` or `SecItemAdd`;
- deletes with `SecItemDelete`;
- throws `TranscriptionCredentialError.readFailed/storeFailed/deleteFailed` with `SecCopyErrorMessageString` plus OSStatus code;
- returns `.failed(...)` from `currentSnapshot()` when a read error occurs.

- [ ] **Step 2: Inject Keychain store**

Modify `native/Sources/VocoApp/VocoNativeApp.swift`:

```swift
let appCoordinator = AppCoordinator(
    hasCompletedOnboarding: true,
    permissionProvider: MacPermissionProvider(),
    launchAtLoginProvider: MacLaunchAtLoginProvider(),
    transcriptionCredentialStore: MacKeychainCredentialStore(),
    recordingWorkflow: NativeRecordingWorkflow(
        audioCapture: MacAudioCaptureEngine(),
        transcription: UnavailableTranscriptionProvider(),
        textInjection: MacTextInjectionProvider()
    ),
    hotkeyProvider: MacHotkeyProvider()
)
```

- [ ] **Step 3: Render credential controls in Settings**

In `SettingsView`, add `@State private var transcriptionAPIKey = ""` and extend `transcriptionSection` with:

```swift
Divider()

HStack(spacing: 8) {
    Image(systemName: coordinator.transcriptionCredentials.hasAPIKey ? "key.fill" : "key")
    VStack(alignment: .leading, spacing: 2) {
        Text(coordinator.transcriptionCredentials.statusTitle)
            .font(.subheadline)
            .fontWeight(.semibold)
        Text(coordinator.transcriptionCredentials.maskedAPIKey ?? coordinator.transcriptionCredentials.storageDetail)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

SecureField("Doubao API Key", text: $transcriptionAPIKey)
    .textFieldStyle(.roundedBorder)

HStack(spacing: 8) {
    Button {
        let apiKey = transcriptionAPIKey
        transcriptionAPIKey = ""
        Task {
            await coordinator.saveTranscriptionAPIKey(apiKey)
        }
    } label: {
        Label("保存到 Keychain", systemImage: "key")
    }
    .disabled(transcriptionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

    Button(role: .destructive) {
        Task {
            await coordinator.clearTranscriptionCredentials()
        }
    } label: {
        Label("清除凭证", systemImage: "trash")
    }
    .disabled(!coordinator.transcriptionCredentials.hasAPIKey)
}
```

- [ ] **Step 4: Run app compile tests**

Run:

```bash
cd native && swift test
```

Expected: all native tests pass and the executable target compiles with Security framework imports.

- [ ] **Step 5: Commit Keychain UI**

Run:

```bash
git add native/Sources/VocoApp/MacKeychainCredentialStore.swift native/Sources/VocoApp/VocoNativeApp.swift native/Sources/VocoApp/SettingsView.swift
git commit -m "feat(native): store transcription credentials in keychain"
```

## Task 4: Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-keychain-credentials.md`

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
git add docs/superpowers/plans/2026-05-06-voco-native-keychain-credentials.md
git commit -m "docs(native): mark keychain credential verification"
```

## Scope Notes

- Covers the native rewrite requirement that provider credentials are stored in Keychain.
- Surfaces Keychain status in Settings without displaying full secrets.
- Keeps real Doubao/WebSocket transcription, streaming partials, diagnostics export, and release DMG notarization as separate slices.
