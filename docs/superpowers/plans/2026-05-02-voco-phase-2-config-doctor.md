---
title: Voco Phase 2 — Config wizard + doctor + log tooling
date: 2026-05-02
status: draft (pending review)
phase_depends_on: 2026-05-01-voco-phase-1-scaffold.md
spec_reference: 2026-05-01-voco-design.md §3.2 / §5.4 / §5.6 / §8 Week 2
---

# Voco Phase 2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Phase 1 留下的三个 stub（`voco config` / `voco doctor` / 完整的日志路径自检）变成可用功能，并落实 Phase 1 carry-over 中的 `VOCO_HOME` 环境变量隔离，使集成测试不再污染用户真实 `~/Library` 目录。

**End-of-phase verification:**

```
$ voco config            # 交互式向导走完五个问题，原子保存到 config.toml
$ voco config show       # 打印当前配置（脱敏 access_token）
$ voco config set output.mode clipboard_only
✓ Saved.
✓ Daemon reloaded (or: daemon not running, change applies on next start)

$ voco config validate
✓ ~/.config/voco/config.toml valid

$ voco doctor
Checking permissions ... (skip on CI)
Checking config ...      ✓
Checking daemon ...      ✓ socket reachable, hotkey not yet installed (Phase 4)
Checking microphone ...  ✓ default input device available
Checking backend ...     ✓ doubao handshake ok (logid=...), empty-audio probe returned 45000002 as expected
All checks: 5 ok / 0 warn / 0 fail
```

**Tech additions:**
- `inquire = "0.7"` — interactive wizard primitives
- `crossterm = "0.27"` — raw-mode keypress capture for "Custom..." hotkey option
- `cpal = "0.15"` — only used by doctor's microphone probe (full audio capture lands in Phase 3; doctor uses default-host enumeration only, no stream `play()`)
- `core-graphics = "0.24"` — only the `AXIsProcessTrustedWithOptions` shim for accessibility check (added behind `#[cfg(target_os = "macos")]`)
- `tokio-tungstenite = { version = "0.24", features = ["rustls-tls-webpki-roots"] }` — Doubao WebSocket transport (Task 8); the same dep also covers doctor's auth probe so we can drop the temporary `reqwest` plan
- `flate2 = "1"` — Gzip frame compression for the Volcengine binary protocol
- `bytes = "1"` — frame buffer hygiene
- `async-trait = "0.1"` — already in voco-daemon; promote to workspace dep so voco-asr can share

**Test additions:**
- `expectrl` — drive interactive wizard transcript in tests
- existing `assert_cmd` / `serial_test` — extend smoke suite

---

## Task 1: VOCO_HOME env override (carry-over)

**Why first:** every later task wants to write tests against an isolated socket/config/log root. Doing this once now means doctor + wizard tests get free isolation.

**Files:**
- Modify: `crates/voco-daemon/src/paths.rs`
- Modify: `crates/voco-config/src/io.rs`
- Modify: existing tests so the smoke suite uses VOCO_HOME

**Design:**
- New env var `VOCO_HOME`. When set, **all** of these resolve under it:
  - `application_support_dir()` → `$VOCO_HOME/data`
  - `logs_dir()` → `$VOCO_HOME/logs`
  - `ConfigIo::default_path()` → `$VOCO_HOME/config.toml`
- Daemon process inherits the env var from its parent (the `voco daemon start` shell), so cli + daemon agree without any IPC plumbing.
- The override is **only** for tests + dev — production users never set it. Keep the resolution logic in two helpers (one in `voco-daemon::paths`, one in `voco-config::io`) and make sure they read `std::env::var("VOCO_HOME")` lazily on each call (not memoized) — tests change env between cases.

**Steps:**

- [ ] **Step 1: Add `voco_home_root()` helper to `voco-daemon::paths`**

```rust
fn voco_home_root() -> Option<PathBuf> {
    std::env::var_os("VOCO_HOME").map(PathBuf::from)
}

pub fn application_support_dir() -> PathBuf {
    if let Some(root) = voco_home_root() { return root.join("data"); }
    BaseDirs::new().map(|b| b.data_dir().join("voco"))
        .unwrap_or_else(|| PathBuf::from("./voco-data"))
}

pub fn logs_dir() -> PathBuf {
    if let Some(root) = voco_home_root() { return root.join("logs"); }
    BaseDirs::new().map(|b| b.home_dir().join("Library").join("Logs").join("voco"))
        .unwrap_or_else(|| PathBuf::from("./voco-logs"))
}
```

- [ ] **Step 2: Mirror the same override in `voco-config::io::ConfigIo::default_path()`**

```rust
pub fn default_path() -> PathBuf {
    if let Ok(root) = std::env::var("VOCO_HOME") {
        return PathBuf::from(root).join("config.toml");
    }
    // existing branch unchanged
}
```

- [ ] **Step 3: Add unit tests for the override (one in each crate)** — tempdir + `std::env::set_var` + assert paths.

  Use `serial_test::serial` (already a dev-dep on voco-cli; add to voco-daemon dev-deps too) so env mutations don't race other tests.

- [ ] **Step 4: Update `crates/voco-cli/tests/smoke.rs` to set `VOCO_HOME` per-test**

```rust
fn voco_with_home(tmp: &tempfile::TempDir) -> Command {
    let mut c = Command::cargo_bin("voco").unwrap();
    c.env("VOCO_HOME", tmp.path());
    c
}
```

  Each test gets its own tempdir → tests no longer touch `~/Library`. Drop the comment about Phase 2 introducing this.

- [ ] **Step 5: Verify** — `cargo test --workspace`. All Phase 1 tests should still pass.

- [ ] **Step 6: Commit**

```
feat(paths): VOCO_HOME env override for isolated dev/test runs

- voco-daemon::paths and voco-config::io both honor $VOCO_HOME
  (data/ logs/ config.toml live under it; default unchanged when unset)
- smoke.rs uses per-test tempdir; ~/Library is no longer touched by tests
- carry-over from Phase 1 §"Open issues for Phase 2"
```

---

## Task 2: voco-config — `show` / `set` / `validate` / `reset` / `edit`

Non-interactive sub-commands first; the wizard (Task 3) builds on top.

**Files:**
- Modify: `crates/voco-cli/src/commands/config.rs` (replace stub)
- Add: `crates/voco-cli/src/commands/config/show.rs` (and friends — split into one file per action under a new `config/` module)
- Modify: `crates/voco-cli/Cargo.toml` (add `toml = "0.8"` for `set` to round-trip)
- Modify: `crates/voco-config/src/schema.rs` — add a `redacted_view()` method that returns a `&Config`-like struct with `access_token` masked, used by `voco config show`.

**Design — `set <key> <value>`:**

Dotted-path keys, only on **leaf scalars**. Whitelist; anything off-list is rejected with "use `voco config edit` for nested edits".

```
backend                                  → BackendChoice
hotkey.keycode                           → u16
hotkey.modifiers                         → u32
hotkey.display_name                      → String
output.mode                              → OutputMode
output.trim_trailing_punct               → bool
output.auto_capitalize                   → bool
hud.style                                → HudStyle
log_level                                → LogLevel
recording_max_duration_secs              → u32
doubao.app_id                            → String  (creates section if absent)
doubao.access_token                      → String  (special: never echo back)
doubao.endpoint                          → String
doubao.model_id                          → String
sherpa.model_dir                         → PathBuf
sherpa.num_threads                       → usize
sherpa.provider                          → String
```

Read → mutate → `Config::validate()` → `ConfigIo::save()` → notify daemon (best-effort, see below).

**Design — `show`:**

Pretty TOML to stdout. `access_token` rendered as `"********"` regardless of length (don't reveal length either). Add a `--unsafe-show-secrets` flag for the rare case the user actually needs to verify their token; print a clear warning when used.

**Design — `validate`:**

Just `ConfigIo::load()` → `Config::validate()` → exit 0 on Ok / exit 1 with formatted errors on Err. Same engine the wizard will reuse.

**Design — `reset`:**

`Confirm::new("This wipes ~/.config/voco/config.toml. Continue? [y/N]")`. On yes, `ConfigIo::save(&Config::default())`. Mention that doubao creds will be lost.

**Design — `edit`:**

`std::process::Command::new(std::env::var("EDITOR").unwrap_or("vi"))` on `default_path()`. Validate after the editor exits; on validation failure, print errors and ask "Re-edit / discard / save anyway?" — discarding restores from a `.bak` we wrote first.

**Daemon notify (shared helper for `set` and the wizard):**

```rust
fn notify_daemon_reload() -> ReloadOutcome {
    match IpcClient::connect(default_socket_path()) {
        Err(_) => ReloadOutcome::DaemonNotRunning,    // print: "(daemon not running; change takes effect on next start)"
        Ok(mut c) => match c.call(&Request::ReloadConfig) {
            Ok(Response::Ok)              => ReloadOutcome::Reloaded,
            Ok(Response::Error{message})  => ReloadOutcome::ReloadFailed(message),  // Phase 1 returns "not yet implemented" — treat as warn, don't fail the whole `set`
            Ok(other)                     => ReloadOutcome::ReloadFailed(format!("{:?}", other)),
            Err(e)                        => ReloadOutcome::ReloadFailed(e.to_string()),
        },
    }
}
```

Phase 1's daemon returns `"reload_config: not yet implemented"`; Task 7 of this Phase 2 plan flips it to actually reload.

- [ ] **Step 1:** Build out the `config::` module per file (one action per file). Keep each function under ~50 lines.
- [ ] **Step 2:** Add `redacted_view()` to schema; `show` uses it.
- [ ] **Step 3:** Unit tests in `voco-config/tests/redaction.rs` — assert `to_string_pretty(&redacted)` does not contain the literal token.
- [ ] **Step 4:** Smoke tests in `voco-cli/tests/config_subcommands.rs` covering: show / set / validate happy + invalid-key / reset with `--yes` / edit with `EDITOR=true`.
- [ ] **Step 5:** Commit.

---

## Task 3: voco-config — interactive wizard (`voco config` no args)

**Files:**
- Add: `crates/voco-cli/src/commands/config/wizard.rs`
- Modify: `crates/voco-cli/Cargo.toml` — add `inquire = "0.7"`, `crossterm = "0.27"`

**Flow:** match spec §3.2.

```
1. Show current config summary (one line per group) — "press Enter to start, Esc to abort"
2. Select<BackendChoice>          (highlight current)
3. Select<HotkeyPreset>           (Right Command / Fn / F19 / Caps / Custom...)
   3a. If Custom: enter raw mode via crossterm::event, capture next non-modifier+modifier combo, render display_name
4. Select<OutputMode>
5. Confirm("Configure Doubao credentials?")
   5a. Text<app_id>
   5b. Password<access_token>      (inquire::Password — masked)
   5c. Text<endpoint>              (default = current or "wss://...")
   5d. Select<model_id>
6. Select<HudStyle>
7. Diff old vs new, line-by-line; highlight only the rows that changed
8. Confirm("Apply these changes?")  → ConfigIo::save() → notify_daemon_reload()
9. Print outcome (saved / daemon reloaded / restart required for backend swap while !Idle)
```

**HotkeyPreset → HotkeyConfig table** (hardcoded for v1, source of truth for the wizard):

| Preset | keycode | modifiers (CGEventFlags) | display_name |
|---|---|---|---|
| Right Command | 0x36 | 0 | "Right Command" |
| Fn | 0x3F | 0 (kCGEventFlagMaskSecondaryFn) | "Fn" |
| F19 | 0x50 | 0 | "F19" |
| Caps Lock | 0x39 | 0 | "Caps Lock" |
| Custom... | (captured) | (captured) | derived |

**Custom-key capture (crossterm raw-mode loop):**

```rust
crossterm::terminal::enable_raw_mode()?;
let result = loop {
    if let Event::Key(KeyEvent { code, modifiers, kind: KeyEventKind::Press, .. }) = event::read()? {
        if matches!(code, KeyCode::Esc) { break Err(WizardError::Aborted); }
        if !modifiers_only(code, modifiers) {                 // require a non-modifier or skip pure modifier-noise
            break Ok((map_to_keycode(code), map_modifiers(modifiers)));
        }
    }
};
crossterm::terminal::disable_raw_mode()?;
```

Notes:
- `crossterm` reports symbolic codes; map to macOS keycodes via a small lookup. Cover the common keys; for anything unmappable, prompt "Press a different key — that one isn't recognized."
- Always `disable_raw_mode()` — wrap in a guard so panic doesn't leave the user's terminal broken.

**Tests:**

- [ ] `voco-cli/tests/wizard.rs` using `expectrl::spawn("./voco config")` for the menu-driven path. Skip Custom hotkey capture (raw-mode + expectrl is fragile); instead test it via a unit test on the parsing helper.
- [ ] Unit test in `wizard.rs`: `crossterm::event::KeyEvent` → `(keycode, modifiers, display_name)` mapping.

- [ ] **Step 1:** Wizard skeleton, Select prompts.
- [ ] **Step 2:** Custom hotkey capture (with the raw-mode guard).
- [ ] **Step 3:** Diff renderer + Confirm.
- [ ] **Step 4:** Wire into `commands::config::run(None)`.
- [ ] **Step 5:** Tests.
- [ ] **Step 6:** Commit.

---

## Task 4: voco-doctor crate (or just module — see "Tradeoff")

**Tradeoff:** Spec §3.2 puts doctor inside the cli crate. Phase 2 keeps it there as `voco-cli/src/commands/doctor/` to avoid an extra crate; if doctor checks grow into Phase 3+ we can promote to `voco-doctor`. Don't pre-emptively crate it.

**Files:**
- Add: `crates/voco-cli/src/commands/doctor/mod.rs`         (driver + Report rendering)
- Add: `crates/voco-cli/src/commands/doctor/permissions.rs`
- Add: `crates/voco-cli/src/commands/doctor/config.rs`
- Add: `crates/voco-cli/src/commands/doctor/daemon.rs`
- Add: `crates/voco-cli/src/commands/doctor/microphone.rs`
- Add: `crates/voco-cli/src/commands/doctor/backend.rs`

**Check taxonomy (each check returns this):**

```rust
pub enum CheckResult {
    Ok(String),               // brief detail line
    Warn { headline: String, hint: String },
    Fail { headline: String, fix: String },
    Skip(String),             // e.g. "sherpa not configured (skip)"
}

pub struct Check {
    pub group: &'static str,  // "Permissions" | "Config" | "Daemon" | "Microphone" | "Backend"
    pub name:  &'static str,
    pub run:   fn() -> CheckResult,
}
```

**Check inventory (Phase 2 set):**

| Group | Name | Phase 2 behavior |
|---|---|---|
| Permissions | Microphone (TCC) | Use `AVAudioApplication.requestRecordPermission` introspection or `AVCaptureDevice.authorizationStatus(for: .audio)` via objc2; fail with `→ System Settings → Privacy → Microphone`. v1 acceptable: try to enumerate input devices via cpal and infer "no permission" from a specific cpal error. |
| Permissions | Accessibility | `AXIsProcessTrustedWithOptions(prompt: false)` (no-prompt variant — prompting is reserved for daemon startup in Phase 4) |
| Permissions | Input Monitoring | macOS 10.15+: `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` |
| Config | File exists at `default_path()` | Skip "ok" if the file is absent and `Config::default()` would have been used |
| Config | Schema valid | `ConfigIo::load_from(path)` |
| Config | Semantic valid | `Config::validate()` |
| Daemon | Socket reachable | `UnixStream::connect(default_socket_path())` |
| Daemon | Hotkey installed | not in Phase 2; Skip with "(Phase 4)" |
| Microphone | Default input device | cpal `default_host().default_input_device()` and `supported_input_configs()` |
| Backend | Doubao credentials present | non-empty app_id + access_token (or new-console api_key) |
| Backend | Doubao handshake | Build the `voco-asr::DoubaoBackend` (Task 8), `start().await`, `stop().await`. Server returns `45000002 empty audio` — treat that as ✓ (handshake + auth ok, no audio sent is expected). Other errors propagate as Fail with the error code/message. 5s timeout. |
| Backend | Sherpa | Skip (Phase v2) |
| Model files | sherpa skipped | always Skip |

**Renderer:**

```
$ voco doctor
Permissions
  ✓ Microphone access (granted)
  ✗ Accessibility (not granted)
      → System Settings → Privacy & Security → Accessibility → enable Voco
  ✓ Input Monitoring (granted)
Config
  ✓ ~/.config/voco/config.toml exists
  ✓ Schema valid
  ✓ Semantic valid
Daemon
  ✓ Socket /Users/.../voco.sock reachable
  - Hotkey installed (Phase 4)
Microphone
  ✓ Default input device: MacBook Pro Microphone (16 kHz mono supported)
Backend
  ✓ Doubao endpoint reachable (rtt 84ms)
  ✓ Doubao credentials present
  ✓ Doubao handshake (logid=20260502xxxxx, rtt 320ms; empty-audio probe returned 45000002 as expected)

Summary: 10 ok / 0 warn / 1 fail / 2 skip
```

Exit code: 0 if no Fail, else 1.

**Tests:**
- [ ] Each check function in isolation: pure test (set up a tempdir, env var, mock socket via `bind`-then-drop trick) → assert exact `CheckResult`.
- [ ] Renderer test: feed a fixture `Vec<Check>` → snapshot the printed output (use `insta` or a hand-rolled equality).
- [ ] CI consideration: TCC permission checks require GUI; gate them with `#[cfg_attr(ci, ignore)]` or a runtime check that returns Skip when `CI=true`.

- [ ] **Step 1:** Define `CheckResult` / `Check` types and the renderer.
- [ ] **Step 2:** Implement each check module (alphabetical: backend → config → daemon → microphone → permissions). Each module ships with its own test.
- [ ] **Step 3:** Wire into `commands::doctor::run`.
- [ ] **Step 4:** Update `voco-cli/Cargo.toml` deps (cpal, core-graphics, objc2 for the perm checks; voco-asr for the backend probe).
- [ ] **Step 5:** Smoke test invocation in `tests/doctor_smoke.rs`.
- [ ] **Step 6:** Commit.

---

## Task 5: tracing — surface `daemon logs -f` improvements

Phase 1 already shells out to `tail -F`. Phase 2 hardens:

- [ ] **Step 1:** When `voco daemon logs` runs and the daemon is **not running**, print a hint instead of just "(no log file)" — include `voco daemon start`.
- [ ] **Step 2:** Add `--lines <N>` (default 50) flag → maps to `tail -n N`.
- [ ] **Step 3:** Daemon side: switch tracing-appender to date-suffixed rotation (`Rotation::DAILY`) so old days don't grow unbounded. Update the demo expectation in Phase 1's plan footnote (file is now `voco.YYYY-MM-DD.log`); update `default_log_file()` → returns the **directory**, with `commands::daemon::logs` discovering the latest dated file via `std::fs::read_dir` + sort.
- [ ] **Step 4:** Tests: write a fake log file, call the resolver, assert it picks the most recent.
- [ ] **Step 5:** Commit.

---

## Task 6: voco-daemon — actually implement `ReloadConfig`

Phase 1 returned a stub error. Phase 2 wires it for the subset of fields that don't require a backend swap or socket rebind (those need `daemon restart` and Phase 3+ owns them anyway).

**Reload-able fields in Phase 2:**
- `output.*` → just write to `Arc<RwLock<Config>>`
- `hud.*` → same (HUD doesn't exist yet, so this is a no-op write)
- `log_level` → no-op for now (env-filter is set at startup; document as "restart required")
- `recording_max_duration_secs` → no-op (recording is Phase 3)
- `doubao.*` → write only; new creds picked up on next `backend.start()` in Phase 3

**Not yet reload-able (return clear "restart required"):**
- `backend` swap
- `hotkey.*`        (Phase 4)
- `socket path / log path / VOCO_HOME` — never reload-able

**Files:**
- Modify: `crates/voco-daemon/src/orchestrator.rs` — `Request::ReloadConfig` arm becomes:
  ```rust
  Request::ReloadConfig => match Config::load_from(default_path()) {
      Err(e)  => Response::Error { message: format!("reload: {e}") },
      Ok(new) => match new.validate() {
          Err(es) => Response::Error { message: format_validation(es) },
          Ok(())  => {
              let mut cfg = self.config.write().await;
              let warnings = diff_for_restart(&cfg, &new);  // returns Vec<String>
              *cfg = new;
              if warnings.is_empty() { Response::Ok }
              else { Response::Error { message: warnings.join("; ") } }    // soft "ok with warnings" — see note
          }
      }
  }
  ```

**Note:** Phase 2 doesn't need a new wire variant for "ok-with-warnings" — extend `Response` with `OkWithWarnings { warnings: Vec<String> }` and bump `PROTOCOL_VERSION` from 1 to 2. The cli renders warnings inline. (This is the only protocol bump in Phase 2.)

**Tests:**
- [ ] Unit test on `diff_for_restart` — covers each field group.
- [ ] Integration: `voco config set output.trim_trailing_punct true` → daemon's status now reflects new config (we need a way to surface it; either add an inert `effective_config_hash` to StatusInfo or expose a `Request::DumpConfig` debug-only message — pick one and stay consistent).
- [ ] Don't forget to update phase-1 e2e `version_mismatch_returns_error` test — expected version is now 2.

- [ ] **Step 1:** Bump `PROTOCOL_VERSION` to 2; add `Response::OkWithWarnings`. Update existing tests.
- [ ] **Step 2:** Implement `diff_for_restart` + reload arm.
- [ ] **Step 3:** Tests.
- [ ] **Step 4:** Commit.

---

## Task 7: voco-asr crate + Doubao WebSocket backend (protocol layer)

**Why in Phase 2:** Phase 1 spec scheduled this for Phase 3, but the Phase 2 doctor wants a real handshake probe (Task 4 §"Backend"). Doing the protocol layer now means doctor can be honest about whether auth works, and Phase 3 only needs to wire `cpal` PCM into `feed()` — no protocol work left. **Task 4 lands first with a temporary `Skip("backend probe wired in Task 7")` stub for the handshake check; this Task 7 fills it in for real.**

**Out of scope (still Phase 3):** real microphone capture, the orchestrator-level recording state machine, partial-text streaming to UI. This task only delivers a self-contained `AsrBackend` that you can drive with synthetic PCM bytes from a test or doctor probe.

**Spec reference:** §3.3, plus the official Volcengine doc at `~/Downloads/volcengine-api.md` (binary frame layout, header bit packing, error codes).

**Files:**
- Add: `crates/voco-asr/Cargo.toml`
- Add: `crates/voco-asr/src/lib.rs`            — `AsrBackend` trait + `Partial` / `Final` / `Segment` structs + `build_backend(&Config)`
- Add: `crates/voco-asr/src/error.rs`          — `AsrError` (network / auth / protocol / decode / not_implemented)
- Add: `crates/voco-asr/src/sherpa.rs`         — Phase 2 stub: `start()` returns `AsrError::NotImplemented`. Trait shape settled here so Phase v0.2 can fill it in.
- Add: `crates/voco-asr/src/doubao/mod.rs`     — `DoubaoBackend` struct + AsrBackend impl
- Add: `crates/voco-asr/src/doubao/protocol.rs` — pure functions: encode/decode the 4-byte header, build full-client-request frame, build audio-only frame, parse server response, parse error message
- Add: `crates/voco-asr/src/doubao/codec.rs`   — Gzip wrappers around `flate2`
- Add: `crates/voco-asr/src/doubao/auth.rs`    — `DoubaoAuth` enum + header-builder for old-console (`X-Api-App-Key` + `X-Api-Access-Key`) and new-console (`X-Api-Key`) flavors
- Add: `crates/voco-asr/src/doubao/types.rs`   — `FullClientRequest` payload struct (audio / request / user / corpus sub-structs) — serde-serializable
- Add: `crates/voco-asr/src/doubao/ws.rs`      — `tokio_tungstenite::connect_async_with_config` wrapper that injects auth headers + tracks logid
- Add: `crates/voco-asr/tests/protocol.rs`     — pure-function header roundtrips, gzip roundtrips, server-response parsing on captured fixtures
- Add: `crates/voco-asr/tests/mock_server.rs`  — full e2e against a `tokio_tungstenite::accept_async` mock that asserts request headers + frames and replies with canned responses
- Add: `crates/voco-asr/tests/live.rs`         — `#[ignore]` smoke against the real endpoint, gated on `VOCO_DOUBAO_*` env vars
- Modify: workspace `Cargo.toml` — promote `async-trait` to `[workspace.dependencies]`; add the new dep set
- Modify: `crates/voco-config/src/schema.rs` — add `DoubaoCreds::api_key: Option<String>` (new-console single-key flavor) and `DoubaoCreds::resource_id: String` (default `volc.bigasr.sauc.duration`)

### 7.1 Public API (`voco-asr/src/lib.rs`)

```rust
#[async_trait::async_trait]
pub trait AsrBackend: Send + Sync {
    async fn start(&mut self) -> Result<(), AsrError>;
    async fn feed(&mut self, pcm: &[i16]) -> Result<Option<Partial>, AsrError>;
    async fn stop(&mut self) -> Result<Final, AsrError>;
    fn name(&self) -> &'static str;
}

pub struct Partial { pub text: String, pub stable_prefix_len: usize }
pub struct Final   { pub text: String, pub segments: Vec<Segment>, pub logid: Option<String> }
pub struct Segment { pub text: String, pub start_ms: u32, pub end_ms: u32, pub definite: bool }

pub fn build_backend(cfg: &voco_config::Config) -> Result<Box<dyn AsrBackend>, AsrError> { ... }
```

### 7.2 Endpoint + protocol decisions

- **Endpoint:** `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async` (双向流式优化版). Phase 1's default config already calls this `endpoint`; Task 8 adds it as the literal default in `Config::default()`.
- **Auth flavor:** dispatch on `(api_key, app_id)` presence:
  - `api_key.is_some()` → new-console: send only `X-Api-Key`, `X-Api-Resource-Id`, `X-Api-Request-Id`, `X-Api-Connect-Id`
  - else if `app_id.is_some() && access_token.is_some()` → old-console: send `X-Api-App-Key` + `X-Api-Access-Key` + the rest
  - else → `AsrError::Auth("no credentials configured")`
- **Resource ID:** default `volc.bigasr.sauc.duration` (Doubao 1.0 hourly). Surfaced in `Config::doubao.resource_id` so users on 2.0 can override.
- **Audio params (full client request):** `format=pcm`, `codec=raw`, `rate=16000`, `bits=16`, `channel=1`. PCM s16le, mono. (Locked to spec §3.4 — voco-audio also produces this exact format.)
- **Request params:** `model_name=bigmodel`, `enable_punc=true`, `enable_itn=true`, `enable_ddc=false`, `result_type=full`, `end_window_size=800` (default judging window). Configurable knobs (`enable_punc`, `enable_itn`, `result_type`) are added to `Config::doubao` as optional fields with these defaults.
- **Sequence numbers:** start at 1 on the first audio frame; increment per send. Last frame uses `-(N+1)` and message-type-specific-flags = `0b0011` (negative-with-sequence + last-packet).
- **Frame size:** `feed()` accepts arbitrary PCM chunks but internally buffers to ~200ms (= 6400 samples = 12800 bytes at 16kHz/16bit/mono) before sending — spec doc says 100-200ms is optimal. Buffering happens in DoubaoBackend, not the trait, so other backends can pick a different cadence.
- **Compression:** Gzip (`flate2::write::GzEncoder`). Compressed before `payload_size` is computed; size is big-endian u32.

### 7.3 Header packing (verified against the spec doc table)

```rust
struct Header {
    protocol_version: u8,    // always 1
    header_size: u8,         // always 1 (= 4 bytes)
    message_type: MessageType,
    flags: u8,
    serialization: Serialization,
    compression: Compression,
}

enum MessageType { FullClientRequest = 0b0001, AudioOnlyRequest = 0b0010,
                   FullServerResponse = 0b1001, ServerError = 0b1111 }
enum Serialization { None = 0, Json = 1 }
enum Compression { None = 0, Gzip = 1 }

impl Header {
    fn encode(&self) -> [u8; 4] {
        [
            (self.protocol_version << 4) | self.header_size,
            ((self.message_type as u8) << 4) | (self.flags & 0x0F),
            ((self.serialization as u8) << 4) | (self.compression as u8),
            0x00,
        ]
    }
    fn decode(b: [u8; 4]) -> Result<Self, AsrError> { ... }
}
```

### 7.4 Server response parsing

- Header → if `message_type == ServerError`, read 4-byte error code + 4-byte size + utf-8 message → `AsrError::Server { code, message, logid }`
- Else read 4-byte sequence + 4-byte payload_size + payload (gunzip if needed) → JSON
- Map `result.utterances[]` to `Vec<Segment>`. `definite=true` segments are stable; latest concatenation forms the partial text. Final = last response with `flags & 0b0010` (last-packet flag).
- Capture `X-Tt-Logid` from the upgrade response and stash on `DoubaoBackend.logid`. Surface it in `Final.logid` and in tracing spans (every error log includes logid for support tickets).

### 7.5 Error code mapping

| Volcengine code | AsrError variant | doctor verdict |
|---|---|---|
| 20000000 | n/a (success) | ✓ |
| 45000001 | `AsrError::BadRequest` | Fail (config bug, won't self-heal) |
| 45000002 | `AsrError::EmptyAudio` | **doctor treats as ✓** — empty-audio probe success path |
| 45000081 | `AsrError::Timeout` | Warn (transient) |
| 45000151 | `AsrError::AudioFormat` | Fail (config bug) |
| 550xxxxx | `AsrError::ServerInternal { code }` | Warn |
| 55000031 | `AsrError::ServerBusy` | Warn |
| network / TLS / WS upgrade | `AsrError::Transport` | Fail with hint about endpoint reachability |

### 7.6 Tests

- [ ] **Step 1: Header roundtrip** — `tests/protocol.rs::header_roundtrips_for_all_message_types`. 4×2×2 = 16 combos, encode → decode → assert eq.
- [ ] **Step 2: Frame roundtrip** — gzip + size prefix + JSON serialize/deserialize a known FullClientRequest payload; assert byte-level equality against a hand-checked fixture.
- [ ] **Step 3: Server response parser** — `tests/protocol.rs::parses_definite_utterances` against the spec doc's JSON example (paste it as a `&str` fixture, gzip it, prepend a fake header, run through the parser).
- [ ] **Step 4: Mock server e2e** — `tests/mock_server.rs::full_session_returns_final`. Use `tokio_tungstenite::accept_async` on a tempdir-bound localhost listener. Assert: handshake headers contain auth keys; first frame is FullClientRequest with the expected JSON; second frame is AudioOnlyRequest with sequence=1; last frame has negative sequence + last-packet flag; client receives a Final with the stitched-together text.
- [ ] **Step 5: Mock server error path** — server replies with ServerError frame (code 45000002, message "empty audio") → client returns `AsrError::EmptyAudio` → doctor's check sees this and ticks ✓.
- [ ] **Step 6: Live smoke** — `tests/live.rs::handshake_only` `#[ignore]` test. Reads `VOCO_DOUBAO_APP_ID` + `VOCO_DOUBAO_ACCESS_TOKEN` env vars; if either missing, returns Ok(()) (so `cargo test` doesn't fail). Calls `start()` → `stop()` (no audio); asserts the logid header was received and the response was an EmptyAudio error. Run manually with `VOCO_DOUBAO_APP_ID=... VOCO_DOUBAO_ACCESS_TOKEN=... cargo test -p voco-asr --test live -- --ignored`.

### 7.7 Wiring into doctor (Task 4 update)

Doctor's `backend.rs` becomes:

```rust
pub fn doubao_handshake() -> CheckResult {
    let cfg = match ConfigIo::load() { Ok(c) => c, Err(e) => return CheckResult::Fail{...} };
    if cfg.doubao.is_none() { return CheckResult::Skip("doubao not configured".into()); }
    let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
    rt.block_on(async {
        let mut be = match voco_asr::build_backend(&cfg) { Ok(b) => b, Err(e) => return CheckResult::Fail{...} };
        let t0 = Instant::now();
        match be.start().await {
            Err(e) => return CheckResult::Fail { headline: format!("start failed: {e}"), fix: ... },
            Ok(()) => {}
        }
        match be.stop().await {
            Err(AsrError::EmptyAudio) => CheckResult::Ok(format!("handshake ok ({}ms, logid=...)", t0.elapsed().as_millis())),
            Err(e)                    => CheckResult::Fail { ... },
            Ok(_)                     => CheckResult::Warn { ... },   // shouldn't happen — flag for review
        }
    })
}
```

### 7.8 Steps + commit

- [ ] **Step 1:** Scaffold `voco-asr` crate, add to workspace, stub trait + sherpa stub. Compile.
- [ ] **Step 2:** `protocol.rs` (header + frame builders) with full unit coverage.
- [ ] **Step 3:** `codec.rs` gzip helpers + tests.
- [ ] **Step 4:** `types.rs` payload structs + serde tests.
- [ ] **Step 5:** `auth.rs` + `ws.rs` (auth header injection + connection setup).
- [ ] **Step 6:** `doubao/mod.rs` glue: `start` (handshake + send FullClientRequest), `feed` (buffer + send AudioOnlyRequest frames), `stop` (send last-packet, drain final, close WS).
- [ ] **Step 7:** Mock-server e2e tests pass.
- [ ] **Step 8:** Wire `doubao_handshake()` into doctor; smoke test the doctor with mock backend behind a feature flag (`#[cfg(test)]` swap-in) so CI doesn't hit the network.
- [ ] **Step 9:** Manual live probe (set env vars, run `voco doctor` against the real endpoint, paste output into commit body).
- [ ] **Step 10:** Commit:

```
feat(asr): voco-asr crate with Doubao WebSocket backend (protocol layer)

- AsrBackend trait per spec §3.3 (start/feed/stop, Partial/Final/Segment)
- DoubaoBackend implements the Volcengine binary protocol from
  ~/Downloads/volcengine-api.md (4-byte header, gzipped JSON or PCM,
  big-endian sequence numbers, last-packet flag)
- Default endpoint = bigmodel_async (双向流式优化版); old-console (App
  Key + Access Token) and new-console (X-Api-Key) auth both supported
- Mock-server tests cover: handshake, FullClientRequest framing,
  audio-only frames, last-packet, server-error path
- Doctor's "Backend handshake" check now does start()->stop() and
  treats 45000002 (empty audio) as ✓
- Sherpa backend stays a NotImplemented stub for v0.2
```

---

## Task 8: end-to-end smoke updates + final verification

- [ ] **Step 1:** Extend `crates/voco-cli/tests/smoke.rs`:
  - `wizard_save_then_show` — drive wizard via expectrl with all defaults; assert `voco config show` reflects them.
  - `set_then_reload` — start daemon, run `voco config set output.mode clipboard_only`, assert daemon reload succeeded, then `voco status` (or DumpConfig) shows the new value.
  - `doctor_in_clean_home` — `VOCO_HOME=tmp` `voco doctor` exits with code 0 (config doesn't exist yet → check skipped; daemon not running → fail; mic depends on host).
- [ ] **Step 2:** Re-run final-verification gates from Phase 1: `cargo fmt --check` / `cargo clippy --workspace --all-targets -- -D warnings` / `cargo test --workspace` / `cargo build --release --workspace`.
- [ ] **Step 3:** Manual demo, paste output into commit body.
- [ ] **Step 4:** Commit.

---

## Phase 2 — Verification (must pass before Phase 3 starts)

- [ ] All Phase 1 gates still green (fmt, clippy, test, release build, manual demo)
- [ ] `voco config` (no args) walks the wizard and saves
- [ ] `voco config show` masks `access_token`
- [ ] `voco config set <leaf-key> <value>` validates + saves + notifies daemon (best-effort)
- [ ] `voco config validate` fails (exit 1) on a corrupted file
- [ ] `voco doctor` runs all five groups, exits 0 if no Fail
- [ ] Smoke suite ≥ 6 tests, no test touches `~/Library` (all use `VOCO_HOME=tmp`)
- [ ] `voco daemon logs --lines 10` works against a date-rotated log file
- [ ] `voco config set output.mode ...` reflects in subsequent `voco status` (via DumpConfig or hash) without `daemon restart`
- [ ] `cargo test -p voco-asr` green; mock-server e2e covers handshake + frame framing + error path
- [ ] Manual: with valid Doubao creds, `voco doctor` → `Doubao handshake` ✓ within 5s, logid printed

---

## What Phase 2 explicitly does NOT do

| Item | Phase that owns it |
|---|---|
| Real audio capture (cpal `Stream::play`) | Phase 3 |
| Orchestrator-level recording state machine + partial-text streaming to UI | Phase 3 |
| Hotkey installation (CGEventTap) | Phase 4 |
| Text injection (CGEvent) | Phase 4 |
| HUD (SwiftUI) | Phase 5 |
| Keychain for `access_token` | v0.2 (post-Phase 6) |
| Sherpa local backend | v0.2 |

doctor's "Microphone access" and "Accessibility" checks **report** status only; they do not request or grant. The daemon-side TCC prompt for accessibility lands in Phase 4 when CGEventTap is wired.

---

## Open issues for Phase 3 carry-over

1. **HotkeyPreset → keycode table** is hardcoded in the wizard. Phase 4 will need the same table inside `voco-hotkey`; consider promoting it to a `voco-config::hotkey_presets` module then. Don't refactor pre-emptively — wait until Phase 4 actually consumes it.
2. **Effective-config introspection** (added in Task 6 via DumpConfig or hash on StatusInfo) — Phase 5's HUD might want to subscribe to changes; we'll know more then.
3. **Wizard's "Custom..." hotkey capture** uses crossterm raw mode. On weird terminals (tmux with funky pass-through, JetBrains-embedded terminals) this can swallow input — collect issues and consider a manual entry fallback ("type the keycode in hex").
4. **DoubaoBackend frame buffering** — Task 8 buffers ~200ms before sending. Phase 3 (orchestrator + cpal) must produce frames at that cadence anyway, so the internal buffer is mostly defensive. Once the cpal pipeline is stable, consider removing the buffer to cut ~100ms of latency, or expose `frame_ms` as a config knob.
5. **Reconnect strategy** — if the WebSocket drops mid-recording, Task 8's `feed()` returns `AsrError::Transport`. Phase 3's orchestrator should decide: stitch already-received partials as the Final, or attempt one reconnect. Spec §4.6 says option A (stitch and finalize); confirm during Phase 3 implementation.
6. **2.0 model rollout** — Task 8 defaults to ASR 1.0 (`volc.bigasr.sauc.duration`). When Doubao 2.0 (`volc.seedasr.sauc.duration`) becomes the better choice, just flip `Config::default().doubao.resource_id`; no code changes needed.

---

## Estimated scope

9 tasks, ~14-17 commits, 4-5 days of focused work. Task 8 (Doubao protocol layer) is roughly half the work — bit-level header packing + mock-server e2e is meticulous but mechanical. Everything else (wizard / doctor / reload) is plumbing built on top of Phase 1's IPC + config.
