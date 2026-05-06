# Voco Native Audio Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the native recording workflow's static audio placeholder with an in-process `AVAudioEngine` microphone capture provider that produces 16 kHz mono PCM data and user-visible audio diagnostics.

**Architecture:** Keep platform-free audio buffer math in `VocoAppCore` so it is unit-testable without touching macOS TCC or real devices. Put the `AVAudioEngine` tap and thread-safe capture store in `VocoApp`, then wire it into `NativeRecordingWorkflow` with static transcription and text injection providers until the ASR and injection slices land.

**Tech Stack:** Swift 6, XCTest, AVFoundation `AVAudioEngine`, `AVAudioPCMBuffer`, existing `RecordingWorkflowing` dependency injection.

---

## File Structure

- Modify `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`
  - Add PCM samples to `CapturedAudioSnapshot`.
  - Add static transcription/text-injection providers for app wiring.
- Create `native/Sources/VocoAppCore/AudioCaptureBuffer.swift`
  - Owns pure Swift downmixing, linear resampling to 16 kHz, Int16 conversion, peak calculation, and snapshot creation.
- Create `native/Tests/VocoAppCoreTests/AudioCaptureBufferTests.swift`
  - Covers silence, clipping, stereo downmix, 48 kHz to 16 kHz resampling, duration, and reset behavior.
- Modify `native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift`
  - Keep existing workflow expectations compiling with the new PCM field defaults.
- Modify `native/Sources/VocoAppCore/AppCoordinator.swift`
  - Store `lastAudio` diagnostics from successful recording stops.
- Modify `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`
  - Assert `lastAudio` is retained after a successful recording stop.
- Create `native/Sources/VocoApp/MacAudioCaptureEngine.swift`
  - Implements `AudioCaptureProviding` using `AVAudioEngine` input taps.
- Modify `native/Sources/VocoApp/VocoNativeApp.swift`
  - Wire `NativeRecordingWorkflow(audioCapture: MacAudioCaptureEngine(), transcription: StaticTranscriptionProvider(), textInjection: StaticTextInjectionProvider())`.
- Modify `native/Sources/VocoApp/SettingsView.swift`
  - Show last audio duration, sample rate, sample count, and peak amplitude in recording diagnostics.
- Modify `docs/superpowers/plans/2026-05-06-voco-native-audio-capture.md`
  - Record final verification results.

## Task 1: Core Audio Buffer Red/Green

**Files:**
- Create: `native/Tests/VocoAppCoreTests/AudioCaptureBufferTests.swift`
- Create: `native/Sources/VocoAppCore/AudioCaptureBuffer.swift`
- Modify: `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`

- [ ] **Step 1: Write failing audio buffer tests**

Create `native/Tests/VocoAppCoreTests/AudioCaptureBufferTests.swift`:

```swift
import XCTest
@testable import VocoAppCore

final class AudioCaptureBufferTests: XCTestCase {
    func testSnapshotFromSilenceHasZeroAmplitudeAndExpectedDuration() {
        var buffer = AudioCaptureBuffer(targetSampleRate: 16_000)

        buffer.appendMonoFloat32(Array(repeating: 0, count: 160), sourceSampleRate: 16_000)
        let snapshot = buffer.snapshot()

        XCTAssertEqual(snapshot.sampleRate, 16_000)
        XCTAssertEqual(snapshot.pcm16Samples.count, 160)
        XCTAssertEqual(snapshot.durationSeconds, 0.01, accuracy: 0.0001)
        XCTAssertEqual(snapshot.peakAmplitude, 0)
    }

    func testFloatSamplesAreClippedAndConvertedToInt16() {
        var buffer = AudioCaptureBuffer(targetSampleRate: 16_000)

        buffer.appendMonoFloat32([-2.0, -0.5, 0.0, 0.5, 2.0], sourceSampleRate: 16_000)

        XCTAssertEqual(buffer.snapshot().pcm16Samples, [Int16.min + 1, -16_383, 0, 16_383, Int16.max])
        XCTAssertEqual(buffer.snapshot().peakAmplitude, 1.0, accuracy: 0.0001)
    }

    func testStereoInputIsDownmixedBeforeConversion() {
        var buffer = AudioCaptureBuffer(targetSampleRate: 16_000)

        buffer.appendNonInterleavedFloat32(
            [[1.0, -1.0], [-1.0, 1.0]],
            sourceSampleRate: 16_000
        )

        XCTAssertEqual(buffer.snapshot().pcm16Samples, [0, 0])
        XCTAssertEqual(buffer.snapshot().peakAmplitude, 0)
    }

    func testInputIsResampledFrom48kHzTo16kHz() {
        var buffer = AudioCaptureBuffer(targetSampleRate: 16_000)

        buffer.appendMonoFloat32(Array(repeating: 0.25, count: 480), sourceSampleRate: 48_000)

        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.sampleRate, 16_000)
        XCTAssertEqual(snapshot.pcm16Samples.count, 160)
        XCTAssertEqual(snapshot.durationSeconds, 0.01, accuracy: 0.0001)
        XCTAssertEqual(snapshot.peakAmplitude, 0.25, accuracy: 0.001)
    }

    func testResetDropsCapturedSamples() {
        var buffer = AudioCaptureBuffer(targetSampleRate: 16_000)
        buffer.appendMonoFloat32([0.5, 0.5], sourceSampleRate: 16_000)

        buffer.reset()

        let snapshot = buffer.snapshot()
        XCTAssertTrue(snapshot.pcm16Samples.isEmpty)
        XCTAssertEqual(snapshot.durationSeconds, 0)
        XCTAssertEqual(snapshot.peakAmplitude, 0)
    }
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter AudioCaptureBufferTests
```

Expected: compile failure because `AudioCaptureBuffer` and `CapturedAudioSnapshot.pcm16Samples` do not exist.

- [ ] **Step 3: Implement captured audio snapshot and buffer**

Update `CapturedAudioSnapshot` in `RecordingWorkflowModels.swift` so the initializer keeps existing call sites source-compatible:

```swift
public struct CapturedAudioSnapshot: Equatable, Sendable {
    public let durationSeconds: Double
    public let sampleRate: Double
    public let peakAmplitude: Double
    public let pcm16Samples: [Int16]

    public init(durationSeconds: Double, sampleRate: Double, peakAmplitude: Double, pcm16Samples: [Int16] = []) {
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.peakAmplitude = peakAmplitude
        self.pcm16Samples = pcm16Samples
    }
}
```

Create `AudioCaptureBuffer.swift` with:

```swift
import Foundation

public struct AudioCaptureBuffer: Sendable {
    private let targetSampleRate: Double
    private var resampler: Float32LinearResampler
    private var pcm16Samples: [Int16]
    private var peakAmplitude: Double

    public init(targetSampleRate: Double = 16_000) {
        precondition(targetSampleRate > 0)
        self.targetSampleRate = targetSampleRate
        self.resampler = Float32LinearResampler()
        self.pcm16Samples = []
        self.peakAmplitude = 0
    }

    public mutating func reset() {
        resampler.reset()
        pcm16Samples.removeAll(keepingCapacity: true)
        peakAmplitude = 0
    }

    public mutating func appendNonInterleavedFloat32(_ channels: [[Float]], sourceSampleRate: Double) {
        guard sourceSampleRate > 0, let firstChannel = channels.first, !firstChannel.isEmpty else {
            return
        }

        let frameCount = firstChannel.count
        var mono = Array(repeating: Float(0), count: frameCount)
        let usableChannels = channels.filter { $0.count >= frameCount }
        guard !usableChannels.isEmpty else {
            return
        }

        for channel in usableChannels {
            for index in 0..<frameCount {
                mono[index] += channel[index]
            }
        }

        let divisor = Float(usableChannels.count)
        appendMonoFloat32(mono.map { $0 / divisor }, sourceSampleRate: sourceSampleRate)
    }

    public mutating func appendMonoFloat32(_ samples: [Float], sourceSampleRate: Double) {
        guard sourceSampleRate > 0, !samples.isEmpty else {
            return
        }

        let resampled = resampler.resample(samples, sourceSampleRate: sourceSampleRate, targetSampleRate: targetSampleRate)
        for sample in resampled {
            let pcm = Self.floatToInt16(sample)
            pcm16Samples.append(pcm)
            peakAmplitude = max(peakAmplitude, min(abs(Double(sample)), 1.0))
        }
    }

    public func snapshot() -> CapturedAudioSnapshot {
        CapturedAudioSnapshot(
            durationSeconds: Double(pcm16Samples.count) / targetSampleRate,
            sampleRate: targetSampleRate,
            peakAmplitude: peakAmplitude,
            pcm16Samples: pcm16Samples
        )
    }

    private static func floatToInt16(_ sample: Float) -> Int16 {
        let clipped = sample.isFinite ? min(max(sample, -1), 1) : 0
        return Int16(clipped * Float(Int16.max))
    }
}
```

Also define the private `Float32LinearResampler` in the same file:

```swift
private struct Float32LinearResampler: Sendable {
    private var pending: [Float] = []
    private var nextSourcePosition: Double = 0

    mutating func reset() {
        pending.removeAll(keepingCapacity: true)
        nextSourcePosition = 0
    }

    mutating func resample(_ samples: [Float], sourceSampleRate: Double, targetSampleRate: Double) -> [Float] {
        guard sourceSampleRate > 0, targetSampleRate > 0, !samples.isEmpty else {
            return []
        }

        pending.append(contentsOf: samples.map { sample in
            sample.isFinite ? min(max(sample, -1), 1) : 0
        })

        let step = sourceSampleRate / targetSampleRate
        var output: [Float] = []
        output.reserveCapacity(Int((Double(samples.count) / step).rounded(.up)) + 1)

        while true {
            let index = Int(nextSourcePosition.rounded(.down))
            guard index < pending.count else {
                break
            }

            let fraction = nextSourcePosition - Double(index)
            if fraction <= Double.ulpOfOne {
                output.append(pending[index])
            } else if index + 1 < pending.count {
                output.append(pending[index] + ((pending[index + 1] - pending[index]) * Float(fraction)))
            } else {
                break
            }

            nextSourcePosition += step
        }

        let drainCount = min(Int(nextSourcePosition.rounded(.down)), pending.count)
        if drainCount > 0 {
            pending.removeFirst(drainCount)
            nextSourcePosition -= Double(drainCount)
        }

        return output
    }
}
```

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter AudioCaptureBufferTests
```

Expected: all `AudioCaptureBufferTests` pass.

- [ ] **Step 5: Commit core audio buffer**

Run:

```bash
git add native/Sources/VocoAppCore/RecordingWorkflowModels.swift native/Sources/VocoAppCore/AudioCaptureBuffer.swift native/Tests/VocoAppCoreTests/AudioCaptureBufferTests.swift docs/superpowers/plans/2026-05-06-voco-native-audio-capture.md
git commit -m "feat(native): add audio capture buffer"
```

## Task 2: Coordinator Audio Diagnostics

**Files:**
- Modify: `native/Sources/VocoAppCore/AppCoordinator.swift`
- Modify: `native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift`
- Modify: `native/Sources/VocoApp/SettingsView.swift`

- [ ] **Step 1: Write failing coordinator diagnostics test**

In `AppCoordinatorTests.testRecordingWorkflowStopStoresDiagnosticsAndReturnsReady`, add:

```swift
XCTAssertEqual(coordinator.lastAudio, result.audio)
```

Expected failure: `AppCoordinator` has no `lastAudio`.

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests/testRecordingWorkflowStopStoresDiagnosticsAndReturnsReady
```

Expected: compile failure because `lastAudio` does not exist.

- [ ] **Step 3: Store and clear last audio**

Update `AppCoordinator`:

```swift
@Published public private(set) var lastAudio: CapturedAudioSnapshot?
```

Initialize it to `nil`, clear it in `startRecording()` with transcript and injection diagnostics, and set it in `stopRecording()` immediately after the workflow returns:

```swift
lastAudio = result.audio
lastTranscript = result.transcript
lastInjection = result.injection
```

- [ ] **Step 4: Render audio diagnostics**

In `recordingDiagnosticsSection`, include the section when `lastAudio` is present and add a row:

```swift
if let audio = coordinator.lastAudio {
    diagnosticRow(
        title: "音频",
        value: String(format: "%.2fs · %.0f Hz · %d samples · peak %.2f", audio.durationSeconds, audio.sampleRate, audio.pcm16Samples.count, audio.peakAmplitude),
        systemImage: "waveform"
    )
}
```

- [ ] **Step 5: Run GREEN**

Run:

```bash
cd native && swift test --filter AppCoordinatorTests/testRecordingWorkflowStopStoresDiagnosticsAndReturnsReady
```

Expected: the focused test passes.

- [ ] **Step 6: Commit diagnostics**

Run:

```bash
git add native/Sources/VocoAppCore/AppCoordinator.swift native/Tests/VocoAppCoreTests/AppCoordinatorTests.swift native/Sources/VocoApp/SettingsView.swift
git commit -m "feat(native): show audio capture diagnostics"
```

## Task 3: Static Providers for Native Workflow Wiring

**Files:**
- Modify: `native/Sources/VocoAppCore/RecordingWorkflowModels.swift`
- Modify: `native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift`

- [ ] **Step 1: Write failing static provider test**

Add to `RecordingWorkflowTests`:

```swift
@MainActor
func testStaticProvidersReturnConfiguredSnapshots() async throws {
    let audio = CapturedAudioSnapshot(durationSeconds: 0.2, sampleRate: 16_000, peakAmplitude: 0.1, pcm16Samples: [1, 2])
    let transcript = try await StaticTranscriptionProvider().transcribe(audio)
    let injection = try await StaticTextInjectionProvider().insert("hello")

    XCTAssertEqual(transcript.providerName, "Unconfigured")
    XCTAssertEqual(transcript.finalText, "")
    XCTAssertEqual(injection.strategy, .skippedEmpty)
    XCTAssertTrue(injection.succeeded)
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
cd native && swift test --filter RecordingWorkflowTests/testStaticProvidersReturnConfiguredSnapshots
```

Expected: compile failure because `StaticTranscriptionProvider` and `StaticTextInjectionProvider` do not exist.

- [ ] **Step 3: Implement static providers**

Add to `RecordingWorkflowModels.swift`:

```swift
public final class StaticTranscriptionProvider: TranscriptionProviding {
    private let transcript: TranscriptSnapshot

    public init(transcript: TranscriptSnapshot = TranscriptSnapshot(finalText: "", partials: [], providerName: "Unconfigured", latencyMilliseconds: nil)) {
        self.transcript = transcript
    }

    public func transcribe(_ audio: CapturedAudioSnapshot) async throws -> TranscriptSnapshot {
        transcript
    }
}

public final class StaticTextInjectionProvider: TextInjectionProviding {
    private let result: TextInjectionSnapshot

    public init(result: TextInjectionSnapshot = .skippedEmpty) {
        self.result = result
    }

    public func insert(_ text: String) async throws -> TextInjectionSnapshot {
        result
    }
}
```

- [ ] **Step 4: Run GREEN**

Run:

```bash
cd native && swift test --filter RecordingWorkflowTests/testStaticProvidersReturnConfiguredSnapshots
```

Expected: focused test passes.

- [ ] **Step 5: Commit static providers**

Run:

```bash
git add native/Sources/VocoAppCore/RecordingWorkflowModels.swift native/Tests/VocoAppCoreTests/RecordingWorkflowTests.swift
git commit -m "feat(native): add static recording providers"
```

## Task 4: Mac AVAudioEngine Provider

**Files:**
- Create: `native/Sources/VocoApp/MacAudioCaptureEngine.swift`
- Modify: `native/Sources/VocoApp/VocoNativeApp.swift`

- [ ] **Step 1: Implement macOS audio provider**

Create `MacAudioCaptureEngine.swift`:

```swift
import AVFoundation
import Foundation
import VocoAppCore

@MainActor
final class MacAudioCaptureEngine: AudioCaptureProviding {
    private let engine = AVAudioEngine()
    private let store = LockedAudioCaptureStore()
    private var isCapturing = false

    func startCapture() async throws {
        guard !isCapturing else {
            throw RecordingWorkflowError("audio capture already running")
        }

        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecordingWorkflowError("microphone input format unavailable")
        }

        store.reset()
        let bufferSize = AVAudioFrameCount(max(160, min(1024, Int(format.sampleRate * 0.02))))
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [store] buffer, _ in
            store.append(buffer)
        }

        do {
            try engine.start()
            isCapturing = true
        } catch {
            inputNode.removeTap(onBus: 0)
            throw RecordingWorkflowError("audio capture failed to start: \(error.localizedDescription)")
        }
    }

    func stopCapture() async throws -> CapturedAudioSnapshot {
        guard isCapturing else {
            throw RecordingWorkflowError("audio capture is not running")
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        return store.snapshot()
    }
}
```

In the same file, define `LockedAudioCaptureStore` with an `NSLock`, an internal `AudioCaptureBuffer`, `reset()`, `append(_ buffer: AVAudioPCMBuffer)`, and `snapshot()`. `append(_:)` must read `buffer.floatChannelData`, copy each channel into `[Float]`, call `audioBuffer.appendNonInterleavedFloat32(channels, sourceSampleRate: buffer.format.sampleRate)`, and ignore only empty buffers.

- [ ] **Step 2: Wire native app to real audio capture**

Update `VocoNativeApp.init()`:

```swift
recordingWorkflow: NativeRecordingWorkflow(
    audioCapture: MacAudioCaptureEngine(),
    transcription: StaticTranscriptionProvider(),
    textInjection: StaticTextInjectionProvider()
),
```

- [ ] **Step 3: Run native tests**

Run:

```bash
cd native && swift test
```

Expected: all native tests pass and the app target compiles with `MacAudioCaptureEngine`.

- [ ] **Step 4: Commit macOS provider**

Run:

```bash
git add native/Sources/VocoApp/MacAudioCaptureEngine.swift native/Sources/VocoApp/VocoNativeApp.swift
git commit -m "feat(native): capture microphone with AVAudioEngine"
```

## Task 5: Verification

**Files:**
- Verify generated bundle under `target/native/Voco.app`
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-audio-capture.md`

- [ ] **Step 1: Run full native tests**

Run:

```bash
cd native && swift test
```

Expected: all native tests pass.

- [ ] **Step 2: Run native bundle smoke**

Run:

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

Expected: both commands exit 0.

- [ ] **Step 4: Record verification results**

Append observed command results under `## Verification Results`.

- [ ] **Step 5: Commit verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-05-06-voco-native-audio-capture.md
git commit -m "docs(native): mark audio capture verification"
```

## Spec Coverage

- Covers the design requirement that `AudioCaptureEngine` uses `AVAudioEngine` in the single-process native app.
- Produces 16 kHz mono PCM samples for the future Swift transcription provider.
- Records duration, sample rate, sample count, and amplitude diagnostics for the settings surface.
- Keeps hotkey, ASR provider, text injection, HUD overlay, Keychain, and DMG notarization as separate implementation slices.
