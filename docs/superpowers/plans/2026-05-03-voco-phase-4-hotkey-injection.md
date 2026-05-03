# Voco Phase 4 — Global Hotkey + Text Injection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Phase 3 `_internal_record` trigger with a real macOS global hotkey and inject final ASR text into the focused app.

**Architecture:** Phase 4 keeps the existing daemon/IPC shape and adds two side-effect crates: `voco-hotkey` owns CGEventTap listening, and `voco-injector` owns text delivery. The daemon translates hotkey toggles into `RecordingStart` / `RecordingStop`, drains the final ASR result, then calls the injector.

**Tech Stack:** Rust, tokio, macOS ApplicationServices/CoreFoundation FFI, existing `voco-config`, `voco-ipc`, `voco-daemon`, `voco-audio`, and `voco-asr`.

---

## Task 1: `voco-hotkey` crate

- [x] Add `crates/voco-hotkey` to the workspace.
- [x] Implement pure `HotkeyMatcher` tests for exact key match, modifier match, wrong-key ignore, and keydown/flags-changed debounce.
- [x] Implement `HotkeyManager::install`, `HotkeyEvent::Toggle`, and macOS CGEventTap loop on a dedicated thread.
- [x] Expose `accessibility_trusted()` for doctor checks.

## Task 2: `voco-injector` crate

- [x] Add `crates/voco-injector` to the workspace.
- [x] Implement text normalization for `trim_trailing_punct` and `auto_capitalize`.
- [x] Implement `ClipboardOnly` and `InjectThenClipboard` strategy tests with a mock sink.
- [x] Implement macOS Unicode CGEvent insertion, `pbcopy` clipboard write, and Cmd+V fallback.

## Task 3: daemon toggle orchestration

- [x] Implement `RecordingStart` and `RecordingStop` instead of returning the Phase 3 stub error.
- [x] Maintain one active recording task with a `stop_tx` and final response channel.
- [x] Treat session stop signal as graceful stop that drains `backend.stop()` for final text.
- [x] Inject text only for hotkey/`RecordingStop` flow; keep `_internal_record` terminal-only.
- [x] Add mock injector support through `VOCO_FORCE_MOCK_INJECTOR=1` for tests.

## Task 4: daemon hotkey loop + doctor

- [x] Install global hotkey when daemon starts; daemon still starts if event tap install fails.
- [x] Translate `HotkeyEvent::Toggle` to `Orchestrator::handle_hotkey_toggle()`.
- [x] Update `voco doctor` Hotkey installed check to report real TCC/event-tap readiness instead of Phase 4 skip.
- [x] Keep CI/TCC-sensitive doctor checks skipped when `CI=true`.

## Task 5: verification

- [x] Unit: `cargo test -p voco-hotkey`
- [x] Unit: `cargo test -p voco-injector`
- [x] Unit: `cargo test -p voco-daemon recording_`
- [x] Unit: `cargo test -p voco-daemon stop_signal_drains_backend_final`
- [x] Integration: `cargo test -p voco-cli doctor_skips_hotkey_install_check_on_ci`
- [x] Integration: `cargo test -p voco-cli recording_start_stop_ipc_returns_final -- --test-threads=1`
- [x] Full gates: `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`, `cargo build --workspace --release`
- [x] Manual: from Ghostty with Accessibility/Input Monitoring granted, start daemon, focus Notes/TextEdit, press Right Command once to start, speak, press Right Command again to stop, verify text appears and `voco status` records a successful session.
- [x] Manual/IPC: set `output.mode = "clipboard_only"`, drive `RecordingStart` / `RecordingStop`, verify final text is copied without direct insertion.

---

## Phase 4 explicitly does NOT do

| Item | Phase that owns it |
|---|---|
| SwiftUI HUD / amplitude display | Phase 5 |
| App bundle / launchctl installer | Phase 6 |
| Sherpa local backend | v0.2 |
| Keychain storage for access_token | v0.2 |
