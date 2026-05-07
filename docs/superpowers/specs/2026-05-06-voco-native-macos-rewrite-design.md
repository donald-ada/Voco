---
title: Voco Native macOS Rewrite
date: 2026-05-06
status: design-approved
target_platform: macOS 14+ native menu bar app
scope: Rewrite Voco as a pure Swift/SwiftUI app with no user-facing CLI, daemon, or helper process
---

# Voco Native macOS Rewrite 设计文档

## 1. Goal

Voco should become a native macOS app, not a CLI-driven tool wrapped in an app
bundle. The final user-facing product is only `Voco.app`.

The app should feel like a system-level voice input utility:

- always available from the menu bar;
- not visible in the Dock by default;
- able to show a settings window when the user asks for it;
- able to record from a global hotkey without stealing focus;
- able to show a lightweight notch/HUD overlay;
- able to insert transcribed text into the current foreground app;
- distributed as a signed, notarized `.dmg`.

The rewrite optimizes for user experience and runtime performance over reuse of
the existing CLI, Rust daemon, or helper-process architecture.

## 2. Product Decision

Use a single-process Swift/SwiftUI menu bar app.

```text
Voco.app
├─ SwiftUI app shell
├─ MenuBarExtra
├─ Settings window
├─ Permission onboarding
├─ Global hotkey manager
├─ Audio capture engine
├─ Transcription engine
├─ Text injection engine
├─ Notch/HUD overlay
└─ Diagnostics and release packaging
```

`Info.plist` sets:

```text
LSUIElement = true
```

This makes Voco an agent-style app: it does not appear in the Dock or Force Quit
window by default, but it can still present windows when needed.

## 3. Scope

### In Scope

- Replace the user-facing CLI product shape with a native `Voco.app`.
- Build a SwiftUI menu bar app as the primary runtime.
- Keep Voco out of the Dock by default with `LSUIElement=true`.
- Show a settings window on demand from the menu bar or a command.
- Implement native onboarding for required permissions.
- Implement low-latency microphone capture with `AVAudioEngine`.
- Implement a native global hotkey flow for press-to-record and toggle modes.
- Implement a Swift transcription service abstraction.
- Implement direct native state flow from recording to HUD to transcript.
- Implement text injection through macOS-native accessibility/event APIs.
- Rebuild the notch/HUD as an in-process SwiftUI overlay window.
- Manage launch-at-login through `SMAppService.mainApp`.
- Store tokens and secrets in Keychain.
- Provide an in-app diagnostics surface for permissions, audio, hotkey, ASR, and
  text injection.
- Build and distribute a signed, hardened, notarized `.dmg`.

### Out of Scope

- Preserving `voco` CLI compatibility.
- Shipping `voco`, `voco-daemon`, or `voco-hud` in the final app bundle.
- Registering a user LaunchAgent plist from the app.
- Keeping stdin JSONL as the HUD transport.
- Keeping Rust as the runtime engine.
- Adding a `.pkg` installer.
- Adding auto-update in the first native rewrite.
- Adding cloud account sync.
- Supporting macOS versions earlier than macOS 14.

## 4. User-Facing Behavior

### First Launch

The user opens `Voco.app`. Voco appears in the menu bar, not in the Dock.

If Voco is still running from the mounted `.dmg`, the app should show a clear
native prompt asking the user to move it to `/Applications` before enabling
launch-at-login. The app may still allow a temporary trial run from the mounted
image, but diagnostics must show that the install location is not final.

The first-run window guides the user through:

1. microphone permission;
2. accessibility permission;
3. ASR provider setup;
4. launch-at-login preference;
5. hotkey test.

Each step has a visible status, a retry action, and a direct button to open the
relevant System Settings pane when macOS requires manual approval.

### Normal Use

The normal path is:

```text
User presses global hotkey
-> Voco starts recording immediately
-> HUD appears near the notch
-> Partial transcript streams into the HUD
-> User releases hotkey or toggles stop
-> Voco finalizes transcription
-> Voco injects text into the focused app
-> HUD confirms success or shows a clear error
```

The foreground app should keep focus throughout recording and insertion. Voco's
settings window should only activate when the user explicitly opens it.

### Menu Bar

The menu bar item shows compact status:

- Ready
- Recording
- Transcribing
- Permission needed
- Provider offline
- Error

Menu actions:

- Start/stop recording
- Open Settings
- Open Diagnostics
- Check permissions
- Launch at Login toggle
- Quit Voco

### Settings Window

The settings window is a normal native window opened on demand. It does not make
Voco permanently appear in the Dock.

Settings sections:

- General: launch at login, startup behavior, app version.
- Hotkey: press-to-record, toggle recording, selected key binding.
- Audio: input device, level meter, sample rate status.
- Transcription: provider, credentials, language, streaming behavior.
- Injection: insertion mode, clipboard fallback, focused app diagnostics.
- HUD: position, notch mode, transcript preview visibility.
- Privacy: Keychain status, transcript retention policy, logs.
- Diagnostics: permission status, recent failures, export diagnostic bundle.

## 5. Architecture

### AppCoordinator

`AppCoordinator` is the central state owner. It wires together permissions,
hotkey events, audio capture, transcription, text injection, settings, and HUD
state.

Core states:

```text
launching
needs_onboarding
ready
recording
transcribing
injecting
blocked(permission)
error
```

The coordinator exposes observable state to SwiftUI views and receives events
from service objects. It should not contain platform API details directly.

### PermissionManager

`PermissionManager` owns all permission checks and requests:

- microphone authorization through native media capture APIs;
- accessibility trust checks for text insertion and event posting;
- System Settings deep links where macOS requires manual action.

Permission failures are first-class app states, not log-only warnings.

### HotkeyManager

`HotkeyManager` owns global activation.

The design supports two modes:

- press-to-record: hold hotkey to record, release to finish;
- toggle: press once to start, press again to stop.

For best latency and key-up handling, implementation should use native global
event handling rather than shelling out or delegating to another process. If a
selected hotkey requires permissions that are not granted, `HotkeyManager`
reports a blocked state instead of silently disabling recording.

### AudioCaptureEngine

`AudioCaptureEngine` uses `AVAudioEngine` for low-latency capture.

Responsibilities:

- select and observe the active input device;
- configure input format and resampling;
- expose PCM frames to the transcription engine;
- compute amplitude for the HUD;
- detect silence and device loss;
- restart cleanly after device changes.

Performance targets:

```text
hotkey down -> audio capture starts: under 50 ms
audio buffer duration: 10-20 ms target
HUD amplitude update: 30-60 fps
process spawn during normal recording path: none
IPC during normal recording path: none
```

### TranscriptionEngine

`TranscriptionEngine` is a Swift protocol, not a CLI wrapper.

```text
AudioCaptureEngine -> TranscriptionEngine -> TranscriptStream
```

The protocol supports:

- streaming partial transcripts;
- final transcript;
- cancellation;
- retryable provider errors;
- explicit auth/configuration errors;
- latency metrics.

Provider implementations can be remote or local, but the app shell should not
care which provider is active. Provider credentials are stored in Keychain.

### TextInjectionEngine

`TextInjectionEngine` inserts the final transcript into the foreground app.

Preferred order:

1. Direct accessibility insertion into the focused text element when supported.
2. Unicode event insertion when appropriate.
3. Clipboard paste fallback with clipboard restoration and explicit user-facing
   diagnostics.

The engine must report the target app, selected insertion strategy, and failure
reason. Clipboard fallback must never silently overwrite user clipboard content.

### HUD Overlay

The HUD is an in-process SwiftUI overlay window, not a helper binary.

Implementation shape:

- transparent `NSPanel`;
- non-activating;
- does not steal keyboard focus;
- can join all Spaces;
- positioned near the notch or top center;
- renders recording, transcribing, transcript, success, and error states;
- reads state directly from `AppCoordinator`.

This removes process startup cost and stdin JSONL transport from the recording
path.

## 6. Packaging and Distribution

The final distributable contains:

```text
Voco.dmg
└─ Voco.app
```

The final app bundle does not contain user-facing CLI or daemon binaries.

Release pipeline:

```text
build native Voco.app
-> codesign with Developer ID Application
-> enable hardened runtime
-> create DMG with Applications alias
-> codesign DMG
-> notarize with notarytool
-> staple ticket
-> verify with spctl, codesign, and stapler
```

The app should support launch-at-login through `SMAppService.mainApp`. It should
not install `~/Library/LaunchAgents/com.voco.daemon.plist`.

## 7. Migration and Cleanup

The rewrite intentionally breaks the CLI-first product model.

Existing Rust crates, CLI commands, LaunchAgent templates, and Swift HUD helper
can stay in the repository during the rewrite for reference, but they are not
part of the final product. Once the native app reaches feature parity, remove or
archive:

- `crates/voco-cli`;
- `crates/voco-daemon`;
- daemon LaunchAgent packaging;
- `voco-hud` helper process packaging;
- CLI-driven install documentation.

User data migration should be explicit:

- credentials move to Keychain;
- app preferences move to native app preferences;
- old logs remain readable but are not required by the native app;
- old LaunchAgent plist is detected and offered for removal.

## 8. Error Handling

No permission, filesystem, network, ASR, or injection failure may be silently
ignored.

User-visible failures should include:

- what failed;
- which system permission or setting is needed;
- which provider or focused app was involved;
- whether retry is safe;
- where diagnostics were written.

Diagnostic logs must redact secrets and transcript content by default. The user
can explicitly export a diagnostic bundle with sensitive fields still redacted.

## 9. Testing Strategy

### Unit Tests

- `AppCoordinator` state transitions.
- `PermissionManager` status mapping.
- `HotkeyManager` press/release and toggle state machine.
- `AudioCaptureEngine` format conversion and amplitude calculations.
- `TranscriptionEngine` provider error classification.
- `TextInjectionEngine` strategy selection and clipboard restoration.
- HUD view model state mapping.

### Integration Tests

- onboarding reaches ready state when all mocked permissions are granted;
- blocked permissions surface the correct recovery action;
- recording cancellation does not inject text;
- provider auth failure shows settings recovery;
- injection failure preserves clipboard state;
- launch-at-login status reflects `SMAppService` state.

### Manual UX Verification

Run on a clean macOS account:

```bash
xcodebuild -scheme Voco -configuration Release build
codesign --verify --deep --strict path/to/Voco.app
spctl --assess --type execute --verbose=4 path/to/Voco.app
```

Then verify:

- first launch shows menu bar item and no Dock icon;
- settings window opens only when requested;
- microphone permission prompt appears with Voco branding;
- accessibility recovery links work;
- global hotkey starts recording without focusing Voco;
- HUD appears without stealing focus;
- final text inserts into TextEdit, Safari, Notes, and a terminal editor;
- launch-at-login works after logout/login;
- quitting Voco removes the menu bar item cleanly.

### Release Verification

```bash
codesign --verify --deep --strict dist/Voco.app
spctl --assess --type execute --verbose=4 dist/Voco.app
hdiutil verify dist/Voco.dmg
codesign --verify --strict dist/Voco.dmg
xcrun stapler validate dist/Voco.dmg
spctl --assess --type open --verbose=4 dist/Voco.dmg
```

Expected:

- app signature is valid;
- DMG signature is valid;
- notarization ticket validates;
- Gatekeeper accepts the DMG and app on a clean machine.

## 10. Acceptance Criteria

The native rewrite is complete when:

- users install only `Voco.app` from a `.dmg`;
- no CLI command is required for installation, startup, recording, settings, or
  diagnostics;
- Voco does not appear in the Dock during normal use;
- settings can be opened on demand;
- launch-at-login is controlled inside the app;
- hotkey-to-recording latency meets the target budget;
- HUD and transcript state update without helper-process IPC;
- text insertion succeeds in common macOS text targets;
- all required permissions have native onboarding and recovery flows;
- release artifacts pass signing, notarization, and Gatekeeper verification.
