---
title: Voco Dynamic Island HUD
date: 2026-05-05
scope: Refresh the recording HUD to an iPhone Dynamic Island visual style
---

# Voco Dynamic Island HUD 设计文档

## 1. Problem

The current HUD is functional but still reads like a generic black capsule with a microphone icon. The user wants the HUD to look closer to the iPhone Dynamic Island: a compact black island, cleaner status text, and more refined waveform motion.

The current green waveform is also visually heavy. The yellow microphone icon should be replaced with text, and the user confirmed the text should be `语音输入`.

## 2. Goals

- Change the HUD to an iPhone Dynamic Island inspired black capsule.
- Replace the yellow microphone icon with yellow text: `语音输入`.
- Keep the green waveform on the right, but make it thinner and more refined.
- Preserve the black/yellow/green visual direction.
- Preserve the current HUD state flow: `recording`, `transcribing`, `error`, `hidden`.
- Keep the HUD compact and not button-like.

## 3. Non-Goals

- No new HUD state.
- No new daemon IPC event.
- No settings UI.
- No transcript preview inside the HUD.
- No changes to recording lifecycle, ASR, injection, or hotkey handling.

## 4. Final Visual Direction

Use option A:

```text
Left:  yellow text "语音输入"
Right: slim green waveform
Base:  near-black Dynamic Island capsule
```

The island should feel like a small system overlay:

- Smaller, tighter black pill than a generic floating button.
- Very high corner radius, fully pill-shaped.
- Subtle edge highlight and close shadow, with no visible rectangular background.
- Text should be yellow and compact, using a semibold system font.
- Waveform bars should be narrower than the current bars and spaced tighter.

Suggested dimensions:

```text
Capsule width:      176-188 px
Capsule height:     42-46 px
Horizontal padding: 14-16 px
Text width:         intrinsic
Waveform width:     44-50 px
Wave bar width:     2.0-2.5 px
Wave bar count:     7
```

## 5. State Behavior

Recording:

- Show yellow `语音输入` text on the left.
- Show thin green animated waveform on the right.
- Waveform should have baseline motion even when amplitude is low.
- Real amplitude should gently modulate height, not create thick spikes.

Transcribing:

- Keep the same island shell.
- Keep `语音输入` text visible.
- Replace waveform with the existing green spinner or a subdued wave motion.

Error:

- Keep the island shell.
- Change text and waveform/spinner color to red.
- Existing delayed hide behavior remains unchanged.

Hidden:

- Panel stays fully transparent and non-visible.

## 6. Implementation Shape

Swift HUD files:

- `hud/Sources/VocoHUDCore/CapsuleView.swift`
  - Replace the `mic.fill` image with a text label.
  - Rename helper intent from microphone/icon to status label where practical.
  - Reduce waveform bar width and overall waveform width.
  - Tune padding, capsule size, border, and shadow for Dynamic Island proportions.

- `hud/Sources/VocoHUDCore/HudTheme.swift`
  - Add or adjust layout constants for text label, thinner waveform bars, and island size.
  - Keep color tokens black/yellow/green/red.

- `hud/Tests/VocoHUDTests/HudEventTests.swift`
  - Add lightweight assertions for new layout constants if the existing tests support it.

No Rust daemon behavior change is required for this design.

## 7. Verification

Automated:

```bash
cd hud && swift test && swift build
cargo fmt --all --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

Manual:

```bash
./packaging/build_app_bundle.sh
./target/debug/voco app install --app-bundle ./target/Voco.app
/Users/zhangxiaolong/Applications/Voco.app/Contents/MacOS/voco daemon restart
```

Then press Right Command:

- HUD appears as a compact black Dynamic Island style pill.
- Left text is yellow `语音输入`.
- Right waveform is green and visibly thinner than before.
- No rectangular residual background or shadow artifact is visible around the pill.
- Press Right Command again and confirm transcribing state still appears and then hides normally.
