# Voco Phase 5 HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hidden SwiftUI/AppKit HUD helper that appears only while Voco is recording/transcribing/erroring and animates waveform bars from real microphone amplitude.

**Architecture:** Keep the Phase 4 Rust daemon as the owner of hotkey/audio/ASR/injection. Add a separate `voco-hud` Swift executable under `hud/`; the daemon starts it hidden and writes newline-delimited JSON events to its stdin. HUD failure is fail-soft: recording and text injection continue without HUD.

**Tech Stack:** Rust/tokio/tracing/serde, existing `voco-audio` amplitude `watch<f32>`, Swift Package Manager, SwiftUI, AppKit `NSPanel`.

---

## File Structure

- Create `hud/Package.swift` — Swift package manifest for executable `voco-hud` and tests.
- Create `hud/Sources/VocoHUD/main.swift` — minimal executable bootstrap in Task 1, then AppKit application entry point, stdin event loop, and panel setup in Task 2.
- Create `hud/Sources/VocoHUDCore/HudEvent.swift` — JSON event parser and `HudState`.
- Create `hud/Sources/VocoHUDCore/HudModel.swift` — `ObservableObject` state/amplitude model.
- Create `hud/Sources/VocoHUDCore/CapsuleView.swift` — SwiftUI Capsule Glass UI.
- Create `hud/Tests/VocoHUDTests/HudEventTests.swift` — parser unit tests.
- Create `crates/voco-daemon/src/hud.rs` — Rust HUD event types, sink trait, process bridge, noop sink, test sink.
- Modify `crates/voco-daemon/src/lib.rs` — export `hud` module.
- Modify `crates/voco-daemon/src/main.rs` — spawn hidden HUD helper, pass sink to `Orchestrator`, hide/close at shutdown.
- Modify `crates/voco-daemon/src/orchestrator.rs` — inject `HudSink`, send state transitions, keep `_internal_record` headless.
- Modify `crates/voco-daemon/src/session.rs` — forward real amplitude while a recording session runs.
- Modify `crates/voco-daemon/Cargo.toml` — add dev dependency only if tests need `assert_cmd`; prefer std-only tests.
- Modify `README.md` or `docs/superpowers/plans/2026-05-03-voco-phase-5-hud.md` only for manual verification notes.

---

## Task 1: Swift Package + Event Parser

**Files:**
- Create: `hud/Package.swift`
- Create: `hud/Sources/VocoHUD/main.swift`
- Create: `hud/Sources/VocoHUDCore/HudEvent.swift`
- Create: `hud/Tests/VocoHUDTests/HudEventTests.swift`

- [ ] **Step 1: Create Swift package manifest**

Create `hud/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VocoHUD",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "voco-hud", targets: ["VocoHUD"])
    ],
    targets: [
        .target(
            name: "VocoHUDCore",
            path: "Sources/VocoHUDCore"
        ),
        .executableTarget(
            name: "VocoHUD",
            dependencies: ["VocoHUDCore"],
            path: "Sources/VocoHUD"
        ),
        .testTarget(
            name: "VocoHUDTests",
            dependencies: ["VocoHUDCore"],
            path: "Tests/VocoHUDTests"
        )
    ]
)
```

Create `hud/Sources/VocoHUD/main.swift` with a minimal executable source file so SwiftPM can load the executable target while Task 1 focuses on parser tests:

```swift
import VocoHUDCore
```

- [ ] **Step 2: Write failing parser tests**

Create `hud/Tests/VocoHUDTests/HudEventTests.swift`:

```swift
import XCTest
@testable import VocoHUDCore

final class HudEventTests: XCTestCase {
    func testDecodesStateEventWithoutMessage() throws {
        let event = try HudEvent.decodeLine(#"{"type":"state","state":"recording"}"#)
        XCTAssertEqual(event, .state(.recording, message: nil))
    }

    func testDecodesStateEventWithMessage() throws {
        let event = try HudEvent.decodeLine(#"{"type":"state","state":"error","message":"microphone unavailable"}"#)
        XCTAssertEqual(event, .state(.error, message: "microphone unavailable"))
    }

    func testDecodesAmplitudeEvent() throws {
        let event = try HudEvent.decodeLine(#"{"type":"amplitude","value":0.42}"#)
        XCTAssertEqual(event, .amplitude(0.42))
    }

    func testRejectsUnknownEventType() {
        XCTAssertThrowsError(try HudEvent.decodeLine(#"{"type":"unknown"}"#))
    }
}
```

- [ ] **Step 3: Run parser tests and confirm failure**

Run:

```bash
cd hud && swift test --filter HudEventTests
```

Expected: FAIL because `HudEvent` does not exist yet.

- [ ] **Step 4: Implement `HudEvent` parser**

Create `hud/Sources/VocoHUDCore/HudEvent.swift`:

```swift
import Foundation

public enum HudState: String, Codable, Equatable {
    case hidden
    case recording
    case transcribing
    case error
}

public enum HudEvent: Equatable {
    case state(HudState, message: String?)
    case amplitude(Double)

    private enum CodingKeys: String, CodingKey {
        case type
        case state
        case message
        case value
    }

    private struct RawEvent: Decodable {
        let type: String
        let state: HudState?
        let message: String?
        let value: Double?
    }

    public static func decodeLine(_ line: String) throws -> HudEvent {
        let data = Data(line.utf8)
        let raw = try JSONDecoder().decode(RawEvent.self, from: data)
        switch raw.type {
        case "state":
            guard let state = raw.state else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "state event missing state"))
            }
            return .state(state, message: raw.message)
        case "amplitude":
            guard let value = raw.value else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "amplitude event missing value"))
            }
            return .amplitude(value)
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unknown HUD event type \(raw.type)"))
        }
    }
}
```

- [ ] **Step 5: Run Swift tests**

Run:

```bash
cd hud && swift test --filter HudEventTests
```

Expected: PASS, 4 tests.

- [ ] **Step 6: Commit**

Run:

```bash
git add .gitignore hud/Package.swift hud/Sources/VocoHUD/main.swift hud/Sources/VocoHUDCore/HudEvent.swift hud/Tests/VocoHUDTests/HudEventTests.swift docs/superpowers/plans/2026-05-03-voco-phase-5-hud.md
git commit -m "feat(hud): add Swift HUD event parser"
```

---

## Task 2: Swift Capsule Glass HUD Helper

**Files:**
- Create: `hud/Sources/VocoHUDCore/HudModel.swift`
- Create: `hud/Sources/VocoHUDCore/CapsuleView.swift`
- Modify: `hud/Sources/VocoHUD/main.swift`
- Modify: `hud/Tests/VocoHUDTests/HudEventTests.swift`

- [ ] **Step 1: Add model tests for clamping and state transitions**

Append to `hud/Tests/VocoHUDTests/HudEventTests.swift`:

```swift
@MainActor
final class HudModelTests: XCTestCase {
    func testAmplitudeIsClamped() {
        let model = HudModel()
        model.apply(.amplitude(1.8))
        XCTAssertEqual(model.amplitude, 1.0)
        model.apply(.amplitude(-0.4))
        XCTAssertEqual(model.amplitude, 0.0)
    }

    func testHiddenStateClearsVisibility() {
        let model = HudModel()
        model.apply(.state(.recording, message: nil))
        XCTAssertTrue(model.isVisible)
        model.apply(.state(.hidden, message: nil))
        XCTAssertFalse(model.isVisible)
    }
}
```

- [ ] **Step 2: Run model tests and confirm failure**

Run:

```bash
cd hud && swift test --filter HudModelTests
```

Expected: FAIL because `HudModel` does not exist yet.

- [ ] **Step 3: Implement `HudModel`**

Create `hud/Sources/VocoHUDCore/HudModel.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
public final class HudModel: ObservableObject {
    @Published public private(set) var state: HudState = .hidden
    @Published public private(set) var amplitude: Double = 0.0
    @Published public private(set) var message: String?

    public init() {}

    public var isVisible: Bool {
        state != .hidden
    }

    public func apply(_ event: HudEvent) {
        switch event {
        case .state(let next, let message):
            state = next
            self.message = message
            if next == .hidden {
                amplitude = 0.0
                self.message = nil
            }
        case .amplitude(let value):
            amplitude = min(max(value, 0.0), 1.0)
        }
    }
}
```

- [ ] **Step 4: Implement Capsule Glass view**

Create `hud/Sources/VocoHUDCore/CapsuleView.swift`:

```swift
import SwiftUI

public struct CapsuleView: View {
    @ObservedObject var model: HudModel

    public init(model: HudModel) {
        self.model = model
    }

    public var body: some View {
        HStack(spacing: 14) {
            statusDot
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 24, height: 24)
            WaveformBars(amplitude: model.amplitude, state: model.state)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 260, height: 56)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.18), radius: 24, y: 12)
    }

    private var foreground: Color {
        model.state == .error ? .red : Color(red: 0.16, green: 0.18, blue: 0.22)
    }

    private var iconName: String {
        switch model.state {
        case .hidden, .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(model.state == .error ? Color.red : Color.yellow)
            .frame(width: 10, height: 10)
            .opacity(model.state == .transcribing ? 0.45 : 1.0)
    }
}

private struct WaveformBars: View {
    let amplitude: Double
    let state: HudState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 5, height: barHeight(idx))
                    .animation(.easeOut(duration: 0.12), value: amplitude)
            }
        }
        .frame(width: 70, height: 32)
    }

    private var color: Color {
        state == .error ? .red : Color(red: 0.16, green: 0.18, blue: 0.22)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        if state == .transcribing {
            return [10, 18, 26, 18, 10, 14, 20][index]
        }
        let pattern = [0.45, 0.72, 1.0, 0.82, 0.55, 0.68, 0.5][index]
        let scaled = 8.0 + max(amplitude, 0.06) * pattern * 24.0
        return CGFloat(min(max(scaled, 8.0), 32.0))
    }
}
```

- [ ] **Step 5: Implement hidden NSPanel app and stdin reader**

Create `hud/Sources/VocoHUD/main.swift`:

```swift
import AppKit
import SwiftUI
import VocoHUDCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = HudModel()
    private var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        startInputReader()
    }

    private func createPanel() {
        let view = CapsuleView(model: model)
        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.orderOut(nil)
        self.panel = panel
    }

    private func startInputReader() {
        DispatchQueue.global(qos: .userInitiated).async {
            while let line = readLine() {
                do {
                    let event = try HudEvent.decodeLine(line)
                    DispatchQueue.main.async {
                        self.apply(event)
                    }
                } catch {
                    fputs("voco-hud: decode error: \(error)\n", stderr)
                }
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    private func apply(_ event: HudEvent) {
        model.apply(event)
        switch event {
        case .state(.hidden, _):
            panel?.orderOut(nil)
        case .state(.error, _):
            positionPanel()
            panel?.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.model.state == .error {
                    self.model.apply(.state(.hidden, message: nil))
                    self.panel?.orderOut(nil)
                }
            }
        case .state:
            positionPanel()
            panel?.orderFrontRegardless()
        case .amplitude:
            break
        }
    }

    private func positionPanel() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + 96
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 6: Run Swift tests and build**

Run:

```bash
cd hud && swift test && swift build
```

Expected: tests pass, `voco-hud` builds under `hud/.build/debug/voco-hud`.

- [ ] **Step 7: Manual smoke the helper**

Run:

```bash
cd hud
(printf '{"type":"state","state":"recording"}\n'; sleep 1; printf '{"type":"amplitude","value":0.8}\n'; sleep 1; printf '{"type":"state","state":"transcribing"}\n'; sleep 1; printf '{"type":"state","state":"hidden"}\n') | .build/debug/voco-hud
```

Expected: HUD window is hidden at launch, appears after `recording`, bars move after amplitude, changes to transcribing, then hides.

- [ ] **Step 8: Commit**

Run:

```bash
git add hud/Sources/VocoHUDCore/HudModel.swift hud/Sources/VocoHUDCore/CapsuleView.swift hud/Sources/VocoHUD/main.swift hud/Tests/VocoHUDTests/HudEventTests.swift
git commit -m "feat(hud): add hidden Capsule Glass helper"
```

---

## Task 3: Rust HUD Event Model and Sink

**Files:**
- Create: `crates/voco-daemon/src/hud.rs`
- Modify: `crates/voco-daemon/src/lib.rs`

- [ ] **Step 1: Write Rust event serialization tests**

Create `crates/voco-daemon/src/hud.rs` with tests first:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn state_event_serializes_as_swift_jsonl_shape() {
        let line = event_to_json_line(&HudEvent::state(HudState::Recording)).unwrap();
        assert_eq!(line, "{\"type\":\"state\",\"state\":\"recording\"}\n");
    }

    #[test]
    fn error_event_includes_message() {
        let line = event_to_json_line(&HudEvent::error("microphone unavailable")).unwrap();
        assert_eq!(
            line,
            "{\"type\":\"state\",\"state\":\"error\",\"message\":\"microphone unavailable\"}\n"
        );
    }

    #[test]
    fn amplitude_event_is_clamped_before_serializing() {
        let line = event_to_json_line(&HudEvent::amplitude(1.4)).unwrap();
        assert_eq!(line, "{\"type\":\"amplitude\",\"value\":1.0}\n");
    }
}
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cargo test -p voco-daemon hud::
```

Expected: FAIL because `HudEvent`, `HudState`, and `event_to_json_line` are not implemented.

- [ ] **Step 3: Implement event model and sink trait**

Replace `crates/voco-daemon/src/hud.rs` content with:

```rust
use serde::{Deserialize, Serialize};
use std::io::Write;
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Arc, Mutex};
use thiserror::Error;
use tracing::warn;

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
}

impl HudEvent {
    pub fn state(state: HudState) -> Self {
        Self::State { state, message: None }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self::State { state: HudState::Error, message: Some(message.into()) }
    }

    pub fn amplitude(value: f32) -> Self {
        Self::Amplitude { value: clamp_amplitude(value) }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HudState {
    Hidden,
    Recording,
    Transcribing,
    Error,
}

#[derive(Debug, Error)]
pub enum HudError {
    #[error("serialize HUD event: {0}")]
    Serialize(#[from] serde_json::Error),
    #[error("spawn HUD helper: {0}")]
    Spawn(std::io::Error),
    #[error("write HUD event: {0}")]
    Write(std::io::Error),
    #[error("HUD helper missing")]
    MissingHelper,
}

pub trait HudSink: Send + Sync {
    fn send(&self, event: HudEvent) -> Result<(), HudError>;
}

pub type SharedHudSink = Arc<dyn HudSink>;

#[derive(Debug, Default)]
pub struct NoopHudSink;

impl HudSink for NoopHudSink {
    fn send(&self, _event: HudEvent) -> Result<(), HudError> {
        Ok(())
    }
}

pub fn noop_hud_sink() -> SharedHudSink {
    Arc::new(NoopHudSink)
}

pub fn event_to_json_line(event: &HudEvent) -> Result<String, HudError> {
    let mut line = serde_json::to_string(event)?;
    line.push('\n');
    Ok(line)
}

pub fn clamp_amplitude(value: f32) -> f32 {
    value.clamp(0.0, 1.0)
}
```

- [ ] **Step 4: Export the module**

Modify `crates/voco-daemon/src/lib.rs`:

```rust
pub mod hud;
pub mod orchestrator;
pub mod paths;
pub mod reload;
pub mod session;
pub mod state;
pub mod stats;
```

- [ ] **Step 5: Run event tests**

Run:

```bash
cargo test -p voco-daemon hud::
```

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git add crates/voco-daemon/src/hud.rs crates/voco-daemon/src/lib.rs
git commit -m "feat(daemon): add HUD event model"
```

---

## Task 4: Rust HUD Process Bridge

**Files:**
- Modify: `crates/voco-daemon/src/hud.rs`

- [ ] **Step 1: Add writer sink tests**

Append tests to `crates/voco-daemon/src/hud.rs`:

```rust
#[test]
fn writer_sink_writes_newline_delimited_events() {
    let output = Arc::new(Mutex::new(Vec::<u8>::new()));
    let sink = TestWriterHudSink::new(output.clone());
    sink.send(HudEvent::state(HudState::Recording)).unwrap();
    sink.send(HudEvent::amplitude(0.25)).unwrap();

    let bytes = output.lock().unwrap().clone();
    assert_eq!(
        String::from_utf8(bytes).unwrap(),
        "{\"type\":\"state\",\"state\":\"recording\"}\n{\"type\":\"amplitude\",\"value\":0.25}\n"
    );
}

#[test]
fn missing_helper_resolution_returns_none() {
    let temp = tempfile::tempdir().unwrap();
    assert_eq!(locate_hud_binary_from(None, temp.path(), None), None);
}
```

- [ ] **Step 2: Implement test writer sink**

Add below `noop_hud_sink()` in `hud.rs`:

```rust
#[cfg(test)]
pub struct TestWriterHudSink {
    output: Arc<Mutex<Vec<u8>>>,
}

#[cfg(test)]
impl TestWriterHudSink {
    pub fn new(output: Arc<Mutex<Vec<u8>>>) -> Self {
        Self { output }
    }
}

#[cfg(test)]
impl HudSink for TestWriterHudSink {
    fn send(&self, event: HudEvent) -> Result<(), HudError> {
        let line = event_to_json_line(&event)?;
        self.output.lock().unwrap().extend_from_slice(line.as_bytes());
        Ok(())
    }
}
```

- [ ] **Step 3: Implement production process bridge**

Add to `hud.rs`:

```rust
pub struct HudProcess {
    inner: Mutex<HudProcessInner>,
}

struct HudProcessInner {
    child: Child,
    stdin: Option<ChildStdin>,
    enabled: bool,
    warned: bool,
}

impl HudProcess {
    pub fn spawn_default() -> Result<Self, HudError> {
        let Some(path) = locate_hud_binary() else {
            return Err(HudError::MissingHelper);
        };
        let mut child = Command::new(&path)
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(HudError::Spawn)?;
        let stdin = child.stdin.take();
        let process = Self {
            inner: Mutex::new(HudProcessInner {
                child,
                stdin,
                enabled: true,
                warned: false,
            }),
        };
        process.send(HudEvent::state(HudState::Hidden))?;
        Ok(process)
    }
}

impl HudSink for HudProcess {
    fn send(&self, event: HudEvent) -> Result<(), HudError> {
        let line = event_to_json_line(&event)?;
        let mut inner = self.inner.lock().unwrap();
        if !inner.enabled {
            return Ok(());
        }
        let Some(stdin) = inner.stdin.as_mut() else {
            inner.enabled = false;
            return Ok(());
        };
        if let Err(err) = stdin.write_all(line.as_bytes()).and_then(|_| stdin.flush()) {
            inner.enabled = false;
            if !inner.warned {
                inner.warned = true;
                warn!(error = %err, "HUD helper write failed; disabling HUD");
            }
            return Err(HudError::Write(err));
        }
        Ok(())
    }
}

impl Drop for HudProcess {
    fn drop(&mut self) {
        let mut inner = self.inner.lock().unwrap();
        let _ = inner.stdin.take();
        let deadline = std::time::Instant::now() + std::time::Duration::from_millis(300);
        while std::time::Instant::now() < deadline {
            if matches!(inner.child.try_wait(), Ok(Some(_))) {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
        let _ = inner.child.kill();
        let _ = inner.child.wait();
    }
}
```

- [ ] **Step 4: Implement binary resolution**

Add to `hud.rs`:

```rust
pub fn default_hud_sink() -> SharedHudSink {
    match HudProcess::spawn_default() {
        Ok(process) => Arc::new(process),
        Err(err) => {
            warn!(error = %err, "HUD helper unavailable; continuing without HUD");
            noop_hud_sink()
        }
    }
}

fn locate_hud_binary() -> Option<PathBuf> {
    let current_exe = std::env::current_exe().ok();
    let exe_dir = current_exe.as_deref().and_then(std::path::Path::parent);
    let current_dir = std::env::current_dir().ok()?;
    let path = std::env::var_os("PATH");
    locate_hud_binary_from(exe_dir, &current_dir, path.as_deref())
}

fn locate_hud_binary_from(
    exe_dir: Option<&std::path::Path>,
    current_dir: &std::path::Path,
    path: Option<&std::ffi::OsStr>,
) -> Option<PathBuf> {
    if let Some(dir) = exe_dir {
        let candidate = dir.join("voco-hud");
        if candidate.exists() {
            return Some(candidate);
        }
    }
    let dev = current_dir.join("hud/.build/debug/voco-hud");
    if dev.exists() {
        return Some(dev);
    }
    let Some(path) = path else {
        return None;
    };
    for dir in std::env::split_paths(path) {
        let candidate = dir.join("voco-hud");
        if candidate.exists() {
            return Some(candidate);
        }
    }
    None
}
```

- [ ] **Step 5: Run HUD bridge tests**

Run:

```bash
cargo test -p voco-daemon hud::
```

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git add crates/voco-daemon/src/hud.rs
git commit -m "feat(daemon): add HUD process bridge"
```

---

## Task 5: Wire HUD Lifecycle and State Transitions

**Files:**
- Modify: `crates/voco-daemon/src/main.rs`
- Modify: `crates/voco-daemon/src/orchestrator.rs`

- [ ] **Step 1: Add orchestrator mock HUD test**

In `crates/voco-daemon/src/orchestrator.rs`, extend `recording_tests` with:

```rust
#[derive(Default)]
struct FakeHudSink {
    events: StdMutex<Vec<crate::hud::HudEvent>>,
}

impl crate::hud::HudSink for FakeHudSink {
    fn send(&self, event: crate::hud::HudEvent) -> Result<(), crate::hud::HudError> {
        self.events.lock().unwrap().push(event);
        Ok(())
    }
}

#[tokio::test]
async fn recording_start_stop_sends_hud_state_sequence() {
    let runner = Arc::new(StopAwareRunner::new());
    let injector = Arc::new(FakeInjector::default());
    let hud = Arc::new(FakeHudSink::default());
    let orch = Orchestrator::with_runner_injector_and_hud(
        Config::default(),
        runner,
        injector,
        hud.clone(),
    );

    assert_eq!(orch.handle(Request::RecordingStart).await, Response::Ok);
    let _ = orch.handle(Request::RecordingStop).await;

    assert_eq!(
        *hud.events.lock().unwrap(),
        vec![
            crate::hud::HudEvent::state(crate::hud::HudState::Recording),
            crate::hud::HudEvent::state(crate::hud::HudState::Transcribing),
            crate::hud::HudEvent::state(crate::hud::HudState::Hidden),
        ]
    );
}

#[tokio::test]
async fn recording_once_does_not_show_hud() {
    let runner = Arc::new(FakeRecordingRunner::new(std::time::Duration::ZERO));
    let injector = Arc::new(FakeInjector::default());
    let hud = Arc::new(FakeHudSink::default());
    let orch = Orchestrator::with_runner_injector_and_hud(
        Config::default(),
        runner,
        injector,
        hud.clone(),
    );

    let _ = orch.handle(Request::RecordingOnce { duration_ms: 100, include_partials: false }).await;
    assert!(hud.events.lock().unwrap().is_empty());
}
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cargo test -p voco-daemon recording_start_stop_sends_hud_state_sequence
cargo test -p voco-daemon recording_once_does_not_show_hud
```

Expected: both commands FAIL because orchestrator has no HUD sink yet.

- [ ] **Step 3: Add HUD sink to orchestrator constructors**

Modify `Orchestrator` fields:

```rust
hud: crate::hud::SharedHudSink,
```

Modify constructors:

```rust
pub fn new(config: Config) -> Self {
    Self::with_runner(config, default_recording_runner())
}

pub fn new_with_hud(config: Config, hud: crate::hud::SharedHudSink) -> Self {
    Self::with_parts(config, default_recording_runner(), default_text_injector(), hud)
}

fn with_runner(config: Config, recording_runner: Arc<dyn RecordingRunner>) -> Self {
    Self::with_parts(
        config,
        recording_runner,
        default_text_injector(),
        crate::hud::noop_hud_sink(),
    )
}

fn with_parts(
    config: Config,
    recording_runner: Arc<dyn RecordingRunner>,
    text_injector: Arc<dyn TextInjector>,
    hud: crate::hud::SharedHudSink,
) -> Self {
    let backend = backend_label(&config);
    Self {
        started_at: Instant::now(),
        state: Arc::new(RwLock::new(DaemonState::Idle)),
        config: Arc::new(RwLock::new(config)),
        stats: Arc::new(RwLock::new(Stats::new(backend))),
        shutdown: Arc::new(Notify::new()),
        recording_runner,
        text_injector,
        active_recording: Arc::new(Mutex::new(None)),
        hud,
    }
}
```

Update the existing test-only constructors and add a HUD-specific constructor:

```rust
#[cfg(test)]
fn with_recording_runner(config: Config, recording_runner: Arc<dyn RecordingRunner>) -> Self {
    Self::with_runner(config, recording_runner)
}

#[cfg(test)]
fn with_runner_and_injector(
    config: Config,
    recording_runner: Arc<dyn RecordingRunner>,
    text_injector: Arc<dyn TextInjector>,
) -> Self {
    Self::with_parts(
        config,
        recording_runner,
        text_injector,
        crate::hud::noop_hud_sink(),
    )
}

#[cfg(test)]
fn with_runner_injector_and_hud(
    config: Config,
    recording_runner: Arc<dyn RecordingRunner>,
    text_injector: Arc<dyn TextInjector>,
    hud: crate::hud::SharedHudSink,
) -> Self {
    Self::with_parts(config, recording_runner, text_injector, hud)
}
```

- [ ] **Step 4: Send state events only for start/stop flow**

In `handle_recording_start`, after state is set to `Recording`, send:

```rust
let _ = self.hud.send(crate::hud::HudEvent::state(crate::hud::HudState::Recording));
```

In `take_active_recording`, after state is set to `Transcribing`, send:

```rust
let _ = self.hud.send(crate::hud::HudEvent::state(crate::hud::HudState::Transcribing));
```

Pass `self.hud.clone()` to `finalize_recording_result` for start/stop flow and a noop sink for `RecordingOnce`.

Change `finalize_recording_result` signature:

```rust
async fn finalize_recording_result(
    result: Result<RecordingPayload, SessionError>,
    state: Arc<RwLock<DaemonState>>,
    stats: Arc<RwLock<Stats>>,
    config: Arc<RwLock<Config>>,
    injector: Arc<dyn TextInjector>,
    inject: bool,
    hud: crate::hud::SharedHudSink,
    show_hud: bool,
) -> Response
```

On success after stats update and before returning:

```rust
if show_hud {
    let _ = hud.send(crate::hud::HudEvent::state(crate::hud::HudState::Hidden));
}
```

On error:

```rust
if show_hud {
    let _ = hud.send(crate::hud::HudEvent::error(err.to_string()));
    spawn_delayed_hud_hide(hud.clone());
}
```

Add helper:

```rust
fn spawn_delayed_hud_hide(hud: crate::hud::SharedHudSink) {
    tokio::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        let _ = hud.send(crate::hud::HudEvent::state(crate::hud::HudState::Hidden));
    });
}
```

- [ ] **Step 5: Wire daemon main to spawn hidden helper**

Modify `crates/voco-daemon/src/main.rs`:

```rust
use voco_daemon::{default_socket_path, hud, logs_dir, Orchestrator};
```

Before creating the orchestrator:

```rust
let hud_sink = hud::default_hud_sink();
let orch = Arc::new(Orchestrator::new_with_hud(cfg, hud_sink.clone()));
```

Before final log on shutdown:

```rust
let _ = hud_sink.send(hud::HudEvent::state(hud::HudState::Hidden));
drop(hud_sink);
```

- [ ] **Step 6: Run orchestrator tests**

Run:

```bash
cargo test -p voco-daemon recording_start_stop_sends_hud_state_sequence
cargo test -p voco-daemon recording_once_does_not_show_hud
```

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```bash
git add crates/voco-daemon/src/main.rs crates/voco-daemon/src/orchestrator.rs
git commit -m "feat(daemon): send HUD state transitions"
```

---

## Task 6: Forward Real Amplitude During Recording

**Files:**
- Modify: `crates/voco-daemon/src/session.rs`
- Modify: `crates/voco-daemon/src/orchestrator.rs`

- [ ] **Step 1: Add amplitude forwarding test**

In `crates/voco-daemon/src/session.rs` tests, add:

```rust
#[derive(Default)]
struct FakeHudSink {
    events: std::sync::Mutex<Vec<crate::hud::HudEvent>>,
}

impl crate::hud::HudSink for FakeHudSink {
    fn send(&self, event: crate::hud::HudEvent) -> Result<(), crate::hud::HudError> {
        self.events.lock().unwrap().push(event);
        Ok(())
    }
}

#[tokio::test]
async fn forwards_clamped_amplitude_to_hud() {
    let (pcm_tx, pcm_rx) = mpsc::channel(4);
    let (amp_tx, amp_rx) = tokio::sync::watch::channel(0.0_f32);
    let hud = std::sync::Arc::new(FakeHudSink::default());
    pcm_tx.send(vec![1, 2, 3]).await.unwrap();
    let (stop_tx, stop_rx) = oneshot::channel();
    let session = RecordingSession::from_parts_with_amplitude(
        pcm_rx,
        Box::new(MockBackend { feed_calls: 0, failure: MockFailure::None }),
        Some(amp_rx),
    );

    let run = tokio::spawn(session.run_with_hud(1_000, true, stop_rx, Some(hud.clone())));
    amp_tx.send(1.4).unwrap();
    tokio::time::sleep(std::time::Duration::from_millis(30)).await;
    let _ = stop_tx.send(());
    let _ = run.await.unwrap().unwrap();

    assert!(hud.events.lock().unwrap().contains(&crate::hud::HudEvent::amplitude(1.0)));
}
```

- [ ] **Step 2: Run test and confirm failure**

Run:

```bash
cargo test -p voco-daemon forwards_clamped_amplitude_to_hud
```

Expected: FAIL because `from_parts_with_amplitude` and `run_with_hud` do not exist.

- [ ] **Step 3: Add amplitude receiver support**

Modify `PcmSource`:

```rust
enum PcmSource {
    Audio(voco_audio::Session),
    Receiver {
        pcm_rx: mpsc::Receiver<Vec<i16>>,
        amplitude_rx: Option<tokio::sync::watch::Receiver<f32>>,
    },
}
```

Update `recv`:

```rust
match self {
    PcmSource::Audio(session) => session.pcm_rx.recv().await,
    PcmSource::Receiver { pcm_rx, .. } => pcm_rx.recv().await,
}
```

Add `amplitude_rx` helper:

```rust
fn amplitude_rx(&self) -> Option<tokio::sync::watch::Receiver<f32>> {
    match self {
        PcmSource::Audio(session) => Some(session.amplitude_rx.clone()),
        PcmSource::Receiver { amplitude_rx, .. } => amplitude_rx.clone(),
    }
}
```

Update `from_parts` to wrap `Receiver { amplitude_rx: None }`, and add:

```rust
pub fn from_parts_with_amplitude(
    pcm_rx: mpsc::Receiver<Vec<i16>>,
    backend: Box<dyn AsrBackend>,
    amplitude_rx: Option<tokio::sync::watch::Receiver<f32>>,
) -> Self {
    Self {
        pcm: PcmSource::Receiver { pcm_rx, amplitude_rx },
        backend,
        started_at: Instant::now(),
        first_partial_at: None,
        last_partial_text: None,
        partials: Vec::new(),
    }
}
```

- [ ] **Step 4: Add `run_with_hud` and amplitude task**

Keep existing `run` as a wrapper:

```rust
pub async fn run(
    self,
    duration_ms: u32,
    include_partials: bool,
    stop_rx: oneshot::Receiver<()>,
) -> Result<RecordingPayload, SessionError> {
    self.run_with_hud(duration_ms, include_partials, stop_rx, None).await
}
```

Add:

```rust
pub async fn run_with_hud(
    self,
    duration_ms: u32,
    include_partials: bool,
    stop_rx: oneshot::Receiver<()>,
    hud: Option<crate::hud::SharedHudSink>,
) -> Result<RecordingPayload, SessionError> {
    let amplitude_task = self
        .pcm
        .amplitude_rx()
        .zip(hud)
        .map(|(rx, hud)| spawn_amplitude_forwarder(rx, hud));

    let result = self.run_loop(duration_ms, include_partials, stop_rx).await;
    if let Some(task) = amplitude_task {
        task.abort();
    }
    result
}
```

Extract the current body of `run` into a private helper named `run_loop`:

```rust
async fn run_loop(
    mut self,
    duration_ms: u32,
    include_partials: bool,
    mut stop_rx: oneshot::Receiver<()>,
) -> Result<RecordingPayload, SessionError> {
    self.backend.start().await?;
    let timeout = tokio::time::sleep(Duration::from_millis(duration_ms as u64));
    tokio::pin!(timeout);
    let terminal = loop {
        tokio::select! {
            frame = self.pcm.recv() => {
                let Some(frame) = frame else {
                    break TerminalReason::AudioEnded;
                };
                match self.backend.feed(&frame).await {
                    Ok(Some(partial)) => self.record_partial(partial, include_partials),
                    Ok(None) => {}
                    Err(err) => {
                        break TerminalReason::BackendError(err.to_string());
                    }
                }
            }
            _ = &mut stop_rx => {
                break TerminalReason::Stopped;
            }
            _ = &mut timeout => {
                break TerminalReason::Timeout;
            }
        }
    };

    if let TerminalReason::BackendError(message) = &terminal {
        return Ok(self.partial_payload(Some(message.clone())));
    }

    let final_result = match self.backend.stop().await {
        Ok(final_result) => final_result,
        Err(err) => {
            return Ok(self.partial_payload(Some(err.to_string())));
        }
    };
    let finished_at = Instant::now();
    Ok(RecordingPayload {
        text: final_result.text,
        segments: final_result
            .segments
            .into_iter()
            .map(|segment| Segment {
                text: segment.text,
                start_ms: segment.start_ms,
                end_ms: segment.end_ms,
                definite: segment.definite,
            })
            .collect(),
        partials: self.partials,
        logid: final_result.logid,
        first_partial_ms: self
            .first_partial_at
            .map(|at| elapsed_ms(self.started_at, at)),
        total_latency_ms: elapsed_ms(self.started_at, finished_at),
        error_hint: terminal.error_hint(),
    })
}
```

Keep `run_with_hud` as the only function that starts/stops the amplitude forwarding task; the wrapper shape above guarantees the task is aborted after every normal `run_loop` return.

Add module helper:

```rust
fn spawn_amplitude_forwarder(
    mut rx: tokio::sync::watch::Receiver<f32>,
    hud: crate::hud::SharedHudSink,
) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(std::time::Duration::from_millis(16));
        loop {
            tokio::select! {
                changed = rx.changed() => {
                    if changed.is_err() {
                        break;
                    }
                }
                _ = ticker.tick() => {
                    let value = crate::hud::clamp_amplitude(*rx.borrow_and_update());
                    let _ = hud.send(crate::hud::HudEvent::amplitude(value));
                }
            }
        }
    })
}
```

- [ ] **Step 5: Pass HUD sink from real recording runner**

Change `RecordingRunner::run_once` signature in `orchestrator.rs`:

```rust
async fn run_once(
    &self,
    config: Config,
    duration_ms: u32,
    include_partials: bool,
    stop_rx: oneshot::Receiver<()>,
    hud: Option<crate::hud::SharedHudSink>,
) -> Result<RecordingPayload, SessionError>;
```

Update `RealRecordingRunner`:

```rust
RecordingSession::start_from_config(&config)?
    .run_with_hud(duration_ms, include_partials, stop_rx, hud)
    .await
```

Update mock runners to accept `_hud` and ignore it.

In `handle_recording_once`, pass `None`.

In `handle_recording_start`, pass `Some(self.hud.clone())`.

- [ ] **Step 6: Run amplitude and daemon tests**

Run:

```bash
cargo test -p voco-daemon forwards_clamped_amplitude_to_hud
cargo test -p voco-daemon recording_
```

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```bash
git add crates/voco-daemon/src/session.rs crates/voco-daemon/src/orchestrator.rs
git commit -m "feat(daemon): forward recording amplitude to HUD"
```

---

## Task 7: Build and Lifecycle Integration

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-05-03-voco-phase-5-hud.md`

- [x] **Step 1: Add developer run notes**

Append to `README.md`:

```markdown
## Phase 5 HUD Development

Build the Swift HUD helper before running the daemon from source:

```bash
cd hud
swift build
cd ..
cargo build --workspace
```

During development, `voco-daemon` resolves `hud/.build/debug/voco-hud` and starts it hidden. The HUD window remains hidden while idle and appears only while recording, transcribing, or showing an error.
```

- [x] **Step 2: Build all artifacts**

Run:

```bash
cd hud && swift build && cd ..
cargo build --workspace
```

Expected: Swift helper builds and Rust workspace builds.

- [x] **Step 3: Run automated checks**

Run:

```bash
cd hud && swift test && cd ..
cargo fmt --all --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

Expected: all pass.

Task 7 note (2026-05-03):
- `cd hud && swift build && cd .. && cargo build --workspace` passed.
- `cd hud && swift test` was initially environment-blocked with CommandLineTools XCTest unavailable. After the Xcode developer directory/license setup was corrected, `cd hud && swift test` passed: 7 tests, 0 failures.
- Rust checks passed separately: `cargo fmt --all --check`, `cargo test --workspace`, and `cargo clippy --workspace --all-targets -- -D warnings`.
- Initial lifecycle smoke across separate tool invocations produced a false negative because the tool runner cleaned up the detached child process after the command exited. A reliable same-shell lifecycle smoke passed: `daemon start` returned pid `38019`, `status` reported idle, `pgrep -x voco-daemon` returned `38019`, `pgrep -x voco-hud` returned `38020`, `daemon stop` succeeded, and a final `pgrep -x` check found no daemon or HUD helper remaining.
- The lifecycle smoke verified process lifecycle only. I did not visually verify that no HUD window is visible while idle.
- Manual hotkey HUD smoke was not visually verified.

- [x] **Step 4: Manual lifecycle smoke (process lifecycle only)**

Run:

```bash
target/debug/voco daemon stop || true
target/debug/voco daemon start
target/debug/voco status
pgrep -af voco-hud
```

Expected:
- daemon starts;
- `voco status` reports idle;
- `voco-hud` process exists;
- no daemon or HUD helper remains after stop.

- [ ] **Step 4b: Idle HUD visual smoke**

Expected: no HUD window is visible while idle.

- [ ] **Step 5: Manual hotkey HUD smoke**

Manual steps:

```text
1. Focus Notes/TextEdit.
2. Press Right Command once.
3. Verify Capsule Glass HUD appears near bottom center.
4. Speak.
5. Verify waveform bars move.
6. Press Right Command again.
7. Verify HUD switches to transcribing and then hides after text injection.
8. Run `target/debug/voco status` and confirm one successful session was recorded.
```

- [x] **Step 6: Stop daemon and verify helper exits**

Run:

```bash
target/debug/voco daemon stop
pgrep -af voco-hud || true
```

Expected: no `voco-hud` helper remains.

- [x] **Step 7: Commit docs**

Run:

```bash
git add README.md docs/superpowers/plans/2026-05-03-voco-phase-5-hud.md
git commit -m "docs: document Phase 5 HUD development workflow"
```

---

## Task 8: Final Verification and Branch Completion

**Files:**
- Modify: `docs/superpowers/plans/2026-05-03-voco-phase-5-hud.md`

- [x] **Step 1: Run final gates**

Run:

```bash
cd hud && swift test && swift build && cd ..
cargo fmt --all --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo build --workspace --release
git diff --check
```

Expected: all commands exit 0.

Task 8 note (2026-05-03):
- `cd hud && swift test && swift build && cd ..` passed: Swift HUD tests executed 7 tests with 0 failures, then the Swift helper build completed.
- `cargo fmt --all --check` passed.
- `cargo test --workspace` passed: all Rust workspace tests passed; live network/microphone tests remained ignored as designed.
- `cargo clippy --workspace --all-targets -- -D warnings` passed.
- `cargo build --workspace --release` passed.
- `git diff --check` passed.
- Manual hotkey HUD visual smoke and idle HUD visual smoke remain unchecked.

- [x] **Step 2: Mark verification checkboxes complete**

Edit this plan's verification rows for the commands that passed. Leave manual rows unchecked until verified on the machine.

- [ ] **Step 3: Commit verification updates**

Run:

```bash
git add docs/superpowers/plans/2026-05-03-voco-phase-5-hud.md
git commit -m "docs: mark Phase 5 HUD verification"
```

- [ ] **Step 4: Finish branch**

Use `superpowers:finishing-a-development-branch`.

Present options:

```text
1. Merge to master locally.
2. Open a PR.
3. Leave branch for manual review.
```

Do not merge without explicit user confirmation.
