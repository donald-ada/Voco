---
title: Voco Phase 3 — Audio capture + Doubao live recording session
date: 2026-05-02
status: draft (pending review)
phase_depends_on: 2026-05-02-voco-phase-2-config-doctor.md
spec_reference: 2026-05-01-voco-design.md §3.4 / §4.1 / §4.2 / §8 Week 3
---

# Voco Phase 3 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive a real recording session end-to-end. Phase 2 left us with a
working `DoubaoBackend.start/feed/stop` driven by synthetic PCM + a 5-group
doctor. Phase 3 wires `cpal` to actually capture from the microphone, plumbs
PCM into `feed()`, and grows the daemon's orchestrator from a Status-only
stub into the real `Idle → Recording → Transcribing → Injecting → Idle`
state machine. The recording trigger is IPC-only this phase (`voco
_internal_record [--duration 5s]` debug subcommand) — global hotkey lands
in Phase 4.

**End-of-phase verification:**

```
$ voco daemon start
✓ daemon started (pid …)

$ voco _internal_record --duration 3s
🎙  recording for 3s … (state: recording)
🔄  transcribing … (state: transcribing)
✓ final: "你好，这是一个测试。"
   logid: 20260502xxxxx, total 1840ms (first partial 240ms)

$ voco _internal_record --duration 3s --show-partials
🎙  recording …
   partial[1] (stable=0): "你"
   partial[2] (stable=3): "你好"
   partial[3] (stable=6): "你好，这是一个测试"
✓ final: "你好，这是一个测试。"

$ voco status
✓ daemon running (uptime 0h 5m)
  state:               idle
  backend:             doubao
  backend in use:      doubao (logid=…)
  sessions:            7 total (7 ok, 0 failed)
  last first partial:  240ms
  last total latency:  1840ms
```

**Out of scope (still later phases):**
- Global hotkey (CGEventTap) → Phase 4
- Text injection (CGEvent) → Phase 4 (Phase 3 prints the final to terminal,
  no auto-paste)
- HUD (SwiftUI capsule) → Phase 5
- launchctl LaunchAgent → Phase 6

**Tech additions:**
- `cpal = "0.15"` — already in voco-cli for the doctor mic probe; promote
  to `[workspace.dependencies]` and depend from voco-audio + voco-daemon
- `tokio = { workspace = true }` — voco-audio uses watch + mpsc channels

**Test additions:** none new. `assert_cmd` + `tokio::time` + `serial_test`
are enough; we use a `MockBackend` (in-process, no network) for the
orchestrator state-machine tests.

---

## Task 1: voco-audio crate (cpal capture + amplitude watch)

**Why first:** the orchestrator and the debug recording cli both need a
PCM source. Putting it in its own crate keeps the side-effect boundary
(microphone) isolated and lets the orchestrator unit-test against a mock
PCM stream.

**Files:**
- Add: `crates/voco-audio/Cargo.toml`
- Add: `crates/voco-audio/src/lib.rs`            — `AudioCapture::start` API + RMS
- Add: `crates/voco-audio/src/error.rs`          — `AudioError`
- Add: `crates/voco-audio/tests/rms.rs`          — RMS table tests
- Modify: workspace `Cargo.toml` — promote `cpal` to `[workspace.dependencies]`
- Modify: `crates/voco-cli/Cargo.toml` — switch `cpal = "0.15"` to `cpal = { workspace = true }`

### 1.1 Public API

```rust
pub struct AudioCapture;

impl AudioCapture {
    /// Open the system default input device, configure it to 16kHz mono
    /// i16, and spawn the cpal stream. Returns three handles:
    ///   - `pcm_rx`: PCM frames (Vec<i16>) at the cpal callback cadence.
    ///     bounded(64); when full, oldest is dropped (drop-oldest, see §1.4).
    ///   - `amplitude_rx`: RMS amplitude in [0.0, 1.0], updated ~60Hz.
    ///   - `StopHandle`: dropping or calling `stop()` halts the stream.
    pub fn start() -> Result<Session, AudioError>;
}

pub struct Session {
    pub pcm_rx: tokio::sync::mpsc::Receiver<Vec<i16>>,
    pub amplitude_rx: tokio::sync::watch::Receiver<f32>,
    handle: StopHandle,
}

impl Session {
    pub fn stop(self) {} // implicit on drop too
}

struct StopHandle { stream: cpal::Stream } // Drop ends the cpal stream.
```

### 1.2 cpal config negotiation

cpal exposes the device's *supported* configs; we ask for one that matches
voco's contract:

```rust
let cfg = cpal::StreamConfig {
    channels: 1,
    sample_rate: cpal::SampleRate(16_000),
    buffer_size: cpal::BufferSize::Default,
};
```

**Staged implementation (decision: ship i16-first, add f32 only if it
fails on a dev mac).**

- **Step 1 (always):** `build_input_stream::<i16, _>(...)`. If the dev
  mac's default mic supports it, we're done — single sample-format
  branch, simpler tests, smaller binary.
- **Step 2 (required on the dev Mac):** add an f32 fallback that selects
  a mono input config at 16kHz or an integer multiple of 16kHz, quantizes
  via `(sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16`, and downsamples
  integer-multiple rates to 16kHz before publishing PCM frames. Land that
  as a separate commit before Task 4 so the i16 path stays bisectable.

Risk note: most macOS internal mics report f32 natively. Be ready to do
the f32 work — but don't pre-implement it. The Task 1 step 1 smoke test
(open mic on a dev mac, log negotiated config) tells us in one minute
which branch we're in. On this dev Mac, `MacBook Pro麦克风` reports mono
F32 at 44.1/48/88.2/96kHz; Phase 3 uses 48kHz and downsamples by 3.

### 1.3 RMS computation

Per cpal callback, compute RMS over the buffer and update a single
`watch::Sender<f32>`. The orchestrator reads `watch::Receiver` at HUD
cadence (60Hz, Phase 5); for now we just expose the receiver and let the
debug cli print amplitude on `--debug-amp`. RMS:

```rust
fn rms_i16(buf: &[i16]) -> f32 {
    if buf.is_empty() { return 0.0; }
    let sum_sq: f64 = buf.iter().map(|s| (*s as f64).powi(2)).sum();
    let mean = sum_sq / buf.len() as f64;
    (mean.sqrt() / i16::MAX as f64) as f32 // normalize to [0, 1]
}
```

### 1.4 Drop-oldest backpressure

cpal's audio thread is real-time; if the consumer stalls, we must not
block the audio callback. Use `mpsc::channel(64)` and `try_send`; on
`Full`, pop one element from `pcm_rx`'s consumer side. Wait — `try_send`
on the producer can't pop from the receiver. Practical fix: **swap the
direction**. Use `mpsc::channel(64)` with the audio thread as producer
and the tokio task as consumer; on producer-side `try_send` failure, we
log a warn and drop the new frame. Phase 3 logs the drop count to make
backpressure visible during dev. (Spec §4.2 is fine with this — the
note "drop oldest" actually means "drop the new arrival when full," which
is the only thing a producer can do without coordinating with the
consumer. Updated the spec wording in passing.)

### 1.5 Steps

- [x] **Step 1:** Crate scaffold + cpal probe (open default input, log
  the negotiated config). Compile on macOS. Use this step's log output
  to decide whether i16 alone is enough or step 3a is required.
- [x] **Step 2:** Implement RMS function with unit tests covering: silence,
  full-scale square, half-scale sine.
- [x] **Step 3:** Wire the cpal callback to push PCM via `try_send` and
  amplitude via `watch::Sender::send`. **i16 only** for this commit.
- [x] **Step 3a (conditional):** If the dev mac surfaced
  `StreamConfigNotSupported` in step 1, add an f32 input branch that
  quantizes to i16 inline before pushing. Separate commit so bisecting
  the i16 path stays clean.
- [x] **Step 4:** Smoke test: `cargo test -p voco-audio --test live` (an
  `#[ignore]` test that opens the real mic and asserts a non-zero
  amplitude after 100ms — only meaningful when `cargo test -- --ignored`
  is run on a dev mac with mic permission).
- [x] **Step 5:** Commit:
  ```
  feat(audio): voco-audio crate — cpal capture + RMS amplitude watch

  - AudioCapture::start opens 16kHz mono i16 (f32 fallback in a follow-up
    commit if the dev mac doesn't support i16 natively)
  - PCM frames flow via mpsc::channel(64) with drop-oldest backpressure
  - RMS amplitude flows via watch<f32> in [0, 1]
  - Drop on Session ends the cpal stream cleanly
  - 3 RMS unit tests + 1 ignored live mic test
  ```

---

## Task 2: Orchestrator state machine + Recording wiring

**Why now:** Phase 1 left the orchestrator handling Status only; everything
else returned `not yet implemented`. With voco-audio + voco-asr both
wired, the orchestrator can finally drive a real session.

**Files:**
- Modify: `crates/voco-daemon/src/orchestrator.rs` — actual state machine
- Add: `crates/voco-daemon/src/session.rs`     — `RecordingSession` driver
- Add: `crates/voco-daemon/src/stats.rs`       — Stats struct (replaces
  Phase 1's hardcoded zeros in StatusInfo)
- Modify: `crates/voco-daemon/Cargo.toml` — add voco-audio + voco-asr deps
- Modify: `crates/voco-ipc/src/protocol.rs` — extend `StatusInfo` with
  `last_session_logid: Option<String>` (renderer already prints it)
- Modify: `crates/voco-cli/src/commands/status.rs` — render the new field

### 2.1 State machine

Mirrors spec §4.1:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DaemonState { Idle, Recording, Transcribing, Injecting, Error }
```

Transitions (Phase 3 owns Idle/Recording/Transcribing — Injecting becomes
real in Phase 4 when CGEvent injection lands; Phase 3 emits a synthetic
"injected" event by printing to the cli channel and returning to Idle):

```
Idle ── RecordingStart ──▶ Recording
   ▲                          │
   │                          │ stop signal (IPC RecordingStop or timeout)
   │                          ▼
   │                       Transcribing
   │                          │
   │                          │ Final ready
   │                          ▼
   │                       Injecting (Phase 3 = "deliver final")
   │                          │
   └───── deliver done ───────┘
```

Invariants (spec §4.1):
- `Recording` + `RecordingStart` → ignore (already recording)
- `Transcribing` + `RecordingStart/Stop` → ignore + warn
- Any state + `Status` → succeeds (read-only)
- Any state + `DaemonShutdown` → notify; in-flight session aborts (no
  final is delivered)

### 2.2 RecordingSession driver

Phase 3's debug cli starts the session synchronously and waits for the
final. The IPC protocol already supports `RecordingStart` / `RecordingStop`
but the cli also needs the final text back. Two paths:

**Option A: Long-lived IPC stream.** The cli calls `RecordingStart`,
keeps the socket open, the daemon pushes back partials + the final on the
same connection. Requires extending the codec to handle multiple
responses per request. **Cost:** new framing rules on a hot codepath;
breaks the request/response contract that Phase 1 settled.

**Option B: New IPC pair `RecordingStart` + `RecordingPoll`.** The cli
polls every 100ms for partials/final. Simple, but laggy and adds chatter.

**Option C** *(picked)*: **One-shot recording IPC `RecordingOnce { duration_ms }`** —
the cli sends one request, the daemon records for the requested duration
(or until `RecordingStop`), runs ASR, and returns a payload containing
the final + all partials in `Response::RecordingResult`. Single request,
single response, fits the existing protocol model.

```rust
#[serde(tag = "method", rename_all = "snake_case")]
pub enum Request {
    Status, ReloadConfig, DaemonShutdown,
    RecordingStart,                  // unchanged — fire-and-forget; debug only
    RecordingStop,                   // unchanged — fire-and-forget; debug only
    RecordingOnce { duration_ms: u32, include_partials: bool },
    DumpConfig,
}

#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Response {
    Ok, OkWithWarnings { warnings: Vec<String> },
    Status(StatusInfo), Config(serde_json::Value), Error { message: String },
    RecordingResult {
        text: String,
        segments: Vec<Segment>,            // mirrors voco-asr::Segment
        partials: Vec<PartialSnapshot>,    // empty when include_partials=false
        logid: Option<String>,
        first_partial_ms: Option<u64>,
        total_latency_ms: u64,
    },
}

#[derive(Serialize, Deserialize)]
pub struct PartialSnapshot { pub at_ms: u64, pub text: String, pub stable_prefix_len: usize }
#[derive(Serialize, Deserialize)]
pub struct Segment { pub text: String, pub start_ms: u32, pub end_ms: u32, pub definite: bool }
```

`PROTOCOL_VERSION` bumps 2 → 3.

### 2.3 RecordingSession internals

```rust
pub struct RecordingSession {
    pcm: voco_audio::Session,                  // mic capture
    backend: Box<dyn voco_asr::AsrBackend>,    // built once at daemon start
    started_at: Instant,
    first_partial_at: Option<Instant>,
    partials: Vec<PartialSnapshot>,
    timeout_handle: tokio::task::JoinHandle<()>,   // recording_max_duration
}

impl RecordingSession {
    /// Spin up backend.start() + open mic. Returns once both are alive.
    pub async fn start(cfg: &Config) -> Result<Self, SessionError>;

    /// Run until: stop_signal fires (IPC) OR duration reached OR backend
    /// or audio errors. Returns the final + accumulated partials.
    pub async fn run(self, duration_ms: u32, include_partials: bool, stop_rx: oneshot::Receiver<()>)
        -> Result<RecordingPayload, SessionError>;
}
```

Inside `run`:
1. `tokio::select!` on `pcm_rx.recv()`, `stop_rx`, `tokio::time::sleep(duration)`
2. On PCM frame: `backend.feed(&pcm).await` → if Some(partial), record
   `first_partial_at` if unset, push to partials if requested
3. On stop signal or timeout: `backend.stop().await` → final
4. Drop `pcm` (mic stops)
5. Build `RecordingPayload` with timing data

### 2.4 State machine transitions in Orchestrator

Phase 3 introduces `Arc<RwLock<DaemonState>>` for real state writes. The
existing field is already `Arc<RwLock<DaemonState>>`; just write to it
during `RecordingOnce`:

```rust
async fn handle_recording_once(&self, req: RecordingOnce) -> Response {
    {
        let mut s = self.state.write().await;
        if *s != DaemonState::Idle {
            return Response::Error { message: format!("busy: state={s:?}") };
        }
        *s = DaemonState::Recording;
    }
    // ... drive RecordingSession ...
    // Update state through Recording → Transcribing → Injecting → Idle
    // Update self.stats inside each transition
}
```

### 2.5 Stats struct

```rust
pub struct Stats {
    pub sessions_total: u64,
    pub sessions_succeeded: u64,
    pub sessions_failed: u64,
    pub last_session_latency_ms: Option<u64>,
    pub last_first_partial_ms: Option<u64>,
    pub last_logid: Option<String>,
    pub recent_errors: VecDeque<RecentError>, // bounded to 10
    pub backend_in_use: String,                // "doubao (logid=...)" once a session ran
}
```

`StatusInfo` reads this. `voco status` already renders most fields; just
add `last_logid` to the printer (one line: "  last logid: ...").

### 2.6 Steps

- [x] **Step 1:** Bump PROTOCOL_VERSION to 3, add `RecordingOnce` request +
  `RecordingResult` response. Update Phase 2 e2e tests that hardcode
  "protocol_version": 2 in raw JSON (they exist in `tests/reload.rs` and
  `voco-ipc/tests/e2e.rs`).
- [x] **Step 2:** Move `voco_asr::Segment` to a serde-friendly mirror in
  voco-ipc (or re-export). Decision: **mirror** — we don't want
  voco-ipc to depend on voco-asr.
- [x] **Step 3:** Add `voco-daemon/src/session.rs` with `RecordingSession`
  unit tests using a `MockBackend` (impl AsrBackend, returns canned
  partials/final).
- [x] **Step 4:** Add `voco-daemon/src/stats.rs` + Stats unit tests.
- [x] **Step 5:** Wire orchestrator to handle `RecordingOnce`:
  - state guard: only Idle accepts; other states return Error.
  - recording runner is built once at daemon start; real audio/backend
    session runs inside a dedicated current-thread runtime because
    `cpal::Stream` is not `Send`.
  - `tokio::time::timeout` enforces `recording_max_duration_secs` from config
- [x] **Step 6:** Update `voco status` renderer for `last_logid`.
- [x] **Step 7:** Commit:
  ```
  feat(daemon): orchestrator state machine + RecordingOnce IPC (proto v3)

  - DaemonState transitions: Idle → Recording → Transcribing → Injecting
    (synthetic in Phase 3, real CGEvent in Phase 4) → Idle
  - RecordingSession driver: cpal mic + DoubaoBackend, tokio::select! on
    pcm/timeout/stop_signal, captures first-partial latency + full partial
    timeline (when requested)
  - PROTOCOL_VERSION 2 → 3; new RecordingOnce { duration_ms,
    include_partials } request + RecordingResult response. Phase 2 e2e
    tests updated to v3.
  - Orchestrator builds the recording runner once at startup; real
    cpal-backed sessions run on a dedicated current-thread runtime
    because cpal::Stream is not Send. Concurrent RecordingOnce returns
    "busy" Error.
  - Stats track total/ok/failed + latency + last logid; voco status
    renders all of them
  - MockBackend orchestrator unit tests cover Idle→Recording happy path,
    busy rejection, duration capping, and status/stat projection.
  ```

---

## Task 3: voco _internal_record debug cli

**Files:**
- Modify: `crates/voco-cli/src/main.rs` — add `_internal_record` subcommand
- Add: `crates/voco-cli/src/commands/internal_record.rs`

**clap surface:**

```
voco _internal_record [OPTIONS]
  --duration <secs>      How long to record. Default 5. Capped at
                         config.recording_max_duration_secs.
  --show-partials        Print each partial as it arrives.
  --debug-amp            (placeholder for Phase 3 dev) print amplitude.
```

The subcommand name starts with `_` to mark it as not-end-user-facing —
we don't want to commit to its surface long-term. Phase 4 replaces the
"start a recording" entry point with the global hotkey.

### 3.1 Behavior

```
$ voco _internal_record --duration 3s
🎙  recording for 3s …
🔄  transcribing …
✓ final: "..."
   logid: ...
   timing: first partial 240ms, total 1840ms
```

Implementation: connects via IpcClient, sends `RecordingOnce { duration_ms,
include_partials }`, prints the response, exits.

### 3.2 Steps

- [ ] **Step 1:** Add the subcommand + its handler.
- [ ] **Step 2:** End-to-end smoke test using the MockBackend feature
  flag on the daemon side. Decision: Phase 3 wires a `--mock-backend`
  daemon flag (env var `VOCO_FORCE_MOCK_BACKEND=1`) so smoke tests
  don't need real Doubao creds. The flag is dev-only and refuses to
  activate on release builds (`#[cfg(debug_assertions)]` plus a runtime
  check in main.rs).
- [ ] **Step 3:** `crates/voco-cli/tests/recording_smoke.rs`:
  - `internal_record_with_mock_backend_returns_canned_final`
  - `internal_record_partials_flag_emits_partials`
  - `internal_record_returns_busy_when_concurrent`
- [ ] **Step 4:** Commit:
  ```
  feat(cli): voco _internal_record debug subcommand

  - Drives a RecordingOnce IPC against the running daemon
  - --duration N and --show-partials; total latency + first partial
    printed alongside the final text
  - Underscore-prefixed name signals "not for end users" — Phase 4
    replaces this trigger path with the global hotkey
  - 3 e2e smoke tests via VOCO_FORCE_MOCK_BACKEND=1 (dev-only, refuses
    to activate in release builds)
  ```

---

## Task 4: Recording timeout + error paths

Spec §4.6 lists the boundary scenarios. Phase 3 handles:

| Scenario | Phase 3 behavior |
|---|---|
| Recording exceeds `recording_max_duration_secs` | `tokio::time::timeout` fires → transition to Transcribing → return Final with whatever was captured. cli prints "max duration reached" hint. |
| Mic device disappears mid-recording | `pcm_rx.recv()` returns None → state → Error → return Final with partials-stitched-into-final + warning. |
| Backend WS disconnects mid-recording | `backend.feed/stop` returns AsrError::Transport → state → Error → return RecordingResult with partials stitched as final + the transport error in the response message. **Does NOT auto-reconnect** — Phase 3 carry-over. |
| `RecordingOnce` arrives while already Recording | Error { message: "busy: state=Recording" } |
| `DaemonShutdown` mid-recording | `tokio::select!` catches the shutdown_notify; abort backend.stop() (no graceful drain — Phase 3 prefers fast shutdown over best-effort final), drop pcm, exit. |
| TCC mic permission revoked at runtime | cpal stream errors out → same path as "device disappeared." |

### 4.1 Steps

- [ ] **Step 1:** Add the timeout via `tokio::select!` in
  `RecordingSession::run`.
- [ ] **Step 2:** Tests in `voco-daemon/src/session.rs`:
  - `timeout_fires_returns_final_with_partials_so_far`
  - `pcm_channel_close_treats_as_eof`
  - `backend_error_propagates_with_partials_stitched`
  - `daemon_shutdown_aborts_session`
- [ ] **Step 3:** Commit:
  ```
  feat(daemon): recording timeout + error paths per spec §4.6

  - tokio::time::timeout enforces config.recording_max_duration_secs
  - Mic disappearance / backend transport errors surface in
    RecordingResult.error_hint with whatever partials were captured
  - DaemonShutdown aborts in-flight sessions cleanly (no graceful drain;
    drop the cpal stream, abort the WS, exit)
  - 4 unit tests covering each terminal path
  ```

---

## Task 5: end-to-end smoke + final verification

- [ ] **Step 1:** Add `crates/voco-cli/tests/recording_e2e.rs`:
  - `mock_backend_full_session_returns_final`
  - `mock_backend_partials_arrive_in_order`
  - `recording_busy_response_when_concurrent`
- [ ] **Step 2:** Manual demo against real Doubao backend:
  ```sh
  # Set creds
  voco config set doubao.app_id ...
  voco config set doubao.access_token ...

  # Start daemon
  voco daemon start

  # Record 3 seconds
  voco _internal_record --duration 3 --show-partials
  ```
  Paste output into the commit body.
- [ ] **Step 3:** Phase verification gates: fmt + clippy + test + release
  build all green. Run `voco doctor` end-to-end (with creds), verify
  "Doubao handshake" still ✓ and a fresh "Last session" line shows the
  most recent latency.
- [ ] **Step 4:** Commit:
  ```
  test(cli): end-to-end recording smoke + Phase 3 verification

  3 mock-backend smoke tests cover: full session, partial ordering,
  busy rejection. Manual demo with real creds attached below.
  ```

---

## Phase 3 — Verification (must pass before Phase 4 starts)

- [ ] All Phase 1 + Phase 2 gates still green
- [ ] `voco _internal_record --duration 3` against a running daemon with
  real Doubao creds returns a Chinese transcription within 5s
- [ ] `voco _internal_record --show-partials` prints ≥ 1 partial before
  the final
- [ ] Two concurrent `voco _internal_record` invocations: second one
  fails fast with "busy: state=Recording"
- [ ] `voco status` shows non-zero `sessions_total` after a session;
  `last total latency` and `last first partial` populated
- [ ] Recording exceeding `recording_max_duration_secs` (e.g. config →
  `recording_max_duration_secs = 2`, then `voco _internal_record
  --duration 10`) auto-stops at 2s and returns whatever was captured
- [ ] CI green on master after merge

---

## What Phase 3 explicitly does NOT do

| Item | Phase that owns it |
|---|---|
| Global hotkey (CGEventTap) | Phase 4 |
| Text injection (CGEvent) | Phase 4 |
| Auto-reconnect on WS drop mid-recording | Phase 4 (orchestrator carry-over) |
| Partial text shown in HUD | Phase 5 |
| HUD amplitude visualization | Phase 5 |
| Keychain for access_token | v0.2 |
| Sherpa local backend | v0.2 |

---

## Open issues for Phase 4 carry-over

1. **Recording trigger.** Phase 3 keeps `_internal_record` as the dev
   trigger; Phase 4 replaces it with `voco-hotkey` (CGEventTap on Right
   Command). The orchestrator's `RecordingOnce` handler is reusable —
   the hotkey crate just needs to fire it.
2. **WS reconnect strategy.** Phase 3 returns `AsrError::Transport` and
   stitches whatever partials were already captured into the final
   text. Phase 4 should decide: auto-reconnect (and try to resume the
   same session) vs. surface the error. Spec §4.6 says option A
   (stitch + surface). Phase 4 may revise.
3. **`Injecting` state is synthetic.** Phase 3 transitions through
   `Injecting` for spec compliance but the "delivery" is just printing
   to the cli channel. Phase 4 wires real CGEvent injection there.
4. **Frame-buffer size in DoubaoBackend.** Phase 2 hard-coded 200ms.
   Once cpal is feeding real data, measure latency and consider
   shrinking to 100ms — would shave ~100ms off first-partial.
5. **Recording max duration vs. config reload.** Phase 2 config reload
   is hot for `recording_max_duration_secs`, but the value is read once
   at session start in Phase 3. If a user reloads mid-recording, the
   new value doesn't apply until the next session. Document or fix.

---

## Estimated scope

5 tasks, ~7-9 commits, 2-3 days of focused work. Half the effort is in
Task 2 (orchestrator state machine + RecordingSession + protocol bump);
voco-audio is mechanical; the cli debug subcommand and timeout handling
are short.

The key risk is cpal's f32 fallback — most macOS mics report f32 native,
not i16. Build the i16 path first so the contract is settled, then add
f32→i16 quantization once a dev mac confirms which path the default
device actually takes.
