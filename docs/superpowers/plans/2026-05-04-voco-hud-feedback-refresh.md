# Voco HUD Feedback Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh the HUD into the selected compact black/yellow/green design, make recording feedback animate immediately, reduce long-dictation cutoff, and default Doubao streaming ASR to Seed ASR 2.0 hourly.

**Architecture:** Keep the existing Rust daemon -> JSONL stdin -> Swift HUD helper architecture. Swift owns visual state/rendering and uses `HudModel` plus theme constants; Rust config owns recording duration and Doubao resource defaults. Use `volc.seedasr.sauc.duration` as the Seed ASR 2.0 `resource_id`, and use the `bigmodel_nostream` WebSocket endpoint because live doctor probes showed `bigmodel` returns HTTP 400 with that resource and `bigmodel_async` times out for the empty-audio doctor check.

**Tech Stack:** SwiftUI, XCTest, Rust 2021, cargo tests, existing `voco-config`, `voco-cli`, `voco-asr`, and `voco-daemon` crates.

---

## File Structure

- Modify: `hud/Sources/VocoHUDCore/HudModel.swift` — add presentation epoch tracking for first-press entry animation.
- Create: `hud/Sources/VocoHUDCore/HudTheme.swift` — centralize B2 compact layout and black/yellow/green color tokens.
- Modify: `hud/Sources/VocoHUDCore/CapsuleView.swift` — implement black capsule, yellow mic, green waveform, immediate animation, and remove the yellow dot.
- Modify: `hud/Sources/VocoHUD/main.swift` — size the panel to the compact HUD dimensions.
- Modify: `hud/Tests/VocoHUDTests/HudEventTests.swift` — add model and theme tests.
- Modify: `crates/voco-config/src/schema.rs` — default recording duration 300 seconds, default Doubao 2.0 `resource_id`, and default `bigmodel_nostream` endpoint.
- Modify: `crates/voco-config/tests/validate.rs` — assert new config defaults.
- Modify: `crates/voco-cli/src/commands/config/wizard.rs` — use Seed ASR 2.0 endpoint and `resource_id` fallbacks for new Doubao config.
- Modify: `crates/voco-cli/src/commands/config/set.rs` — use Seed ASR 2.0 endpoint and `resource_id` fallbacks when `config set` creates a Doubao section.
- Modify: `crates/voco-cli/tests/config_subcommands.rs` — assert CLI fallback writes Seed ASR 2.0 `resource_id`.
- Modify: `crates/voco-asr/tests/mock_server.rs` — assert outgoing header uses Seed ASR 2.0 `resource_id`.
- Modify: `crates/voco-daemon/src/orchestrator.rs` — add a regression guard that hotkey recording stays active and HUD stays visible until explicit stop, with the 300-second default cap.
- Modify: `docs/superpowers/plans/2026-05-04-voco-hud-feedback-refresh.md` — record final verification.

## Task 1: Swift Model Red Tests for First-Press Presentation Epoch

**Files:**
- Modify: `hud/Tests/VocoHUDTests/HudEventTests.swift`

- [ ] **Step 1: Add failing HudModel presentation epoch tests**

Append these tests inside `@MainActor final class HudModelTests: XCTestCase` in `hud/Tests/VocoHUDTests/HudEventTests.swift`:

```swift
    func testVisibleStateIncrementsPresentationEpoch() {
        let model = HudModel()

        XCTAssertEqual(model.presentationEpoch, 0)
        model.apply(.state(.recording, message: nil))

        XCTAssertEqual(model.presentationEpoch, 1)
        XCTAssertTrue(model.isVisible)
    }

    func testAmplitudeDoesNotChangePresentationEpoch() {
        let model = HudModel()

        model.apply(.state(.recording, message: nil))
        model.apply(.amplitude(0.5))

        XCTAssertEqual(model.presentationEpoch, 1)
    }

    func testRecordingToTranscribingDoesNotRestartEntryAnimation() {
        let model = HudModel()

        model.apply(.state(.recording, message: nil))
        model.apply(.state(.transcribing, message: nil))

        XCTAssertEqual(model.presentationEpoch, 1)
        XCTAssertEqual(model.state, .transcribing)
    }
```

- [ ] **Step 2: Run Swift tests and confirm RED**

Run:

```bash
cd hud
swift test --filter HudModelTests
cd ..
```

Expected: FAIL because `HudModel.presentationEpoch` is not defined.

- [ ] **Step 3: Commit RED model tests**

Run:

```bash
git add hud/Tests/VocoHUDTests/HudEventTests.swift
git commit -m "test(hud): cover recording presentation epoch"
```

## Task 2: Implement HudModel Presentation Epoch

**Files:**
- Modify: `hud/Sources/VocoHUDCore/HudModel.swift`

- [ ] **Step 1: Update HudModel**

Replace `hud/Sources/VocoHUDCore/HudModel.swift` with:

```swift
import Foundation
import SwiftUI

@MainActor
public final class HudModel: ObservableObject {
    @Published public private(set) var state: HudState = .hidden
    @Published public private(set) var amplitude: Double = 0.0
    @Published public private(set) var message: String?
    @Published public private(set) var presentationEpoch: Int = 0
    private var becameVisibleAt: Date?

    public init() {}

    public var isVisible: Bool {
        state != .hidden
    }

    public func apply(_ event: HudEvent) {
        switch event {
        case .state(let next, let message):
            let wasHidden = state == .hidden
            state = next
            self.message = message
            if next == .hidden {
                amplitude = 0.0
                self.message = nil
                becameVisibleAt = nil
            } else if wasHidden {
                presentationEpoch += 1
                becameVisibleAt = Date()
            }
        case .amplitude(let value):
            amplitude = min(max(value, 0.0), 1.0)
        }
    }

    public func entryProgress(now: Date) -> Double {
        guard let becameVisibleAt else {
            return isVisible ? 1.0 : 0.0
        }
        let elapsed = now.timeIntervalSince(becameVisibleAt)
        return min(max(elapsed / 0.28, 0.0), 1.0)
    }
}
```

- [ ] **Step 2: Run model tests and confirm GREEN**

Run:

```bash
cd hud
swift test --filter HudModelTests
cd ..
```

Expected: PASS.

- [ ] **Step 3: Commit model implementation**

Run:

```bash
git add hud/Sources/VocoHUDCore/HudModel.swift
git commit -m "feat(hud): track HUD presentation epochs"
```

## Task 3: Theme Constants Red Tests

**Files:**
- Modify: `hud/Tests/VocoHUDTests/HudEventTests.swift`

- [ ] **Step 1: Add failing HudTheme tests**

Append this test class to `hud/Tests/VocoHUDTests/HudEventTests.swift`:

```swift
final class HudThemeTests: XCTestCase {
    func testB2CompactLayoutTokens() {
        XCTAssertEqual(HudTheme.Layout.capsuleWidth, 196)
        XCTAssertEqual(HudTheme.Layout.capsuleHeight, 48)
        XCTAssertEqual(HudTheme.Layout.micGlyphSize, 22)
        XCTAssertEqual(HudTheme.Layout.waveformWidth, 58)
        XCTAssertEqual(HudTheme.Layout.waveformBarCount, 7)
    }

    func testBlackYellowGreenColorTokens() {
        XCTAssertEqual(HudTheme.ColorToken.capsule.hex, "#050607")
        XCTAssertEqual(HudTheme.ColorToken.recordingMic.hex, "#FFCC4D")
        XCTAssertEqual(HudTheme.ColorToken.waveform.hex, "#32D67A")
    }
}
```

- [ ] **Step 2: Run theme tests and confirm RED**

Run:

```bash
cd hud
swift test --filter HudThemeTests
cd ..
```

Expected: FAIL because `HudTheme` does not exist.

- [ ] **Step 3: Commit RED theme tests**

Run:

```bash
git add hud/Tests/VocoHUDTests/HudEventTests.swift
git commit -m "test(hud): cover compact HUD theme tokens"
```

## Task 4: Implement HudTheme

**Files:**
- Create: `hud/Sources/VocoHUDCore/HudTheme.swift`

- [ ] **Step 1: Create HudTheme.swift**

Create `hud/Sources/VocoHUDCore/HudTheme.swift`:

```swift
import CoreGraphics
import SwiftUI

public enum HudTheme {
    public enum Layout {
        public static let capsuleWidth: CGFloat = 196
        public static let capsuleHeight: CGFloat = 48
        public static let micGlyphSize: CGFloat = 22
        public static let waveformWidth: CGFloat = 58
        public static let waveformHeight: CGFloat = 34
        public static let waveformBarCount = 7
        public static let contentSpacing: CGFloat = 10
        public static let panelBottomOffset: CGFloat = 96
    }

    public struct ColorToken: Equatable {
        public let hex: String
        public let red: Double
        public let green: Double
        public let blue: Double
        public let opacity: Double

        public var color: Color {
            Color(red: red, green: green, blue: blue).opacity(opacity)
        }

        public static let capsule = ColorToken(
            hex: "#050607",
            red: 5.0 / 255.0,
            green: 6.0 / 255.0,
            blue: 7.0 / 255.0,
            opacity: 0.92
        )
        public static let capsuleBorder = ColorToken(
            hex: "#1B1F22",
            red: 27.0 / 255.0,
            green: 31.0 / 255.0,
            blue: 34.0 / 255.0,
            opacity: 0.95
        )
        public static let recordingMic = ColorToken(
            hex: "#FFCC4D",
            red: 255.0 / 255.0,
            green: 204.0 / 255.0,
            blue: 77.0 / 255.0,
            opacity: 1.0
        )
        public static let waveform = ColorToken(
            hex: "#32D67A",
            red: 50.0 / 255.0,
            green: 214.0 / 255.0,
            blue: 122.0 / 255.0,
            opacity: 1.0
        )
        public static let error = ColorToken(
            hex: "#FF5E57",
            red: 255.0 / 255.0,
            green: 94.0 / 255.0,
            blue: 87.0 / 255.0,
            opacity: 1.0
        )
    }
}
```

- [ ] **Step 2: Run theme tests and confirm GREEN**

Run:

```bash
cd hud
swift test --filter HudThemeTests
cd ..
```

Expected: PASS.

- [ ] **Step 3: Commit theme implementation**

Run:

```bash
git add hud/Sources/VocoHUDCore/HudTheme.swift
git commit -m "feat(hud): add compact black HUD theme"
```

## Task 5: Implement Compact Black/Yellow/Green CapsuleView

**Files:**
- Modify: `hud/Sources/VocoHUDCore/CapsuleView.swift`
- Modify: `hud/Sources/VocoHUD/main.swift`

- [ ] **Step 1: Replace CapsuleView with B2 implementation**

Replace `hud/Sources/VocoHUDCore/CapsuleView.swift` with:

```swift
import Foundation
import SwiftUI

public struct CapsuleView: View {
    @ObservedObject var model: HudModel

    public init(model: HudModel) {
        self.model = model
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date
            let entry = model.entryProgress(now: now)
            HStack(spacing: HudTheme.Layout.contentSpacing) {
                microphone(at: now)
                if model.state == .transcribing {
                    TranscribingSpinner(time: now.timeIntervalSinceReferenceDate)
                } else {
                    WaveformBars(
                        amplitude: model.amplitude,
                        state: model.state,
                        time: now.timeIntervalSinceReferenceDate
                    )
                }
            }
            .padding(.horizontal, 14)
            .frame(width: HudTheme.Layout.capsuleWidth, height: HudTheme.Layout.capsuleHeight)
            .background(HudTheme.ColorToken.capsule.color, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    HudTheme.ColorToken.capsuleBorder.color,
                    lineWidth: 1
                )
            )
            .shadow(color: Color.black.opacity(0.46), radius: 18, y: 10)
            .opacity(entry)
            .scaleEffect(0.94 + (0.06 * entry))
        }
    }

    private func microphone(at date: Date) -> some View {
        let time = date.timeIntervalSinceReferenceDate
        let recordingPulse = model.state == .recording
            ? 1.0 + (0.08 * normalizedSine(time, speed: 0.85, offset: 0))
            : 1.0
        let color: Color = model.state == .error
            ? HudTheme.ColorToken.error.color
            : HudTheme.ColorToken.recordingMic.color

        return Image(systemName: iconName)
            .font(.system(size: HudTheme.Layout.micGlyphSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(
                width: HudTheme.Layout.micGlyphSize,
                height: HudTheme.Layout.micGlyphSize
            )
            .scaleEffect(recordingPulse)
            .shadow(
                color: color.opacity(model.state == .recording ? 0.55 : 0.28),
                radius: model.state == .recording ? 9 : 5
            )
    }

    private var iconName: String {
        switch model.state {
        case .hidden, .recording: return "mic.fill"
        case .transcribing: return "mic.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

private struct WaveformBars: View {
    let amplitude: Double
    let state: HudState
    let time: TimeInterval

    var body: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<HudTheme.Layout.waveformBarCount, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 5, height: barHeight(idx))
            }
        }
        .frame(width: HudTheme.Layout.waveformWidth, height: HudTheme.Layout.waveformHeight)
    }

    private var color: Color {
        state == .error ? HudTheme.ColorToken.error.color : HudTheme.ColorToken.waveform.color
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let pattern = [0.42, 0.76, 1.0, 0.82, 0.52, 0.68, 0.46][index]
        if state == .hidden {
            return 8
        }
        if state == .transcribing {
            let moving = normalizedSine(time, speed: 0.7, offset: Double(index) * 0.55)
            return CGFloat(10.0 + moving * 18.0 * pattern)
        }
        let baseline = 4.0 + normalizedSine(time, speed: 0.72, offset: Double(index) * 0.65) * 7.0
        let boosted = max(amplitude, 0.08) * pattern * 18.0
        return CGFloat(min(max(8.0 + baseline + boosted, 8.0), 32.0))
    }
}

private struct TranscribingSpinner: View {
    let time: TimeInterval

    var body: some View {
        Circle()
            .trim(from: 0.18, to: 0.82)
            .stroke(
                HudTheme.ColorToken.waveform.color,
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .frame(width: 24, height: 24)
            .rotationEffect(.degrees((time * 360.0).truncatingRemainder(dividingBy: 360.0)))
            .shadow(color: HudTheme.ColorToken.waveform.color.opacity(0.35), radius: 6)
    }
}

private func normalizedSine(_ time: TimeInterval, speed: Double, offset: Double) -> Double {
    let phase = (time / speed + offset) * Double.pi * 2.0
    return (sin(phase) + 1.0) / 2.0
}
```

- [ ] **Step 2: Update panel content size**

In `hud/Sources/VocoHUD/main.swift`, replace the `NSPanel` `contentRect` block:

```swift
let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
```

with:

```swift
let panel = NSPanel(
    contentRect: NSRect(
        x: 0,
        y: 0,
        width: HudTheme.Layout.capsuleWidth,
        height: HudTheme.Layout.capsuleHeight
    ),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
```

In the same file, replace the bottom offset in `positionPanel()`:

```swift
let y = frame.minY + 96
```

with:

```swift
let y = frame.minY + HudTheme.Layout.panelBottomOffset
```

- [ ] **Step 3: Run Swift tests and build**

Run:

```bash
cd hud
swift test
swift build
cd ..
```

Expected: PASS; Swift tests pass and `voco-hud` builds.

- [ ] **Step 4: Commit HUD visual implementation**

Run:

```bash
git add hud/Sources/VocoHUDCore/CapsuleView.swift hud/Sources/VocoHUD/main.swift
git commit -m "feat(hud): refresh recording HUD visuals"
```

## Task 6: Rust Defaults and Long Recording Red Tests

**Files:**
- Modify: `crates/voco-config/tests/validate.rs`
- Modify: `crates/voco-asr/tests/mock_server.rs`
- Modify: `crates/voco-cli/tests/config_subcommands.rs`
- Modify: `crates/voco-daemon/src/orchestrator.rs`

- [ ] **Step 1: Add failing config default tests**

In `crates/voco-config/tests/validate.rs`, add these tests after `default_doubao_endpoint_uses_seed_asr_2_streaming_input_protocol`:

```rust
#[test]
fn default_recording_duration_supports_long_dictation() {
    assert_eq!(Config::default().recording_max_duration_secs, 300);
}

#[test]
fn default_doubao_resource_id_uses_seed_asr_2_hourly() {
    assert_eq!(
        DoubaoCreds::default().resource_id,
        "volc.seedasr.sauc.duration"
    );
}
```

- [ ] **Step 2: Update mock-server expected resource header**

In `crates/voco-asr/tests/mock_server.rs`, replace:

```rust
            .any(|h| h.starts_with("x-api-resource-id=volc.bigasr.sauc.duration")),
```

with:

```rust
            .any(|h| h.starts_with("x-api-resource-id=volc.seedasr.sauc.duration")),
```

- [ ] **Step 3: Add failing CLI fallback test**

In `crates/voco-cli/tests/config_subcommands.rs`, add this test after `set_token_message_is_masked`:

```rust
#[test]
fn set_creates_doubao_section_with_seed_asr_2_resource_id() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;

    voco(&tmp)
        .args(["config", "set", "doubao.app_id", "APP-2"])
        .assert()
        .success();

    voco(&tmp)
        .args(["config", "show"])
        .assert()
        .success()
        .stdout(predicate::str::contains(
            "endpoint = \"wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream\"",
        ))
        .stdout(predicate::str::contains(
            "resource_id = \"volc.seedasr.sauc.duration\"",
        ));

    Ok(())
}
```

- [ ] **Step 4: Add failing long recording/HUD visibility regression test**

In `crates/voco-daemon/src/orchestrator.rs`, add this helper after the `impl RecordingRunner for StopAwareRunner` block inside `mod recording_tests`:

```rust
    struct DurationCapturingRunner {
        payload: RecordingPayload,
        durations: Mutex<Vec<u32>>,
        calls: AtomicUsize,
    }

    impl DurationCapturingRunner {
        fn new() -> Self {
            Self {
                payload: RecordingPayload {
                    text: "duration final".into(),
                    segments: vec![],
                    partials: vec![],
                    logid: Some("duration-log".into()),
                    first_partial_ms: Some(90),
                    total_latency_ms: 510,
                    error_hint: None,
                },
                durations: Mutex::new(Vec::new()),
                calls: AtomicUsize::new(0),
            }
        }
    }

    #[async_trait]
    impl RecordingRunner for DurationCapturingRunner {
        async fn run_once(
            &self,
            _config: Config,
            duration_ms: u32,
            _include_partials: bool,
            stop_rx: oneshot::Receiver<()>,
            _hud: Option<crate::hud::SharedHudSink>,
        ) -> Result<RecordingPayload, SessionError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            self.durations.lock().await.push(duration_ms);
            let _ = stop_rx.await;
            Ok(self.payload.clone())
        }
    }
```

Then add this test after `recording_start_stop_sends_hud_state_sequence`:

```rust
    #[tokio::test]
    async fn recording_start_uses_long_default_and_hud_stays_visible_until_stop() {
        let runner = Arc::new(DurationCapturingRunner::new());
        let injector = Arc::new(FakeInjector::default());
        let hud = Arc::new(FakeHudSink::default());
        let orch = Orchestrator::with_runner_injector_and_hud(
            Config::default(),
            runner.clone(),
            injector,
            hud.clone(),
        );

        assert_eq!(orch.handle(Request::RecordingStart).await, Response::Ok);

        for _ in 0..10 {
            if !runner.durations.lock().await.is_empty() {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }

        assert_eq!(*runner.durations.lock().await, vec![300_000]);
        match orch.handle(Request::Status).await {
            Response::Status(status) => assert_eq!(status.state, "recording"),
            other => panic!("expected recording Status, got {other:?}"),
        }
        assert_eq!(
            *hud.events.lock().unwrap(),
            vec![crate::hud::HudEvent::state(crate::hud::HudState::Recording)]
        );

        match orch.handle(Request::RecordingStop).await {
            Response::RecordingResult { text, logid, .. } => {
                assert_eq!(text, "duration final");
                assert_eq!(logid.as_deref(), Some("duration-log"));
            }
            other => panic!("expected RecordingResult, got {other:?}"),
        }

        assert_eq!(
            *hud.events.lock().unwrap(),
            vec![
                crate::hud::HudEvent::state(crate::hud::HudState::Recording),
                crate::hud::HudEvent::state(crate::hud::HudState::Transcribing),
                crate::hud::HudEvent::state(crate::hud::HudState::Hidden),
            ]
        );
        assert_eq!(runner.calls.load(Ordering::SeqCst), 1);
    }
```

- [ ] **Step 5: Run focused Rust tests and confirm RED**

Run:

```bash
cargo test -p voco-config default_
cargo test -p voco-asr handshake_audio_final_roundtrip
cargo test -p voco-cli set_creates_doubao_section_with_seed_asr_2_resource_id
cargo test -p voco-daemon recording_start_uses_long_default_and_hud_stays_visible_until_stop
```

Expected: FAIL because defaults still use `60` and `volc.bigasr.sauc.duration`; the daemon regression test sees `60_000` instead of `300_000`.

- [ ] **Step 6: Commit RED Rust config and daemon tests**

Run:

```bash
git add crates/voco-config/tests/validate.rs crates/voco-asr/tests/mock_server.rs crates/voco-cli/tests/config_subcommands.rs crates/voco-daemon/src/orchestrator.rs
git commit -m "test(config): cover long recording and Seed ASR defaults"
```

## Task 7: Implement Rust Config Defaults

**Files:**
- Modify: `crates/voco-config/src/schema.rs`
- Modify: `crates/voco-cli/src/commands/config/wizard.rs`
- Modify: `crates/voco-cli/src/commands/config/set.rs`

- [ ] **Step 1: Update default resource ID, endpoint, and recording duration**

In `crates/voco-config/src/schema.rs`, replace:

```rust
fn default_resource_id() -> String {
    "volc.bigasr.sauc.duration".to_string()
}
```

with:

```rust
fn default_resource_id() -> String {
    "volc.seedasr.sauc.duration".to_string()
}
```

In the same file, replace:

```rust
endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel".to_string(),
```

with:

```rust
endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream".to_string(),
```

In the same file, replace:

```rust
recording_max_duration_secs: 60,
```

with:

```rust
recording_max_duration_secs: 300,
```

- [ ] **Step 2: Update config wizard fallbacks**

In `crates/voco-cli/src/commands/config/wizard.rs`, replace:

```rust
        .unwrap_or_else(|| "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel".to_string());
```

with:

```rust
        .unwrap_or_else(|| {
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream".to_string()
        });
```

In `crates/voco-cli/src/commands/config/wizard.rs`, replace:

```rust
            .unwrap_or_else(|| "volc.bigasr.sauc.duration".to_string()),
```

with:

```rust
            .unwrap_or_else(|| "volc.seedasr.sauc.duration".to_string()),
```

- [ ] **Step 3: Update config set fallbacks**

In `crates/voco-cli/src/commands/config/set.rs`, replace:

```rust
        endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel".to_string(),
```

with:

```rust
        endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream".to_string(),
```

In `crates/voco-cli/src/commands/config/set.rs`, replace:

```rust
        resource_id: "volc.bigasr.sauc.duration".to_string(),
```

with:

```rust
        resource_id: "volc.seedasr.sauc.duration".to_string(),
```

- [ ] **Step 4: Run focused Rust tests and confirm GREEN**

Run:

```bash
cargo test -p voco-config default_
cargo test -p voco-asr handshake_audio_final_roundtrip
cargo test -p voco-cli set_creates_doubao_section_with_seed_asr_2_resource_id
cargo test -p voco-daemon recording_start_uses_long_default_and_hud_stays_visible_until_stop
```

Expected: PASS.

- [ ] **Step 5: Run existing config tests**

Run:

```bash
cargo test -p voco-config
cargo test -p voco-cli --test config_subcommands
```

Expected: PASS.

- [ ] **Step 6: Commit Rust config implementation**

Run:

```bash
git add crates/voco-config/src/schema.rs crates/voco-cli/src/commands/config/wizard.rs crates/voco-cli/src/commands/config/set.rs
git commit -m "feat(config): default to long recording and Seed ASR 2"
```

## Task 8: Update Local User Config

**Files:**
- No repository files.
- Mutates: `~/.config/voco/config.toml`

- [ ] **Step 1: Set local recording duration**

Run:

```bash
target/debug/voco config set recording_max_duration_secs 300
```

Expected: exit 0 and stdout contains:

```text
recording_max_duration_secs = 300
```

- [ ] **Step 2: Set local Doubao resource ID to Seed ASR 2.0 hourly**

Run:

```bash
target/debug/voco config set doubao.resource_id volc.seedasr.sauc.duration
```

Expected: exit 0 and stdout contains:

```text
doubao.resource_id = volc.seedasr.sauc.duration
```

- [ ] **Step 3: Set local Doubao endpoint to Seed ASR 2.0 streaming input**

Run:

```bash
target/debug/voco config set doubao.endpoint wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream
```

Expected: exit 0 and stdout contains:

```text
doubao.endpoint = wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream
```

- [ ] **Step 4: Verify local config after endpoint update**

Run:

```bash
target/debug/voco config show
```

Expected: output includes:

```text
recording_max_duration_secs = 300
resource_id = "volc.seedasr.sauc.duration"
endpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream"
```

## Task 9: Final Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-05-04-voco-hud-feedback-refresh.md`

- [ ] **Step 1: Run Swift checks**

Run:

```bash
cd hud
swift test
swift build
cd ..
```

Expected: PASS.

- [ ] **Step 2: Run Rust formatting**

Run:

```bash
cargo fmt --all --check
```

Expected: PASS.

- [ ] **Step 3: Run Rust tests**

Run:

```bash
cargo test --workspace
```

Expected: PASS. Live Doubao network and microphone tests remain ignored unless explicitly enabled.

- [ ] **Step 4: Run Rust clippy**

Run:

```bash
cargo clippy --workspace --all-targets -- -D warnings
```

Expected: PASS.

- [ ] **Step 5: Run doctor with local config**

Run:

```bash
target/debug/voco doctor
```

Expected: Doubao credentials and Doubao handshake pass with `resource_id = volc.seedasr.sauc.duration`; daemon may warn if not running.

- [ ] **Step 6: Manual HUD smoke**

Run:

```bash
target/debug/voco daemon restart
target/debug/voco status
```

Then manually:

- Focus Notes/TextEdit.
- Press Right Command once.
- Verify HUD appears immediately as a compact black capsule with yellow mic and green waveform.
- Speak continuously for at least 75 seconds.
- Verify HUD remains visible and recording continues until the second Right Command press.
- Press Right Command again.
- Verify HUD switches to transcribing animation.
- Verify final text injects and HUD hides only after completion.

If HUD hides or recording stops before the second Right Command press, do not mark verification passed. Collect evidence with:

```bash
target/debug/voco status
target/debug/voco daemon logs -n 200
```

Expected when the bug is fixed: status remains `recording` during the 75-second speaking window; logs do not show `max duration reached`, `recording task stopped`, `server timeout`, or a hidden HUD state before manual stop.

- [ ] **Step 7: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 8: Record verification results in this plan**

Append a note under Task 9:

```markdown
Verification note (2026-05-04):

- `cd hud && swift test && swift build && cd ..` passed.
- `cargo fmt --all --check` passed.
- `cargo test --workspace` passed; live network/microphone tests remained ignored as designed.
- `cargo clippy --workspace --all-targets -- -D warnings` passed.
- Local config was updated to `recording_max_duration_secs = 300`.
- Local config was updated to `doubao.resource_id = "volc.seedasr.sauc.duration"`.
- Local config was updated to `doubao.endpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream"` after live probes showed `bigmodel` returned HTTP 400 and `bigmodel_async` timed out for the doctor empty-audio check.
- `target/debug/voco doctor` passed Doubao credentials and handshake with Seed ASR 2.0 resource ID and `bigmodel_nostream`.
- Manual HUD smoke passed: the HUD appeared on first press, stayed visible during at least 75 seconds of continuous speech, switched to transcribing only after manual stop, and hid only after completion; or it was blocked by a named environment condition.
- `git diff --check` passed.
```

Actual verification note (2026-05-04):

- `cd hud && swift test && swift build && cd ..` passed.
- `cargo fmt --all --check` passed.
- `cargo test --workspace` passed; live network/microphone tests remained ignored as designed.
- `cargo clippy --workspace --all-targets -- -D warnings` passed.
- `packaging/build_app_bundle.sh --profile release` passed and produced `target/Voco.app`.
- `target/release/voco app install --app-bundle target/Voco.app` passed and installed `/Users/zhangxiaolong/Applications/Voco.app`.
- Local config was updated to `recording_max_duration_secs = 300`.
- Local config was updated to `doubao.resource_id = "volc.seedasr.sauc.duration"`.
- Local config was updated to `doubao.endpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream"` after live probes showed `bigmodel` returned HTTP 400 and `bigmodel_async` timed out for the doctor empty-audio check.
- `target/release/voco doctor` passed with `10 ok / 0 warn / 0 fail / 2 skip`.
- Live long-recording bug test passed: IPC `RecordingStart` held daemon status at `recording` at 15, 30, 45, 60, and 75 seconds, then `RecordingStop` returned `recording_result` with `total_latency_ms = 72034`.
- Log scan found no `max duration reached`, `recording task stopped`, `server timeout`, `HTTP error`, or `Bad Request` during the long-recording test.
- Visual HUD styling was verified by Swift code/tests/build, not by an interactive screen capture in this terminal session.
- `git diff --check` passed.

- [ ] **Step 9: Commit verification update**

Run:

```bash
git add docs/superpowers/plans/2026-05-04-voco-hud-feedback-refresh.md
git commit -m "docs: mark HUD feedback refresh verification"
```

- [ ] **Step 10: Finish branch**

Use `superpowers:finishing-a-development-branch`.

Expected: present merge/PR/keep/discard options after all automated gates pass and the manual HUD smoke is either passed or explicitly recorded as blocked.

## Self-Review

- Spec coverage: black/yellow/green HUD, B2 196x48 sizing, immediate first-press animation, no recording hide without explicit hidden, daemon long-recording regression coverage, 300-second default recording duration, Seed ASR 2.0 `resource_id`, Seed ASR 2.0 `bigmodel_nostream` endpoint, local config update, and final verification are covered.
- Scope control: no menu bar UI, settings UI, transcript display, new IPC channel, signing/notarization, automatic silence stop, or `bigmodel_async` endpoint switch is included.
- Type consistency: `HudModel.presentationEpoch`, `HudTheme.Layout`, `HudTheme.ColorToken`, `recording_max_duration_secs`, and `doubao.resource_id` names match existing code or are introduced in earlier tasks before use.
