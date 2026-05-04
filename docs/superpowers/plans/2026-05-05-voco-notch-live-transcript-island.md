# Voco Notch Live Transcript Island Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a top-center Dynamic Island style live transcript HUD that displays Doubao streaming ASR partials in real time.

**Architecture:** Reuse the existing Doubao `Partial` output and existing daemon-to-HUD JSONL pipe. Add a new `transcript` HUD event in Rust, forward every recording partial to the HUD independent of `include_partials`, decode it in Swift, and render a second transparent top panel with a collapsed/expanded notch island while preserving the existing bottom HUD.

**Tech Stack:** Rust, Tokio, serde JSONL, SwiftUI, AppKit `NSPanel`, XCTest, existing Voco HUD helper package.

---

## File Structure

- Modify: `crates/voco-daemon/src/hud.rs`
  - Own the Rust HUD event contract.
  - Add `HudEvent::Transcript { text, stable_prefix_len }`.
  - Add serialization tests for the JSONL shape consumed by Swift.

- Modify: `crates/voco-daemon/src/session.rs`
  - Forward ASR partials to the HUD in recording sessions.
  - Keep `include_partials` limited to final IPC history, not live HUD display.
  - Add tests for transcript forwarding and HUD send failure behavior.

- Modify: `hud/Sources/VocoHUDCore/HudEvent.swift`
  - Decode `{"type":"transcript", ...}` JSONL events.

- Modify: `hud/Sources/VocoHUDCore/HudModel.swift`
  - Store live transcript text and stable prefix byte length.
  - Split UTF-8 byte stable prefix safely for Swift rendering.
  - Clear transcript on hidden state.

- Modify: `hud/Sources/VocoHUDCore/HudTheme.swift`
  - Add top island layout tokens and transcript color tokens.

- Create: `hud/Sources/VocoHUDCore/TranscriptIslandView.swift`
  - Render option B: top notch island collapsed when no transcript, expanded to two-line caption when transcript exists.

- Modify: `hud/Sources/VocoHUD/main.swift`
  - Keep the current bottom panel.
  - Add a second transparent top panel using `TranscriptIslandView`.
  - Position it at screen top center near `visibleFrame.maxY`.

- Modify: `hud/Tests/VocoHUDTests/HudEventTests.swift`
  - Add decoding, model, UTF-8 splitting, and top layout token tests.

---

### Task 1: Add Rust HUD Transcript Event Contract

**Files:**
- Modify: `crates/voco-daemon/src/hud.rs`

- [ ] **Step 1: Write failing serialization tests**

Add these tests inside `#[cfg(test)] mod tests` in `crates/voco-daemon/src/hud.rs`, after `amplitude_event_is_clamped_before_serializing`:

```rust
#[test]
fn transcript_event_serializes_as_swift_jsonl_shape() {
    let line = event_to_json_line(&HudEvent::transcript("你好世界", 6)).unwrap();
    assert_eq!(
        line,
        "{\"type\":\"transcript\",\"text\":\"你好世界\",\"stable_prefix_len\":6}\n"
    );
}

#[test]
fn transcript_event_preserves_empty_text() {
    let line = event_to_json_line(&HudEvent::transcript("", 0)).unwrap();
    assert_eq!(
        line,
        "{\"type\":\"transcript\",\"text\":\"\",\"stable_prefix_len\":0}\n"
    );
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
cargo test -p voco-daemon hud::tests::transcript_event_serializes_as_swift_jsonl_shape
```

Expected: FAIL with an error like `no variant or associated item named transcript found for enum HudEvent`.

- [ ] **Step 3: Add the transcript event variant**

In `crates/voco-daemon/src/hud.rs`, change `HudEvent` to:

```rust
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum HudEvent {
    State {
        state: HudState,
        #[serde(skip_serializing_if = "Option::is_none")]
        message: Option<String>,
    },
    Amplitude {
        value: f32,
    },
    Transcript {
        text: String,
        stable_prefix_len: usize,
    },
}
```

Add this constructor inside `impl HudEvent`, after `amplitude`:

```rust
pub fn transcript(text: impl Into<String>, stable_prefix_len: usize) -> Self {
    Self::Transcript {
        text: text.into(),
        stable_prefix_len,
    }
}
```

- [ ] **Step 4: Run the focused tests and verify they pass**

Run:

```bash
cargo test -p voco-daemon hud::tests::transcript_event
```

Expected: both transcript event tests PASS.

- [ ] **Step 5: Run all HUD event tests**

Run:

```bash
cargo test -p voco-daemon hud::tests
```

Expected: existing state/amplitude/HUD process tests still PASS.

- [ ] **Step 6: Commit Task 1**

Run:

```bash
git add crates/voco-daemon/src/hud.rs
git commit -m "Add HUD transcript event contract"
```

---

### Task 2: Forward ASR Partials To HUD During Recording

**Files:**
- Modify: `crates/voco-daemon/src/session.rs`

- [ ] **Step 1: Write failing session tests**

In `crates/voco-daemon/src/session.rs`, add this test sink in the test module after `FakeHudSink`:

```rust
#[derive(Default)]
struct FailingHudSink;

impl crate::hud::HudSink for FailingHudSink {
    fn send(&self, _event: crate::hud::HudEvent) -> Result<(), crate::hud::HudError> {
        Err(crate::hud::HudError::Write(
            std::io::ErrorKind::BrokenPipe.into(),
        ))
    }
}
```

Add these tests after `run_omits_partials_when_not_requested`:

```rust
#[tokio::test]
async fn forwards_partials_to_hud_even_when_partial_history_is_disabled() {
    let (pcm_tx, pcm_rx) = mpsc::channel(4);
    pcm_tx.send(vec![1, 2, 3]).await.unwrap();
    drop(pcm_tx);
    let (_stop_tx, stop_rx) = oneshot::channel();
    let hud = std::sync::Arc::new(FakeHudSink::default());
    let session = RecordingSession::from_parts(pcm_rx, Box::new(MockBackend::new()));

    let payload = session
        .run_with_hud(1_000, false, stop_rx, Some(hud.clone()))
        .await
        .unwrap();

    assert!(payload.partials.is_empty());
    assert!(hud
        .events
        .lock()
        .unwrap()
        .contains(&crate::hud::HudEvent::transcript("partial-1", 1)));
}

#[tokio::test]
async fn hud_transcript_send_failure_does_not_fail_recording() {
    let (pcm_tx, pcm_rx) = mpsc::channel(4);
    pcm_tx.send(vec![1, 2, 3]).await.unwrap();
    drop(pcm_tx);
    let (_stop_tx, stop_rx) = oneshot::channel();
    let hud = std::sync::Arc::new(FailingHudSink::default());
    let session = RecordingSession::from_parts(pcm_rx, Box::new(MockBackend::new()));

    let payload = session
        .run_with_hud(1_000, false, stop_rx, Some(hud))
        .await
        .unwrap();

    assert_eq!(payload.text, "final text");
    assert!(payload.partials.is_empty());
}
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```bash
cargo test -p voco-daemon session::tests::forwards_partials_to_hud_even_when_partial_history_is_disabled session::tests::hud_transcript_send_failure_does_not_fail_recording
```

Expected: FAIL because `record_partial` does not forward transcript events to the HUD yet.

- [ ] **Step 3: Preserve HUD sink for both amplitude and transcript**

In `RecordingSession::run_with_hud`, replace the amplitude task setup and `run_loop` call with:

```rust
let amplitude_task = self
    .pcm
    .amplitude_rx()
    .zip(hud.clone())
    .map(|(rx, hud)| spawn_amplitude_forwarder(rx, hud));

let result = self
    .run_loop(duration_ms, include_partials, stop_rx, hud)
    .await;
if let Some(task) = amplitude_task {
    task.abort();
}
result
```

Change the `run_loop` signature to:

```rust
async fn run_loop(
    mut self,
    duration_ms: u32,
    include_partials: bool,
    mut stop_rx: oneshot::Receiver<()>,
    hud: Option<crate::hud::SharedHudSink>,
) -> Result<RecordingPayload, SessionError> {
```

- [ ] **Step 4: Pass HUD into `record_partial`**

In `run_loop`, replace:

```rust
Ok(Some(partial)) => self.record_partial(partial, include_partials),
```

with:

```rust
Ok(Some(partial)) => self.record_partial(partial, include_partials, hud.as_ref()),
```

Replace `record_partial` with:

```rust
fn record_partial(
    &mut self,
    partial: voco_asr::Partial,
    include_partials: bool,
    hud: Option<&crate::hud::SharedHudSink>,
) {
    let at = Instant::now();
    if self.first_partial_at.is_none() {
        self.first_partial_at = Some(at);
    }

    let text = partial.text;
    let stable_prefix_len = partial.stable_prefix_len;

    if let Some(hud) = hud {
        if let Err(err) = hud.send(crate::hud::HudEvent::transcript(
            text.clone(),
            stable_prefix_len,
        )) {
            warn!(error = %err, "failed to send HUD transcript event");
        }
    }

    self.last_partial_text = Some(text.clone());
    if include_partials {
        self.partials.push(PartialSnapshot {
            at_ms: elapsed_ms(self.started_at, at),
            text,
            stable_prefix_len,
        });
    }
}
```

- [ ] **Step 5: Run focused session tests**

Run:

```bash
cargo test -p voco-daemon session::tests::forwards_partials_to_hud_even_when_partial_history_is_disabled session::tests::hud_transcript_send_failure_does_not_fail_recording
```

Expected: both tests PASS.

- [ ] **Step 6: Run all daemon tests**

Run:

```bash
cargo test -p voco-daemon
```

Expected: all daemon tests PASS, including existing recording lifecycle tests.

- [ ] **Step 7: Commit Task 2**

Run:

```bash
git add crates/voco-daemon/src/session.rs
git commit -m "Forward ASR partials to HUD"
```

---

### Task 3: Decode And Store Transcript Events In Swift

**Files:**
- Modify: `hud/Tests/VocoHUDTests/HudEventTests.swift`
- Modify: `hud/Sources/VocoHUDCore/HudEvent.swift`
- Modify: `hud/Sources/VocoHUDCore/HudModel.swift`

- [ ] **Step 1: Write failing Swift event/model tests**

Add this test to `HudEventTests` after `testDecodesAmplitudeEvent`:

```swift
func testDecodesTranscriptEvent() throws {
    let event = try HudEvent.decodeLine(#"{"type":"transcript","text":"你好世界","stable_prefix_len":6}"#)
    XCTAssertEqual(event, .transcript(text: "你好世界", stablePrefixLen: 6))
}
```

Add these tests to `HudModelTests` after `testAmplitudeDoesNotChangePresentationEpoch`:

```swift
func testTranscriptDoesNotChangePresentationEpoch() {
    let model = HudModel()

    model.apply(.state(.recording, message: nil))
    model.apply(.transcript(text: "你好世界", stablePrefixLen: 6))

    XCTAssertEqual(model.presentationEpoch, 1)
    XCTAssertEqual(model.transcriptText, "你好世界")
    XCTAssertEqual(model.stablePrefixLen, 6)
}

func testHiddenStateClearsTranscript() {
    let model = HudModel()

    model.apply(.state(.recording, message: nil))
    model.apply(.transcript(text: "你好世界", stablePrefixLen: 6))
    model.apply(.state(.hidden, message: nil))

    XCTAssertEqual(model.transcriptText, "")
    XCTAssertEqual(model.stablePrefixLen, 0)
}

func testTranscriptDisplaySplitsUtf8StablePrefix() {
    let model = HudModel()

    model.apply(.transcript(text: "你好世界", stablePrefixLen: 6))

    XCTAssertEqual(model.transcriptDisplay.stable, "你好")
    XCTAssertEqual(model.transcriptDisplay.live, "世界")
}

func testTranscriptDisplayFallsBackToCharacterBoundaryForInvalidUtf8Prefix() {
    let model = HudModel()

    model.apply(.transcript(text: "你好世界", stablePrefixLen: 7))

    XCTAssertEqual(model.transcriptDisplay.stable, "你好")
    XCTAssertEqual(model.transcriptDisplay.live, "世界")
}
```

- [ ] **Step 2: Run focused Swift tests and verify they fail**

Run:

```bash
cd hud && swift test --filter HudEventTests/testDecodesTranscriptEvent
cd hud && swift test --filter HudModelTests/testTranscript
```

Expected: FAIL because `.transcript`, `transcriptText`, `stablePrefixLen`, and `transcriptDisplay` do not exist yet.

- [ ] **Step 3: Add Swift transcript decoding**

In `hud/Sources/VocoHUDCore/HudEvent.swift`, replace the enum and raw event with:

```swift
public enum HudEvent: Equatable {
    case state(HudState, message: String?)
    case amplitude(Double)
    case transcript(text: String, stablePrefixLen: Int)

    private enum CodingKeys: String, CodingKey {
        case type
        case state
        case message
        case value
        case text
        case stablePrefixLen = "stable_prefix_len"
    }

    private struct RawEvent: Decodable {
        let type: String
        let state: HudState?
        let message: String?
        let value: Double?
        let text: String?
        let stablePrefixLen: Int?
    }
```

In `decodeLine`, add this case after `amplitude`:

```swift
case "transcript":
    guard let text = raw.text else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "transcript event missing text"))
    }
    guard let stablePrefixLen = raw.stablePrefixLen else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "transcript event missing stable_prefix_len"))
    }
    return .transcript(text: text, stablePrefixLen: stablePrefixLen)
```

- [ ] **Step 4: Add transcript model state and safe UTF-8 splitting**

In `hud/Sources/VocoHUDCore/HudModel.swift`, add this public value type above `HudModel`:

```swift
public struct TranscriptDisplay: Equatable {
    public let stable: String
    public let live: String
}
```

Add these published properties inside `HudModel`:

```swift
@Published public private(set) var transcriptText: String = ""
@Published public private(set) var stablePrefixLen: Int = 0
```

Add this computed property inside `HudModel`:

```swift
public var hasTranscript: Bool {
    !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

public var transcriptDisplay: TranscriptDisplay {
    Self.splitTranscript(text: transcriptText, stablePrefixLen: stablePrefixLen)
}
```

In `.state(.hidden)`, clear transcript state:

```swift
transcriptText = ""
stablePrefixLen = 0
```

Add transcript handling to `apply(_:)`:

```swift
case .transcript(let text, let stablePrefixLen):
    transcriptText = text
    self.stablePrefixLen = max(0, stablePrefixLen)
```

Add this helper at the end of `HudModel`:

```swift
private static func splitTranscript(text: String, stablePrefixLen: Int) -> TranscriptDisplay {
    guard stablePrefixLen > 0, !text.isEmpty else {
        return TranscriptDisplay(stable: "", live: text)
    }

    var index = text.startIndex
    var bytes = 0
    while index < text.endIndex {
        let next = text.index(after: index)
        let charByteCount = text[index..<next].utf8.count
        if bytes + charByteCount > stablePrefixLen {
            break
        }
        bytes += charByteCount
        index = next
    }

    return TranscriptDisplay(
        stable: String(text[..<index]),
        live: String(text[index...])
    )
}
```

- [ ] **Step 5: Run Swift focused tests**

Run:

```bash
cd hud && swift test --filter HudEventTests/testDecodesTranscriptEvent
cd hud && swift test --filter HudModelTests/testTranscript
```

Expected: transcript decoding and model tests PASS.

- [ ] **Step 6: Run all Swift tests**

Run:

```bash
cd hud && swift test
```

Expected: all Swift tests PASS.

- [ ] **Step 7: Commit Task 3**

Run:

```bash
git add hud/Tests/VocoHUDTests/HudEventTests.swift hud/Sources/VocoHUDCore/HudEvent.swift hud/Sources/VocoHUDCore/HudModel.swift
git commit -m "Decode HUD transcript events"
```

---

### Task 4: Add Top Island Layout Tokens

**Files:**
- Modify: `hud/Tests/VocoHUDTests/HudEventTests.swift`
- Modify: `hud/Sources/VocoHUDCore/HudTheme.swift`

- [ ] **Step 1: Write failing layout token test**

Add this test to `HudThemeTests`:

```swift
func testNotchTranscriptIslandLayoutTokens() {
    XCTAssertEqual(HudTheme.Layout.notchCollapsedWidth, 250)
    XCTAssertEqual(HudTheme.Layout.notchCollapsedHeight, 44)
    XCTAssertEqual(HudTheme.Layout.notchExpandedWidth, 520)
    XCTAssertEqual(HudTheme.Layout.notchExpandedHeight, 86)
    XCTAssertEqual(HudTheme.Layout.notchShadowPadding, 24)
    XCTAssertEqual(HudTheme.Layout.notchPanelWidth, HudTheme.Layout.notchExpandedWidth + HudTheme.Layout.notchShadowPadding * 2)
    XCTAssertEqual(HudTheme.Layout.notchPanelHeight, HudTheme.Layout.notchExpandedHeight + HudTheme.Layout.notchShadowPadding * 2)
    XCTAssertEqual(HudTheme.Layout.notchTopOffset, 8)
    XCTAssertEqual(HudTheme.Layout.transcriptFontSize, 17)
    XCTAssertEqual(HudTheme.Layout.transcriptLineLimit, 2)
}
```

Add these color assertions to `testBlackYellowGreenColorTokens`:

```swift
XCTAssertEqual(HudTheme.ColorToken.transcriptStable.hex, "#F8F1D4")
XCTAssertEqual(HudTheme.ColorToken.transcriptLive.hex, "#8DFFB5")
```

- [ ] **Step 2: Run the token test and verify it fails**

Run:

```bash
cd hud && swift test --filter HudThemeTests/testNotchTranscriptIslandLayoutTokens
```

Expected: FAIL because the new layout tokens do not exist.

- [ ] **Step 3: Add top island layout tokens**

In `hud/Sources/VocoHUDCore/HudTheme.swift`, add these constants inside `HudTheme.Layout`, after the existing bottom HUD layout constants:

```swift
public static let notchCollapsedWidth: CGFloat = 250
public static let notchCollapsedHeight: CGFloat = 44
public static let notchExpandedWidth: CGFloat = 520
public static let notchExpandedHeight: CGFloat = 86
public static let notchShadowPadding: CGFloat = 24
public static let notchPanelWidth: CGFloat = notchExpandedWidth + notchShadowPadding * 2
public static let notchPanelHeight: CGFloat = notchExpandedHeight + notchShadowPadding * 2
public static let notchTopOffset: CGFloat = 8
public static let transcriptFontSize: CGFloat = 17
public static let transcriptStatusFontSize: CGFloat = 13
public static let transcriptLineLimit = 2
```

Add these color tokens inside `HudTheme.ColorToken`, after `waveform`:

```swift
public static let transcriptStable = ColorToken(
    hex: "#F8F1D4",
    red: 248.0 / 255.0,
    green: 241.0 / 255.0,
    blue: 212.0 / 255.0,
    opacity: 1.0
)
public static let transcriptLive = ColorToken(
    hex: "#8DFFB5",
    red: 141.0 / 255.0,
    green: 255.0 / 255.0,
    blue: 181.0 / 255.0,
    opacity: 1.0
)
```

- [ ] **Step 4: Run Swift theme tests**

Run:

```bash
cd hud && swift test --filter HudThemeTests
```

Expected: all theme tests PASS.

- [ ] **Step 5: Commit Task 4**

Run:

```bash
git add hud/Tests/VocoHUDTests/HudEventTests.swift hud/Sources/VocoHUDCore/HudTheme.swift
git commit -m "Add notch transcript island tokens"
```

---

### Task 5: Implement The Swift Transcript Island View

**Files:**
- Create: `hud/Sources/VocoHUDCore/TranscriptIslandView.swift`

- [ ] **Step 1: Create the top transcript island view**

Create `hud/Sources/VocoHUDCore/TranscriptIslandView.swift` with:

```swift
import SwiftUI

public struct TranscriptIslandView: View {
    @ObservedObject var model: HudModel

    public init(model: HudModel) {
        self.model = model
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date
            let hasTranscript = model.hasTranscript
            let width = hasTranscript
                ? HudTheme.Layout.notchExpandedWidth
                : HudTheme.Layout.notchCollapsedWidth
            let height = hasTranscript
                ? HudTheme.Layout.notchExpandedHeight
                : HudTheme.Layout.notchCollapsedHeight
            let cornerRadius = hasTranscript ? 28.0 : HudTheme.Layout.notchCollapsedHeight / 2.0

            ZStack {
                islandContent(time: now.timeIntervalSinceReferenceDate, hasTranscript: hasTranscript)
                    .padding(.horizontal, hasTranscript ? 20 : 16)
                    .frame(width: width, height: height)
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(HudTheme.ColorToken.capsule.color)
                            .shadow(color: Color.black.opacity(0.34), radius: 12, y: 5)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(HudTheme.ColorToken.capsuleBorder.color, lineWidth: 1)
                    )
                    .animation(.spring(response: 0.24, dampingFraction: 0.86), value: hasTranscript)
            }
            .frame(width: HudTheme.Layout.notchPanelWidth, height: HudTheme.Layout.notchPanelHeight)
            .background(Color.clear)
        }
    }

    @ViewBuilder
    private func islandContent(time: TimeInterval, hasTranscript: Bool) -> some View {
        if hasTranscript {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    statusLabel
                    Spacer(minLength: 12)
                    TranscriptMiniWaveform(amplitude: model.amplitude, time: time)
                }
                transcriptLine
            }
        } else {
            HStack(spacing: HudTheme.Layout.contentSpacing) {
                statusLabel
                Spacer(minLength: 6)
                TranscriptMiniWaveform(amplitude: model.amplitude, time: time)
            }
        }
    }

    private var statusLabel: some View {
        Text(HudTheme.Layout.statusLabelText)
            .font(.system(size: HudTheme.Layout.transcriptStatusFontSize, weight: .semibold))
            .foregroundStyle(HudTheme.ColorToken.recordingMic.color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .shadow(color: HudTheme.ColorToken.recordingMic.color.opacity(0.24), radius: 4)
    }

    private var transcriptLine: some View {
        let display = model.transcriptDisplay
        return (Text(display.stable).foregroundStyle(HudTheme.ColorToken.transcriptStable.color)
            + Text(display.live).foregroundStyle(HudTheme.ColorToken.transcriptLive.color))
            .font(.system(size: HudTheme.Layout.transcriptFontSize, weight: .semibold))
            .lineLimit(HudTheme.Layout.transcriptLineLimit)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TranscriptMiniWaveform: View {
    let amplitude: Double
    let time: TimeInterval

    var body: some View {
        HStack(spacing: HudTheme.Layout.waveformBarSpacing) {
            ForEach(0..<HudTheme.Layout.waveformBarCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: HudTheme.Layout.waveformBarWidth / 2.0)
                    .fill(HudTheme.ColorToken.waveform.color)
                    .frame(width: HudTheme.Layout.waveformBarWidth, height: barHeight(index))
            }
        }
        .frame(width: HudTheme.Layout.waveformWidth, height: HudTheme.Layout.waveformHeight)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let pattern = [0.40, 0.70, 1.0, 0.78, 0.48, 0.62, 0.42][index]
        let baseline = 3.0 + normalizedTranscriptSine(time, speed: 0.78, offset: Double(index) * 0.65) * 5.0
        let boosted = max(amplitude, 0.06) * pattern * 12.0
        return CGFloat(min(max(6.0 + baseline + boosted, 6.0), 26.0))
    }
}

private func normalizedTranscriptSine(_ time: TimeInterval, speed: Double, offset: Double) -> Double {
    let phase = (time / speed + offset) * Double.pi * 2.0
    return (sin(phase) + 1.0) / 2.0
}
```

- [ ] **Step 2: Run Swift build and fix compile issues only**

Run:

```bash
cd hud && swift build
```

Expected: build PASS. If Swift complains about `ObservedObject` initializer visibility or numeric type inference, adjust the code without changing behavior.

- [ ] **Step 3: Run Swift tests**

Run:

```bash
cd hud && swift test
```

Expected: all tests PASS.

- [ ] **Step 4: Commit Task 5**

Run:

```bash
git add hud/Sources/VocoHUDCore/TranscriptIslandView.swift
git commit -m "Add notch transcript island view"
```

---

### Task 6: Add A Top Transparent Panel In The HUD Helper

**Files:**
- Modify: `hud/Sources/VocoHUD/main.swift`

- [ ] **Step 1: Split the single panel into bottom and top panels**

In `AppDelegate`, replace:

```swift
private var panel: NSPanel?
```

with:

```swift
private var bottomPanel: NSPanel?
private var topPanel: NSPanel?
```

In `applicationDidFinishLaunching`, replace:

```swift
createPanel()
```

with:

```swift
createBottomPanel()
createTopPanel()
```

- [ ] **Step 2: Rename existing panel creation to bottom panel**

Rename `createPanel()` to `createBottomPanel()` and update its panel assignment:

```swift
private func createBottomPanel() {
    let view = CapsuleView(model: model)
    let hosting = NSHostingController(rootView: view)
    makeTransparent(hosting.view)
    let panel = NSPanel(
        contentRect: NSRect(
            x: 0,
            y: 0,
            width: HudTheme.Layout.panelWidth,
            height: HudTheme.Layout.panelHeight
        ),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.contentViewController = hosting
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    makeTransparent(panel.contentView)
    panel.level = .floating
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.orderOut(nil)
    self.bottomPanel = panel
}
```

- [ ] **Step 3: Add top panel creation**

Add this method after `createBottomPanel()`:

```swift
private func createTopPanel() {
    let view = TranscriptIslandView(model: model)
    let hosting = NSHostingController(rootView: view)
    makeTransparent(hosting.view)
    let panel = NSPanel(
        contentRect: NSRect(
            x: 0,
            y: 0,
            width: HudTheme.Layout.notchPanelWidth,
            height: HudTheme.Layout.notchPanelHeight
        ),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.contentViewController = hosting
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    makeTransparent(panel.contentView)
    panel.level = .floating
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.orderOut(nil)
    self.topPanel = panel
}
```

- [ ] **Step 4: Update event application behavior**

Replace `apply(_:)` with:

```swift
private func apply(_ event: HudEvent) {
    model.apply(event)
    switch event {
    case .state(.hidden, _):
        bottomPanel?.orderOut(nil)
        topPanel?.orderOut(nil)
    case .state(.error, _):
        errorGeneration += 1
        let generation = errorGeneration
        topPanel?.orderOut(nil)
        positionBottomPanel()
        bottomPanel?.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.model.state == .error && self.errorGeneration == generation {
                self.model.apply(.state(.hidden, message: nil))
                self.bottomPanel?.orderOut(nil)
                self.topPanel?.orderOut(nil)
            }
        }
    case .state:
        positionBottomPanel()
        positionTopPanel()
        bottomPanel?.orderFrontRegardless()
        topPanel?.orderFrontRegardless()
    case .amplitude:
        break
    case .transcript:
        guard model.isVisible else { return }
        positionTopPanel()
        topPanel?.orderFrontRegardless()
    }
}
```

- [ ] **Step 5: Split positioning functions**

Rename `positionPanel()` to `positionBottomPanel()` and update the local panel reference:

```swift
private func positionBottomPanel() {
    guard let panel = bottomPanel else { return }
    let screen = NSScreen.main ?? NSScreen.screens.first
    guard let frame = screen?.visibleFrame else { return }
    let size = panel.frame.size
    let x = frame.midX - size.width / 2
    let y = frame.minY + HudTheme.Layout.panelBottomOffset - HudTheme.Layout.shadowPadding
    panel.setFrameOrigin(NSPoint(x: x, y: y))
}
```

Add:

```swift
private func positionTopPanel() {
    guard let panel = topPanel else { return }
    let screen = NSScreen.main ?? NSScreen.screens.first
    guard let frame = screen?.visibleFrame else { return }
    let size = panel.frame.size
    let x = frame.midX - size.width / 2
    let y = frame.maxY - size.height + HudTheme.Layout.notchShadowPadding - HudTheme.Layout.notchTopOffset
    panel.setFrameOrigin(NSPoint(x: x, y: y))
}
```

- [ ] **Step 6: Run Swift build and tests**

Run:

```bash
cd hud && swift build && swift test
```

Expected: build and tests PASS.

- [ ] **Step 7: Commit Task 6**

Run:

```bash
git add hud/Sources/VocoHUD/main.swift
git commit -m "Show transcript island in top HUD panel"
```

---

### Task 7: Full Workspace Verification And Installed App Smoke Test

**Files:**
- No source edits expected.

- [ ] **Step 1: Run Swift verification**

Run:

```bash
cd hud && swift test && swift build
```

Expected: `13+` Swift tests PASS and Swift build exits 0.

- [ ] **Step 2: Run Rust verification**

Run:

```bash
cargo fmt --all --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

Expected: all commands exit 0.

- [ ] **Step 3: Build and install the app bundle**

Run:

```bash
./packaging/build_app_bundle.sh
./target/debug/voco app install --app-bundle ./target/Voco.app
/Users/zhangxiaolong/Applications/Voco.app/Contents/MacOS/voco daemon restart
```

Expected:

```text
ok: verified Voco.app bundle: target/Voco.app
✓ installed app bundle: /Users/zhangxiaolong/Applications/Voco.app
✓ daemon restarted via launchctl
```

- [ ] **Step 4: Trigger a controlled recording session through IPC**

Run:

```bash
ruby -rsocket -rjson -rsecurerandom -e 'path=File.expand_path("~/Library/Application Support/voco/voco.sock"); req={protocol_version:3,kind:"request",id:SecureRandom.uuid,payload:{method:"recording_start"}}.to_json; s=UNIXSocket.new(path); s.write([req.bytesize].pack("N")+req); len=s.read(4).unpack1("N"); puts s.read(len)'
```

Expected:

```json
{"protocol_version":3,"kind":"response",...,"payload":{"kind":"ok"}}
```

Then speak a sentence for at least 3 seconds and verify visually:

- Top-center island appears near the notch/menu bar.
- It starts collapsed with yellow `语音输入` and green waveform.
- It expands when partial text arrives.
- Stable text is warm white and live suffix is green.
- Bottom HUD remains visible with waveform.

- [ ] **Step 5: Stop the controlled recording session**

Run:

```bash
ruby -rsocket -rjson -rsecurerandom -e 'path=File.expand_path("~/Library/Application Support/voco/voco.sock"); req={protocol_version:3,kind:"request",id:SecureRandom.uuid,payload:{method:"recording_stop"}}.to_json; s=UNIXSocket.new(path); s.write([req.bytesize].pack("N")+req); len=s.read(4).unpack1("N"); puts s.read(len)'
```

Expected:

```json
{"protocol_version":3,"kind":"response",...,"payload":{"kind":"recording_result",...}}
```

Visual expected:

- Top island hides after stop/finalization.
- Bottom HUD hides after stop/finalization.
- `voco status` returns `state: idle`.

- [ ] **Step 6: Commit verification adjustments if any**

If Task 7 required code adjustments, commit only those adjustments:

```bash
git add crates/voco-daemon/src/hud.rs crates/voco-daemon/src/session.rs hud/Sources/VocoHUDCore/HudEvent.swift hud/Sources/VocoHUDCore/HudModel.swift hud/Sources/VocoHUDCore/HudTheme.swift hud/Sources/VocoHUDCore/TranscriptIslandView.swift hud/Sources/VocoHUD/main.swift hud/Tests/VocoHUDTests/HudEventTests.swift
git commit -m "Verify notch live transcript island"
```

If Task 7 required no source adjustments, do not create an empty commit.

---

## Self-Review Checklist

- Spec coverage: Tasks 1-2 cover Rust `transcript` event and partial forwarding; Tasks 3-6 cover Swift decode/model/top panel/view; Task 7 covers full build, install, and manual live transcript verification.
- Placeholder scan: This plan avoids unfinished markers and vague implementation instructions; every code-changing step includes concrete code.
- Type consistency: Rust uses `stable_prefix_len`; Swift decodes it as `stablePrefixLen`; model exposes `transcriptText`, `stablePrefixLen`, `hasTranscript`, and `transcriptDisplay`; `TranscriptIslandView` consumes those names.
