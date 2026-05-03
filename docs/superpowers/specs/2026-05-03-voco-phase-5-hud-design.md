---
title: Voco Phase 5 — Hidden Swift HUD Helper
date: 2026-05-03
status: design-approved
target_platform: macOS 14+
language: Rust + SwiftUI/AppKit
---

# Voco Phase 5 — HUD 设计文档

## 1. Goal

Phase 5 adds visible recording feedback without changing the already-validated Phase 4 hotkey, ASR, and injection path.

The feature is a native Swift HUD helper named `voco-hud`. The daemon starts the helper hidden, sends it state and amplitude events, and the helper shows a non-activating Capsule Glass HUD only while Voco is recording, transcribing, or briefly showing an error.

## 2. Decisions

| Topic | Decision |
|---|---|
| Process model | Keep Rust daemon and add a separate Swift `voco-hud` helper for Phase 5. |
| Helper lifecycle | `voco daemon start` starts the helper hidden; `voco daemon stop` closes daemon stdin and the helper exits. |
| Display timing | The HUD window is hidden while daemon is idle. It appears only on recording/transcribing/error states. |
| Visual style | Capsule Glass: bottom-center, non-activating `NSPanel`, translucent capsule, yellow status dot, mic glyph, waveform bars. |
| Text privacy | Do not show partial or final transcript text in Phase 5. |
| Amplitude | Forward real-time `voco-audio` amplitude to the HUD and animate waveform bars. |
| Transport | daemon writes JSON Lines events to `voco-hud` stdin. |
| Failure policy | HUD failure never blocks recording or injection; daemon logs warn and continues headless. |

## 3. Scope

In scope:
- Add a Swift executable helper under `hud/`.
- Add a Rust HUD bridge inside `voco-daemon`.
- Start `voco-hud` hidden when daemon starts.
- Send daemon state events to the HUD.
- Forward recording amplitude events at a capped cadence.
- Keep the HUD hidden while idle.
- Validate with Rust tests, `swift build`, and manual hotkey verification.

Out of scope:
- Full `Voco.app` bundle.
- `launchctl` installer.
- menu bar UI.
- settings UI.
- partial/final text display in the HUD.
- replacing CLI daemon lifecycle with app lifecycle.

## 4. User Experience

When the user runs `voco daemon start`, no window appears.

When the user presses Right Command the first time:
- daemon enters `Recording`;
- HUD fades in near the bottom center of the active display;
- yellow dot and mic glyph show active listening;
- waveform bars follow real microphone amplitude.

When the user presses Right Command the second time:
- daemon enters `Transcribing`;
- HUD remains visible;
- waveform bars freeze or switch to spinner-style motion;
- after injection completes, HUD fades out.

When recording fails:
- HUD shows a red error state for about one second;
- daemon logs the error;
- HUD hides as the daemon returns to idle.

## 5. Architecture

Phase 5 uses two processes:

```text
voco-daemon
  ├─ owns hotkey, audio, ASR, injection, IPC
  ├─ spawns voco-hud with piped stdin
  └─ writes JSONL HudEvent messages

voco-hud
  ├─ reads JSONL from stdin on a background queue
  ├─ updates HudModel on the main queue
  └─ owns hidden NSPanel + SwiftUI CapsuleView
```

This deliberately avoids introducing a second IPC socket in Phase 5. stdin gives daemon-owned lifecycle, no stale socket cleanup, and a simple failure mode: if the helper exits, writes fail and daemon continues without HUD.

## 6. HUD Event Contract

The daemon sends one JSON object per line.

```json
{"type":"state","state":"hidden"}
{"type":"state","state":"recording"}
{"type":"amplitude","value":0.42}
{"type":"state","state":"transcribing"}
{"type":"state","state":"error","message":"microphone unavailable"}
```

Rust-side event model:

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum HudEvent {
    State {
        state: HudState,
        #[serde(skip_serializing_if = "Option::is_none")]
        message: Option<String>,
    },
    Amplitude { value: f32 },
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum HudState {
    Hidden,
    Recording,
    Transcribing,
    Error,
}
```

Swift-side event model:

```swift
enum HudEvent: Decodable {
    case state(HudState, message: String?)
    case amplitude(Double)
}

enum HudState: String, Decodable {
    case hidden
    case recording
    case transcribing
    case error
}
```

The initial event after helper spawn is always `hidden`. This keeps the helper process alive without showing UI at daemon startup.

## 7. Rust Integration

Add a daemon-local HUD bridge:

```rust
pub trait HudSink: Send + Sync {
    fn send(&self, event: HudEvent) -> Result<(), HudError>;
}
```

The production implementation owns:
- `std::process::Child`
- piped `ChildStdin`
- an `enabled` flag after the first write failure

`HudBridge::spawn_from_env()` resolves `voco-hud` in this order:
1. same directory as the current daemon executable;
2. `hud/.build/debug/voco-hud` for development;
3. `PATH`.

If no helper is found, daemon logs a warn and uses `NoopHudSink`.

State hooks:
- `RecordingStart`: send `recording`.
- stop requested / max duration: send `transcribing`.
- successful injection completion: send `hidden`.
- recording or injection error: send `error`, then delayed `hidden`.
- daemon shutdown: send `hidden`, drop stdin, wait briefly for child exit.

Amplitude hooks:
- `voco-audio::Session` already exposes `amplitude_rx: watch::Receiver<f32>`.
- `RecordingSession` will accept an optional `HudSink`.
- During recording, a small tokio task reads amplitude changes and sends clamped values at no more than 60Hz.
- When recording ends, the amplitude task stops with the session.

## 8. Swift HUD Helper

Create `hud/Package.swift` with an executable target named `voco-hud`.

The helper starts an `NSApplication` configured as accessory/background-style UI. It creates one `NSPanel`:
- `.nonactivatingPanel`
- `.borderless`
- `.floating` level
- `ignoresMouseEvents = true`
- transparent background
- not visible at launch

`CapsuleView` uses SwiftUI:
- width around 240-280 points;
- height around 52-60 points;
- `.ultraThinMaterial` capsule background;
- yellow recording dot;
- mic SF Symbol;
- 5-7 waveform bars driven by normalized amplitude;
- red tint for error;
- spinner or subdued bars for transcribing.

The stdin reader runs on a background queue:

```swift
while let line = readLine() {
    decode HudEvent
    DispatchQueue.main.async {
        model.apply(event)
    }
}
DispatchQueue.main.async {
    NSApp.terminate(nil)
}
```

Invalid JSON lines are ignored with stderr diagnostics; they do not crash the helper.

## 9. Error Handling

HUD errors must be fail-soft:
- helper binary missing: warn once, daemon continues;
- helper exits: warn once, disable further HUD writes;
- broken pipe: warn once, disable further HUD writes;
- invalid event serialization: log warn, continue;
- Swift decode error: print to stderr, keep reading next line.

The daemon must never log transcript text in HUD paths.

## 10. Testing

Rust tests:
- `HudEvent` serializes to the JSONL shape Swift expects.
- `HudBridge` write path appends newline-delimited JSON.
- amplitude values are clamped to `[0.0, 1.0]`.
- amplitude forwarding throttles repeated updates.
- orchestrator sends `recording -> transcribing -> hidden` in successful stop flow with a mock HUD sink.
- HUD spawn failure uses noop sink and does not fail daemon startup.

Swift tests:
- JSON line decoding maps `state` and `amplitude` events correctly.
- invalid JSON returns a decode failure without process crash in the parser function.

Manual verification:
- `swift build` inside `hud/`.
- `cargo test --workspace`.
- start daemon; no HUD appears while idle.
- press Right Command once; HUD appears.
- speak; waveform bars move.
- press Right Command again; HUD shows transcribing then hides after injection.
- stop daemon; helper exits.

## 11. Open Follow-ups

These are deliberately not part of Phase 5:
- app bundle packaging and signing;
- launchctl-managed helper lifecycle;
- partial transcript rendering;
- menu bar controls;
- user-customizable HUD position and colors.
