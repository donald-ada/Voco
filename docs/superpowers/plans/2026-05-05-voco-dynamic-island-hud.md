# Voco Dynamic Island HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh the Swift HUD into a compact iPhone Dynamic Island style pill with yellow `语音输入` text and thinner green waveform bars.

**Architecture:** Keep the existing Rust daemon and JSONL HUD event flow unchanged. Implement the visual refresh entirely in `VocoHUDCore` by changing layout tokens, replacing the mic glyph helper with a status text label, and tightening the waveform rendering.

**Tech Stack:** SwiftUI, XCTest, existing Voco HUD helper package, existing Rust workspace verification.

---

## File Structure

- Modify: `hud/Tests/VocoHUDTests/HudEventTests.swift`
  - Update HUD layout token tests to encode the Dynamic Island dimensions and new status label constants.

- Modify: `hud/Sources/VocoHUDCore/HudTheme.swift`
  - Own all visual constants: island size, shadow padding, status label font size, waveform bar width, waveform spacing, waveform width.

- Modify: `hud/Sources/VocoHUDCore/CapsuleView.swift`
  - Replace the microphone SF Symbol with a yellow `语音输入` text label.
  - Render thinner green waveform bars.
  - Preserve state-driven spinner, waveform, error colors, entry animation, and explicit hidden behavior.

No Rust code should change for this feature.

---

### Task 1: Lock Dynamic Island Layout Tokens

**Files:**
- Modify: `hud/Tests/VocoHUDTests/HudEventTests.swift`
- Modify: `hud/Sources/VocoHUDCore/HudTheme.swift`

- [ ] **Step 1: Update the failing theme test**

Replace `HudThemeTests.testB2CompactLayoutTokens` in `hud/Tests/VocoHUDTests/HudEventTests.swift` with:

```swift
func testDynamicIslandLayoutTokens() {
    XCTAssertEqual(HudTheme.Layout.capsuleWidth, 184)
    XCTAssertEqual(HudTheme.Layout.capsuleHeight, 44)
    XCTAssertEqual(HudTheme.Layout.statusLabelText, "语音输入")
    XCTAssertEqual(HudTheme.Layout.statusLabelFontSize, 14)
    XCTAssertEqual(HudTheme.Layout.waveformWidth, 48)
    XCTAssertEqual(HudTheme.Layout.waveformBarWidth, 2.4)
    XCTAssertEqual(HudTheme.Layout.waveformBarSpacing, 3)
    XCTAssertEqual(HudTheme.Layout.waveformBarCount, 7)
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
cd hud && swift test --filter HudThemeTests/testDynamicIslandLayoutTokens
```

Expected: FAIL because `statusLabelText`, `statusLabelFontSize`, `waveformBarWidth`, and `waveformBarSpacing` do not exist yet, and size constants still use the old values.

- [ ] **Step 3: Update layout tokens**

Edit `hud/Sources/VocoHUDCore/HudTheme.swift` so `HudTheme.Layout` becomes:

```swift
public enum Layout {
    public static let capsuleWidth: CGFloat = 184
    public static let capsuleHeight: CGFloat = 44
    public static let shadowPadding: CGFloat = 22
    public static let panelWidth: CGFloat = capsuleWidth + shadowPadding * 2
    public static let panelHeight: CGFloat = capsuleHeight + shadowPadding * 2
    public static let statusLabelText = "语音输入"
    public static let statusLabelFontSize: CGFloat = 14
    public static let waveformWidth: CGFloat = 48
    public static let waveformHeight: CGFloat = 30
    public static let waveformBarWidth: CGFloat = 2.4
    public static let waveformBarSpacing: CGFloat = 3
    public static let waveformBarCount = 7
    public static let contentSpacing: CGFloat = 12
    public static let panelBottomOffset: CGFloat = 96
}
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
cd hud && swift test --filter HudThemeTests/testDynamicIslandLayoutTokens
```

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add hud/Tests/VocoHUDTests/HudEventTests.swift hud/Sources/VocoHUDCore/HudTheme.swift
git commit -m "Tune HUD Dynamic Island layout tokens"
```

---

### Task 2: Replace Mic Glyph With Yellow Status Text

**Files:**
- Modify: `hud/Sources/VocoHUDCore/CapsuleView.swift`

- [ ] **Step 1: Replace the mic helper**

In `hud/Sources/VocoHUDCore/CapsuleView.swift`, replace the `microphone(at:)` helper and `iconName` computed property with:

```swift
private func statusLabel(at date: Date) -> some View {
    let time = date.timeIntervalSinceReferenceDate
    let recordingPulse = model.state == .recording
        ? 1.0 + (0.025 * normalizedSine(time, speed: 0.95, offset: 0))
        : 1.0
    let color: Color = model.state == .error
        ? HudTheme.ColorToken.error.color
        : HudTheme.ColorToken.recordingMic.color

    return Text(HudTheme.Layout.statusLabelText)
        .font(.system(size: HudTheme.Layout.statusLabelFontSize, weight: .semibold))
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .scaleEffect(recordingPulse)
        .shadow(
            color: color.opacity(model.state == .recording ? 0.38 : 0.22),
            radius: model.state == .recording ? 5 : 3
        )
}
```

- [ ] **Step 2: Update the HStack to call the text label**

In the `HStack`, replace:

```swift
microphone(at: now)
```

with:

```swift
statusLabel(at: now)
```

- [ ] **Step 3: Tighten island padding and shadow**

In the same view, change:

```swift
.padding(.horizontal, 14)
```

to:

```swift
.padding(.horizontal, 16)
```

Change the capsule background shadow:

```swift
.shadow(color: Color.black.opacity(0.32), radius: 16, y: 8)
```

to:

```swift
.shadow(color: Color.black.opacity(0.34), radius: 12, y: 5)
```

- [ ] **Step 4: Run Swift tests**

Run:

```bash
cd hud && swift test
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

Run:

```bash
git add hud/Sources/VocoHUDCore/CapsuleView.swift
git commit -m "Replace HUD mic icon with voice input label"
```

---

### Task 3: Thin the Green Waveform

**Files:**
- Modify: `hud/Sources/VocoHUDCore/CapsuleView.swift`

- [ ] **Step 1: Use waveform width and spacing tokens**

In `WaveformBars.body`, replace:

```swift
HStack(spacing: 3.5) {
    ForEach(0..<HudTheme.Layout.waveformBarCount, id: \.self) { idx in
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 5, height: barHeight(idx))
    }
}
```

with:

```swift
HStack(spacing: HudTheme.Layout.waveformBarSpacing) {
    ForEach(0..<HudTheme.Layout.waveformBarCount, id: \.self) { idx in
        RoundedRectangle(cornerRadius: HudTheme.Layout.waveformBarWidth / 2.0)
            .fill(color)
            .frame(width: HudTheme.Layout.waveformBarWidth, height: barHeight(idx))
    }
}
```

- [ ] **Step 2: Reduce waveform height modulation**

Replace `barHeight(_:)` with:

```swift
private func barHeight(_ index: Int) -> CGFloat {
    let pattern = [0.40, 0.70, 1.0, 0.78, 0.48, 0.62, 0.42][index]
    if state == .hidden {
        return 6
    }
    if state == .transcribing {
        let moving = normalizedSine(time, speed: 0.78, offset: Double(index) * 0.55)
        return CGFloat(7.0 + moving * 15.0 * pattern)
    }
    let baseline = 3.0 + normalizedSine(time, speed: 0.78, offset: Double(index) * 0.65) * 5.0
    let boosted = max(amplitude, 0.06) * pattern * 12.0
    return CGFloat(min(max(6.0 + baseline + boosted, 6.0), 26.0))
}
```

- [ ] **Step 3: Thin the transcribing spinner**

In `TranscribingSpinner`, change the stroke line width:

```swift
style: StrokeStyle(lineWidth: 3, lineCap: .round)
```

to:

```swift
style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
```

Change the frame:

```swift
.frame(width: 24, height: 24)
```

to:

```swift
.frame(width: 22, height: 22)
```

- [ ] **Step 4: Run Swift tests**

Run:

```bash
cd hud && swift test
```

Expected: PASS.

- [ ] **Step 5: Commit Task 3**

Run:

```bash
git add hud/Sources/VocoHUDCore/CapsuleView.swift
git commit -m "Thin HUD waveform bars"
```

---

### Task 4: Build, Install, and Verify

**Files:**
- No source edits expected.

- [ ] **Step 1: Run Swift build and tests**

Run:

```bash
cd hud && swift test && swift build && cd ..
```

Expected: PASS and build completes.

- [ ] **Step 2: Run Rust workspace checks**

Run:

```bash
cargo fmt --all --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

Expected: all commands exit 0.

- [ ] **Step 3: Build and install app bundle**

Run:

```bash
./packaging/build_app_bundle.sh
./target/debug/voco app install --app-bundle ./target/Voco.app
/Users/zhangxiaolong/Applications/Voco.app/Contents/MacOS/voco daemon restart
```

Expected: bundle build succeeds, app installs to `/Users/zhangxiaolong/Applications/Voco.app`, daemon restarts through launchctl.

- [ ] **Step 4: Manual HUD check**

Press Right Command and verify:

- HUD is a compact black Dynamic Island style pill.
- Left side shows yellow `语音输入`.
- Right side shows thin green waveform bars.
- No rectangular shadow or background residue is visible around the pill.
- Press Right Command again and confirm transcribing still appears and the HUD hides after finalization.

- [ ] **Step 5: Commit verification note if needed**

If verification required source adjustments, commit them:

```bash
git add hud/Sources/VocoHUDCore/CapsuleView.swift hud/Sources/VocoHUDCore/HudTheme.swift hud/Tests/VocoHUDTests/HudEventTests.swift
git commit -m "Verify Dynamic Island HUD refresh"
```

If no source adjustments were needed after Task 3, do not create an empty commit.
