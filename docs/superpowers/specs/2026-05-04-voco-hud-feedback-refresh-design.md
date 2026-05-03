---
title: Voco HUD Feedback Refresh
date: 2026-05-04
scope: Fix recording HUD visual feedback, animation timing, and long-recording disappearance
---

# Voco HUD Feedback Refresh 设计文档

## 1. Problem

Current HUD behavior and visual treatment are not good enough for daily use:

- The HUD can feel static when recording begins; visible animation is more obvious after the second hotkey press.
- During longer speaking sessions the HUD disappears, which makes the user think recording stopped or UI broke.
- The visual language uses a yellow dot plus a microphone icon. The desired model is simpler: the microphone itself is the yellow recording status mark.
- The grey/glass visual direction is too muted. The HUD should use a black base, yellow microphone, and green waveform.

Code inspection found one likely non-visual cause for the disappearance: `recording_max_duration_secs` defaults to `60`, and the recording loop stops on that timeout. When the recording finalizes, daemon sends `hidden`, so long speech can look like the HUD disappeared by itself.

## 2. Goals

- Use the selected B2 compact HUD direction.
- Make the HUD visibly animate immediately on the first recording hotkey press.
- Keep HUD visible for the whole `recording` state.
- Replace the yellow dot + mic pairing with a yellow microphone status icon.
- Use a black/yellow/green visual system: black capsule, yellow mic, green waveform.
- Reduce the default chance of long-speaking cutoff by raising the default max recording duration.
- Switch the default Doubao streaming ASR resource ID to Seed ASR 2.0 hourly: `volc.seedasr.sauc.duration`.
- Preserve current daemon/HUD architecture: Rust daemon owns state and sends JSONL events; Swift helper renders the HUD.

## 3. Non-Goals

- No menu bar UI.
- No settings UI.
- No transcript text in the HUD.
- No new IPC channel.
- No signing/notarization/packaging work.
- No speech activity detection or automatic stop-on-silence.

## 4. Final Visual Direction

Use B2 compact proportions with shorter width:

```text
HUD capsule: 196px wide x 48px tall
Mic glyph:   22px
Waveform:    7 slim bars, about 58px total width
```

Color system:

```text
Base capsule:     near-black / black
Border/shadow:    subtle dark edge, no grey glass look
Recording mic:    yellow
Recording waves:  green
Transcribing:     green spinner or subdued green wave motion
Error:            red mic/error mark plus red waveform
```

The HUD should read as a compact black status capsule, not a button. The yellow microphone is the recording status mark. There should be no separate yellow dot.

## 5. Animation Behavior

Recording start must trigger visible feedback immediately:

- On `recording`, the panel orders front and the capsule runs an enter animation: fade in, slight upward movement, and scale from about 0.94 to 1.0.
- The yellow mic runs a subtle pulse while recording.
- The green waveform runs a baseline animation even before real amplitude changes arrive.
- Real amplitude events modulate the waveform height on top of the baseline motion.

Recording must not hide the HUD:

- Swift helper must only hide the panel for explicit `hidden` state.
- Amplitude changes must never hide the panel.
- Recording state should keep the panel visible even during quiet input.

Transcribing:

- On stop, daemon sends `transcribing`.
- HUD remains visible and switches to green spinner or subdued green waveform.
- After injection/finalization succeeds, daemon sends `hidden`.

Error:

- Error state shows red visual feedback.
- Error still auto-hides after the existing short delay.

## 6. Long Recording Behavior

The default `recording_max_duration_secs = 60` is too low for normal dictation. Increase the default to `300` seconds.

Validation should keep the existing safe upper bound:

```text
recording_max_duration_secs must be in 1..=600
```

For the user's current machine, implementation should also update local config with:

```bash
target/debug/voco config set recording_max_duration_secs 300
```

This is a local setup action, not a code requirement.

## 7. Implementation Shape

Swift HUD files:

- `hud/Sources/VocoHUDCore/CapsuleView.swift`
  - Remove `statusDot`.
  - Render the microphone as the primary yellow status icon.
  - Change capsule sizing to 196x48.
  - Change background to black/near-black.
  - Change waveform color to green for recording/transcribing.
  - Add immediate recording animation for mic pulse and waveform baseline.

- `hud/Sources/VocoHUDCore/HudModel.swift`
  - Preserve clamping behavior for amplitude.
  - Keep hidden handling explicit.
  - Add small model-level helpers only if needed for testable view state; avoid broad state refactors.

- `hud/Sources/VocoHUD/main.swift`
  - Keep panel lifecycle as-is unless a failing test or manual verification shows panel hiding without `hidden`.
  - Do not add timers for recording hide.

Rust files:

- `crates/voco-config/src/schema.rs`
  - Change default `recording_max_duration_secs` from `60` to `300`.
  - Change default `DoubaoCreds::resource_id` from `volc.bigasr.sauc.duration` to `volc.seedasr.sauc.duration`.

- `crates/voco-config/src/validate.rs`
  - Keep `1..=600` validation.

- `crates/voco-cli/src/commands/config/wizard.rs`
  - Change the fallback resource ID for newly-created Doubao config to `volc.seedasr.sauc.duration`.

- `crates/voco-cli/src/commands/config/set.rs`
  - Change the fallback resource ID used when `voco config set doubao.*` creates a missing Doubao section to `volc.seedasr.sauc.duration`.

Doubao endpoint:

- Keep `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel` in this refresh.
- The user-provided `volc.seedasr.sauc.duration` is a resource ID, not a WebSocket URL.
- Do not switch to `bigmodel_async` in this plan. That endpoint can be evaluated separately because previous live verification stabilized on the simple streaming endpoint.

Tests:

- Swift tests should cover view/model-facing constants or helper values where practical.
- Rust config tests should assert the new default duration.
- Existing daemon HUD event sequence tests must remain valid: `recording -> transcribing -> hidden`.

## 8. Verification

Automated checks:

```bash
cd hud && swift test && swift build && cd ..
cargo fmt --all --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

Manual checks:

```bash
target/debug/voco config set recording_max_duration_secs 300
target/debug/voco config set doubao.resource_id volc.seedasr.sauc.duration
target/debug/voco daemon restart
target/debug/voco status
```

Then:

- Focus Notes/TextEdit.
- Press Right Command once.
- Verify HUD appears immediately with black capsule, yellow mic, green waveform, and recording animation.
- Speak for longer than 60 seconds.
- Verify HUD remains visible and recording continues.
- Press Right Command again.
- Verify HUD switches to transcribing animation.
- Verify final text injects and HUD hides only after completion.

## 9. Initial Color Tokens

Start with a saturated but not neon green:

```text
Green waveform: #32D67A
Yellow mic:     #FFCC4D
Black capsule:  #050607 / #0B0D0F range
```

If this looks too bright in the real Swift HUD, tune within the same black/yellow/green direction without changing the structure.
