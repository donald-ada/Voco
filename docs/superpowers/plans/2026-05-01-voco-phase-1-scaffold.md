# Voco Phase 1 — Scaffold + Config + IPC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Voco 从空仓库带到"`voco daemon start && voco status` 返回 idle"的可演示状态——workspace、配置、IPC、daemon 空壳、CLI 骨架全就位，但没有录音、没有识别、没有 GUI。

**Architecture:** Cargo workspace + 4 个 crate（voco-config / voco-ipc / voco-daemon / voco-cli）。daemon 是 tokio 服务进程，CLI 是同步 launcher，两者通过 Unix domain socket + length-prefixed JSON 通信。launchctl plist 留到 Phase 6 真正接入；Phase 1 用 `std::process::Command::spawn` 简单拉起子进程。

**Tech Stack:** Rust 1.78+ (stable), tokio 1, serde 1, clap 4, thiserror 1, directories 5, tracing 0.1, tracing-subscriber 0.3, tracing-appender 0.2, uuid 1, tempfile 3 (test-only).

**Spec reference:** `docs/superpowers/specs/2026-05-01-voco-design.md` §1-3, §8 Week 1.

**End-of-phase verification:**

```
$ voco daemon start
✓ daemon started (pid 12345)

$ voco status
✓ daemon running (uptime 0h 0m)
  state:           idle
  backend:         doubao
  backend in use:  (not yet implemented)

$ voco daemon stop
✓ daemon stopped
```

---

## Task 1: Workspace scaffold + tooling files

**Files:**
- Create: `Cargo.toml`
- Create: `.gitignore`
- Create: `rust-toolchain.toml`
- Create: `README.md`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
/target
**/*.rs.bk
Cargo.lock.bak
.DS_Store
.idea/
.vscode/
*.swp
/tmp
/build
*.log
.env
.env.local
```

- [ ] **Step 2: Create `rust-toolchain.toml`**

```toml
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy"]
profile = "default"
```

- [ ] **Step 3: Create root `Cargo.toml`** (workspace manifest)

```toml
[workspace]
resolver = "2"
members = [
    "crates/voco-config",
    "crates/voco-ipc",
    "crates/voco-daemon",
    "crates/voco-cli",
]

[workspace.package]
edition = "2021"
rust-version = "1.78"
license = "MIT"
authors = ["Voco contributors"]
repository = "https://github.com/zhangxiaolong/voco"

[workspace.dependencies]
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "1"
anyhow = "1"
clap = { version = "4", features = ["derive"] }
directories = "5"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }
tracing-appender = "0.2"
uuid = { version = "1", features = ["v4", "serde"] }
tempfile = "3"

[profile.release]
opt-level = 3
lto = "thin"
codegen-units = 1
strip = "symbols"
```

- [ ] **Step 4: Create minimal `README.md`**

```markdown
# Voco

Terminal-controlled local/cloud STT voice input tool for macOS.

See `docs/superpowers/specs/2026-05-01-voco-design.md` for the full design.

## Status

Phase 1 (scaffold) in progress. Not yet usable as a voice-input tool.

## Build

```sh
cargo build --release
```

## License

MIT
```

- [ ] **Step 5: Commit (workspace verify is deferred until Task 3 adds the first member crate)**

```sh
git add Cargo.toml .gitignore rust-toolchain.toml README.md
git commit -m "chore: scaffold Cargo workspace and tooling

- workspace with 4 placeholder members (config/ipc/daemon/cli)
- pinned to stable channel
- shared deps in [workspace.dependencies]
- placeholder README"
```

---

## Task 2: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create CI workflow**

```yaml
name: CI

on:
  push:
    branches: [master, main]
  pull_request:

jobs:
  rust:
    strategy:
      fail-fast: false
      matrix:
        os: [macos-14]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: rustfmt, clippy
      - uses: Swatinem/rust-cache@v2
      - name: fmt
        run: cargo fmt --all -- --check
      - name: clippy
        run: cargo clippy --workspace --all-targets -- -D warnings
      - name: test
        run: cargo test --workspace --all-targets
      - name: build release
        run: cargo build --release --workspace
```

`macos-15` is added to the matrix in Phase 6 once SwiftUI builds enter the picture; Phase 1 is Rust-only so a single runner is enough.

- [ ] **Step 2: Commit**

```sh
git add .github/workflows/ci.yml
git commit -m "ci: add macOS Rust workflow (fmt + clippy + test + release build)"
```

---

## Task 3: voco-config — schema types

**Files:**
- Create: `crates/voco-config/Cargo.toml`
- Create: `crates/voco-config/src/lib.rs`
- Create: `crates/voco-config/src/schema.rs`

- [ ] **Step 1: Create crate manifest**

```toml
# crates/voco-config/Cargo.toml
[package]
name = "voco-config"
version = "0.1.0"
edition.workspace = true
rust-version.workspace = true
license.workspace = true

[dependencies]
serde = { workspace = true }
serde_json = { workspace = true }
toml = "0.8"
thiserror = { workspace = true }
directories = { workspace = true }
tracing = { workspace = true }

[dev-dependencies]
tempfile = { workspace = true }
```

- [ ] **Step 2: Create `src/schema.rs` — all data types**

```rust
//! Configuration schema. Pure data — no IO, no validation here.
//! IO lives in `io.rs`, validation lives in `validate.rs`.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Config {
    pub backend: BackendChoice,
    pub hotkey: HotkeyConfig,
    pub output: OutputConfig,
    pub hud: HudConfig,
    pub doubao: Option<DoubaoCreds>,
    pub sherpa: Option<SherpaPaths>,
    pub log_level: LogLevel,
    pub recording_max_duration_secs: u32,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum BackendChoice {
    Doubao,
    Sherpa,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HotkeyConfig {
    pub keycode: u16,
    pub modifiers: u32,
    pub display_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OutputConfig {
    pub mode: OutputMode,
    pub trim_trailing_punct: bool,
    pub auto_capitalize: bool,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OutputMode {
    InjectThenClipboard,
    ClipboardOnly,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HudConfig {
    pub style: HudStyle,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum HudStyle {
    Capsule,
    Minimal,
    Disabled,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DoubaoCreds {
    pub app_id: String,
    pub access_token: String,
    pub endpoint: String,
    pub model_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SherpaPaths {
    pub model_dir: PathBuf,
    pub num_threads: usize,
    pub provider: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            backend: BackendChoice::Doubao,
            hotkey: HotkeyConfig {
                // Right Command. CGKeyCode 54 = kVK_RightCommand.
                keycode: 54,
                modifiers: 0,
                display_name: "Right Command".to_string(),
            },
            output: OutputConfig {
                mode: OutputMode::InjectThenClipboard,
                trim_trailing_punct: false,
                auto_capitalize: false,
            },
            hud: HudConfig {
                style: HudStyle::Capsule,
            },
            doubao: None,
            sherpa: None,
            log_level: LogLevel::Info,
            recording_max_duration_secs: 60,
        }
    }
}
```

- [ ] **Step 3: Create `src/lib.rs` — re-exports (Phase 1 only adds `schema`; `io` and `validate` arrive in Tasks 4 and 5)**

```rust
//! Voco configuration: schema, IO, validation.
//!
//! Three layers (added incrementally over Tasks 3-5):
//! * `schema` — pure data types
//! * `io`     — load/save with atomic writes
//! * `validate` — semantic checks before applying

pub mod schema;

pub use schema::*;
```

- [ ] **Step 4: Verify the crate builds**

Run: `cargo build --package voco-config`
Expected: `Compiling voco-config v0.1.0 ... Finished`

- [ ] **Step 5: Commit**

```sh
git add crates/voco-config
git commit -m "feat(config): introduce Config schema with serde derives

All struct/enum types described in spec §3.1, plus Default impl
that matches spec defaults (Right Command hotkey, Doubao backend,
inject-then-clipboard output, 60s recording cap)."
```

---

## Task 4: voco-config — load/save with atomic write

**Files:**
- Create: `crates/voco-config/src/io.rs`
- Modify: `crates/voco-config/src/lib.rs`
- Create: `crates/voco-config/tests/roundtrip.rs`

- [ ] **Step 1: Write the failing test**

```rust
// crates/voco-config/tests/roundtrip.rs
use voco_config::{ConfigIo};
use voco_config::schema::Config;

#[test]
fn default_roundtrips_through_disk() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("config.toml");

    let original = Config::default();
    ConfigIo::save_to(&path, &original).expect("save");

    let loaded = ConfigIo::load_from(&path).expect("load");
    assert_eq!(loaded, original);
}

#[test]
fn load_missing_returns_default() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("does_not_exist.toml");
    let loaded = ConfigIo::load_from(&path).expect("load");
    assert_eq!(loaded, Config::default());
}

#[test]
fn save_is_atomic() {
    // Save twice; intermediate files must not leak.
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("config.toml");
    ConfigIo::save_to(&path, &Config::default()).unwrap();
    ConfigIo::save_to(&path, &Config::default()).unwrap();

    let entries: Vec<_> = std::fs::read_dir(dir.path())
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().to_string())
        .collect();
    assert_eq!(entries, vec!["config.toml".to_string()]);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p voco-config --test roundtrip`
Expected: compile error — `ConfigIo` is unresolved.

- [ ] **Step 3: Implement `src/io.rs`**

```rust
//! Atomic load/save for `Config`.

use crate::schema::Config;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("TOML deserialize error: {0}")]
    Deserialize(#[from] toml::de::Error),
    #[error("TOML serialize error: {0}")]
    Serialize(#[from] toml::ser::Error),
    #[error("validation failed: {0}")]
    Validation(String),
}

pub struct ConfigIo;

impl ConfigIo {
    /// Default path: `~/.config/voco/config.toml`.
    pub fn default_path() -> PathBuf {
        directories::BaseDirs::new()
            .map(|b| b.home_dir().join(".config").join("voco").join("config.toml"))
            .unwrap_or_else(|| PathBuf::from("./voco-config.toml"))
    }

    /// Load from `default_path()`. Returns `Config::default()` if file is absent.
    pub fn load() -> Result<Config, ConfigError> {
        Self::load_from(&Self::default_path())
    }

    pub fn load_from(path: &Path) -> Result<Config, ConfigError> {
        match fs::read_to_string(path) {
            Ok(s) => Ok(toml::from_str(&s)?),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Config::default()),
            Err(e) => Err(e.into()),
        }
    }

    /// Atomic write: write to `<path>.tmp` then rename.
    pub fn save(cfg: &Config) -> Result<(), ConfigError> {
        Self::save_to(&Self::default_path(), cfg)
    }

    pub fn save_to(path: &Path, cfg: &Config) -> Result<(), ConfigError> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }

        let content = toml::to_string_pretty(cfg)?;

        let tmp = path.with_extension(
            path.extension()
                .map(|e| format!("{}.tmp", e.to_string_lossy()))
                .unwrap_or_else(|| "tmp".to_string()),
        );

        {
            let mut f = fs::OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .open(&tmp)?;
            f.write_all(content.as_bytes())?;
            f.sync_all()?;
        }

        // chmod 600 to protect plaintext access_token (spec §3.1).
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600))?;
        }

        fs::rename(&tmp, path)?;
        Ok(())
    }
}
```

- [ ] **Step 4: Re-export `io` from `lib.rs`**

```rust
// crates/voco-config/src/lib.rs (replace previous content)
pub mod io;
pub mod schema;

pub use io::{ConfigError, ConfigIo};
pub use schema::*;
```

- [ ] **Step 5: Run test to verify pass**

Run: `cargo test -p voco-config --test roundtrip`
Expected: 3 passed.

- [ ] **Step 6: Run clippy**

Run: `cargo clippy -p voco-config -- -D warnings`
Expected: no warnings.

- [ ] **Step 7: Commit**

```sh
git add crates/voco-config
git commit -m "feat(config): atomic load/save to ~/.config/voco/config.toml

- Default path via directories::BaseDirs
- Atomic write: temp file + rename
- chmod 600 on Unix to protect plaintext access_token
- Missing file returns Config::default()
- Tests cover roundtrip, missing-file, and atomicity"
```

---

## Task 5: voco-config — validate

**Files:**
- Create: `crates/voco-config/src/validate.rs`
- Modify: `crates/voco-config/src/lib.rs`
- Create: `crates/voco-config/tests/validate.rs`

- [ ] **Step 1: Write the failing test**

```rust
// crates/voco-config/tests/validate.rs
use std::path::PathBuf;
use voco_config::schema::*;
use voco_config::validate::ValidationKind;

fn cfg_with_backend(backend: BackendChoice) -> Config {
    Config { backend, ..Config::default() }
}

#[test]
fn default_is_invalid_in_strict_mode() {
    // Default has backend=Doubao but no creds. Strict mode rejects.
    let cfg = Config::default();
    let errors = cfg.validate();
    assert_eq!(errors.len(), 1);
    assert!(matches!(errors[0].kind, ValidationKind::DoubaoCredsMissing));
}

#[test]
fn doubao_with_creds_is_valid() {
    let mut cfg = cfg_with_backend(BackendChoice::Doubao);
    cfg.doubao = Some(DoubaoCreds {
        app_id: "x".into(),
        access_token: "y".into(),
        endpoint: "wss://example.invalid/asr".into(),
        model_id: "bigmodel-streaming".into(),
    });
    assert!(cfg.validate().is_empty());
}

#[test]
fn sherpa_without_paths_fails() {
    let cfg = cfg_with_backend(BackendChoice::Sherpa);
    let errors = cfg.validate();
    assert!(errors.iter().any(|e| matches!(e.kind, ValidationKind::SherpaPathsMissing)));
}

#[test]
fn sherpa_with_nonexistent_dir_fails() {
    let mut cfg = cfg_with_backend(BackendChoice::Sherpa);
    cfg.sherpa = Some(SherpaPaths {
        model_dir: PathBuf::from("/definitely/does/not/exist/voco-test"),
        num_threads: 2,
        provider: "cpu".into(),
    });
    let errors = cfg.validate();
    assert!(errors.iter().any(|e| matches!(e.kind, ValidationKind::SherpaModelDirMissing)));
}

#[test]
fn doubao_with_empty_token_fails() {
    let mut cfg = cfg_with_backend(BackendChoice::Doubao);
    cfg.doubao = Some(DoubaoCreds {
        app_id: "x".into(),
        access_token: "".into(),
        endpoint: "wss://example.invalid/asr".into(),
        model_id: "bigmodel-streaming".into(),
    });
    let errors = cfg.validate();
    assert!(errors.iter().any(|e| matches!(e.kind, ValidationKind::DoubaoCredsEmpty(_))));
}

#[test]
fn recording_max_duration_zero_fails() {
    let mut cfg = Config::default();
    cfg.doubao = Some(DoubaoCreds {
        app_id: "x".into(),
        access_token: "y".into(),
        endpoint: "wss://example.invalid/asr".into(),
        model_id: "bigmodel-streaming".into(),
    });
    cfg.recording_max_duration_secs = 0;
    let errors = cfg.validate();
    assert!(errors.iter().any(|e| matches!(e.kind, ValidationKind::RecordingMaxDurationOutOfRange)));
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p voco-config --test validate`
Expected: compile error — no `validate` module, no `validate` method.

- [ ] **Step 3: Implement `src/validate.rs`**

```rust
//! Validate that a `Config` is internally consistent and all referenced
//! resources (creds, model dirs) are usable.

use crate::schema::*;

#[derive(Debug, Clone)]
pub struct ValidationError {
    pub kind: ValidationKind,
    pub message: String,
}

#[derive(Debug, Clone)]
pub enum ValidationKind {
    DoubaoCredsMissing,
    DoubaoCredsEmpty(&'static str),
    SherpaPathsMissing,
    SherpaModelDirMissing,
    SherpaThreadsOutOfRange,
    RecordingMaxDurationOutOfRange,
    HotkeyKeycodeUnset,
}

impl Config {
    /// Returns all validation errors. Empty Vec means OK.
    pub fn validate(&self) -> Vec<ValidationError> {
        let mut errors = Vec::new();

        match self.backend {
            BackendChoice::Doubao => match &self.doubao {
                None => errors.push(ValidationError {
                    kind: ValidationKind::DoubaoCredsMissing,
                    message: "backend=doubao requires [doubao] section".into(),
                }),
                Some(c) => {
                    if c.app_id.is_empty() {
                        errors.push(ValidationError {
                            kind: ValidationKind::DoubaoCredsEmpty("app_id"),
                            message: "doubao.app_id must not be empty".into(),
                        });
                    }
                    if c.access_token.is_empty() {
                        errors.push(ValidationError {
                            kind: ValidationKind::DoubaoCredsEmpty("access_token"),
                            message: "doubao.access_token must not be empty".into(),
                        });
                    }
                    if c.endpoint.is_empty() {
                        errors.push(ValidationError {
                            kind: ValidationKind::DoubaoCredsEmpty("endpoint"),
                            message: "doubao.endpoint must not be empty".into(),
                        });
                    }
                }
            },
            BackendChoice::Sherpa => match &self.sherpa {
                None => errors.push(ValidationError {
                    kind: ValidationKind::SherpaPathsMissing,
                    message: "backend=sherpa requires [sherpa] section (note: not implemented in MVP)".into(),
                }),
                Some(s) => {
                    if !s.model_dir.is_dir() {
                        errors.push(ValidationError {
                            kind: ValidationKind::SherpaModelDirMissing,
                            message: format!(
                                "sherpa.model_dir does not exist: {}",
                                s.model_dir.display()
                            ),
                        });
                    }
                    if s.num_threads == 0 || s.num_threads > 32 {
                        errors.push(ValidationError {
                            kind: ValidationKind::SherpaThreadsOutOfRange,
                            message: format!(
                                "sherpa.num_threads must be in 1..=32, got {}",
                                s.num_threads
                            ),
                        });
                    }
                }
            },
        }

        if self.recording_max_duration_secs == 0 || self.recording_max_duration_secs > 600 {
            errors.push(ValidationError {
                kind: ValidationKind::RecordingMaxDurationOutOfRange,
                message: format!(
                    "recording_max_duration_secs must be in 1..=600, got {}",
                    self.recording_max_duration_secs
                ),
            });
        }

        if self.hotkey.keycode == 0 {
            errors.push(ValidationError {
                kind: ValidationKind::HotkeyKeycodeUnset,
                message: "hotkey.keycode 0 is reserved (kVK_ANSI_A) — pick a real key".into(),
            });
        }

        errors
    }
}
```

- [ ] **Step 4: Re-export `validate` from `lib.rs`**

```rust
// crates/voco-config/src/lib.rs
pub mod io;
pub mod schema;
pub mod validate;

pub use io::{ConfigError, ConfigIo};
pub use schema::*;
pub use validate::{ValidationError, ValidationKind};
```

- [ ] **Step 5: Run test to verify pass**

Run: `cargo test -p voco-config --test validate`
Expected: 6 passed.

- [ ] **Step 6: Run clippy**

Run: `cargo clippy -p voco-config -- -D warnings`
Expected: no warnings.

- [ ] **Step 7: Commit**

```sh
git add crates/voco-config
git commit -m "feat(config): semantic validation for Config

- backend=doubao requires non-empty [doubao] creds
- backend=sherpa requires existing [sherpa].model_dir
- recording_max_duration_secs in 1..=600
- hotkey.keycode != 0
- Returns Vec<ValidationError> so caller can show all problems at once"
```

---

## Task 6: voco-ipc — protocol types

**Files:**
- Create: `crates/voco-ipc/Cargo.toml`
- Create: `crates/voco-ipc/src/lib.rs`
- Create: `crates/voco-ipc/src/protocol.rs`

- [ ] **Step 1: Create crate manifest**

```toml
# crates/voco-ipc/Cargo.toml
[package]
name = "voco-ipc"
version = "0.1.0"
edition.workspace = true
rust-version.workspace = true
license.workspace = true

[dependencies]
serde = { workspace = true }
serde_json = { workspace = true }
thiserror = { workspace = true }
tokio = { workspace = true, optional = true }
async-trait = { version = "0.1", optional = true }
tracing = { workspace = true }
uuid = { workspace = true }

[features]
default = ["server"]
server = ["tokio", "async-trait"]
client = []     # no extra deps; uses std::os::unix::net

[dev-dependencies]
tempfile = { workspace = true }
tokio = { workspace = true }
async-trait = "0.1"
```

- [ ] **Step 2: Create `src/protocol.rs`**

```rust
//! Wire protocol for the Voco daemon control channel.
//!
//! Frame: `[length: u32 BE][JSON body]`. JSON body is an [`Envelope`].
//! Wraps either a [`Request`] or [`Response`] in `payload`.

use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

pub const PROTOCOL_VERSION: u32 = 1;
pub const MAX_FRAME_BYTES: u32 = 1024 * 1024; // 1 MiB; status payloads are tiny

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Envelope {
    pub protocol_version: u32,
    pub kind: EnvelopeKind,
    pub id: Uuid,
    pub payload: serde_json::Value,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum EnvelopeKind {
    Request,
    Response,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "method", rename_all = "snake_case")]
pub enum Request {
    Status,
    ReloadConfig,
    DaemonShutdown,
    RecordingStart,
    RecordingStop,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Response {
    Ok,
    Status(StatusInfo),
    Error { message: String },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct StatusInfo {
    pub state: String,
    pub backend: String,
    pub backend_in_use: String,
    pub uptime_secs: u64,
    pub sessions_total: u64,
    pub sessions_succeeded: u64,
    pub sessions_failed: u64,
    pub last_session_latency_ms: Option<u64>,
    pub last_first_partial_ms: Option<u64>,
    pub recent_errors: Vec<RecentError>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RecentError {
    pub timestamp_unix_secs: u64,
    pub message: String,
}

#[derive(Debug, Error)]
pub enum ProtocolError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("frame too large: {0} bytes (max {1})")]
    FrameTooLarge(u32, u32),
    #[error("json: {0}")]
    Json(#[from] serde_json::Error),
    #[error("protocol version mismatch: got {got}, expected {expected}")]
    VersionMismatch { got: u32, expected: u32 },
    #[error("kind mismatch: expected {expected}, got {got}")]
    KindMismatch { expected: &'static str, got: &'static str },
}

impl Envelope {
    pub fn new_request(req: &Request) -> Result<Self, serde_json::Error> {
        Ok(Self {
            protocol_version: PROTOCOL_VERSION,
            kind: EnvelopeKind::Request,
            id: Uuid::new_v4(),
            payload: serde_json::to_value(req)?,
        })
    }

    pub fn new_response(in_reply_to: Uuid, resp: &Response) -> Result<Self, serde_json::Error> {
        Ok(Self {
            protocol_version: PROTOCOL_VERSION,
            kind: EnvelopeKind::Response,
            id: in_reply_to,
            payload: serde_json::to_value(resp)?,
        })
    }

    pub fn decode_request(&self) -> Result<Request, ProtocolError> {
        if self.kind != EnvelopeKind::Request {
            return Err(ProtocolError::KindMismatch {
                expected: "request",
                got: "response",
            });
        }
        Ok(serde_json::from_value(self.payload.clone())?)
    }

    pub fn decode_response(&self) -> Result<Response, ProtocolError> {
        if self.kind != EnvelopeKind::Response {
            return Err(ProtocolError::KindMismatch {
                expected: "response",
                got: "request",
            });
        }
        Ok(serde_json::from_value(self.payload.clone())?)
    }
}
```

- [ ] **Step 3: Create `src/lib.rs`** (Phase 1 starts with only the protocol module; codec/server/client added in Tasks 7-9)

```rust
//! Voco IPC: typed messages + Unix-socket server/client for daemon control.

pub mod protocol;

pub use protocol::*;
```

- [ ] **Step 4: Verify the crate compiles**

Run: `cargo build -p voco-ipc`
Expected: success.

- [ ] **Step 5: Commit**

```sh
git add crates/voco-ipc
git commit -m "feat(ipc): protocol types for daemon control channel

- Envelope { protocol_version, kind, id, payload }
- Request: Status / ReloadConfig / DaemonShutdown / RecordingStart / RecordingStop
- Response: Ok / Status(StatusInfo) / Error
- ProtocolError covers io, frame size, json, version mismatch, kind mismatch
- PROTOCOL_VERSION = 1, MAX_FRAME_BYTES = 1 MiB"
```

---

## Task 7: voco-ipc — length-prefixed JSON codec (sync)

The codec is sync (no tokio) so the CLI can use it from a regular `std::os::unix::net::UnixStream` and stay zero-runtime.

**Files:**
- Create: `crates/voco-ipc/src/codec.rs`
- Modify: `crates/voco-ipc/src/lib.rs`
- Create: `crates/voco-ipc/tests/codec.rs`

- [ ] **Step 1: Write the failing test**

```rust
// crates/voco-ipc/tests/codec.rs
use std::io::Cursor;
use voco_ipc::codec::{read_envelope_blocking, write_envelope_blocking};
use voco_ipc::protocol::*;

#[test]
fn roundtrip_request() {
    let mut buf = Vec::new();
    let env = Envelope::new_request(&Request::Status).unwrap();
    write_envelope_blocking(&mut buf, &env).unwrap();

    let mut cur = Cursor::new(buf);
    let decoded = read_envelope_blocking(&mut cur).unwrap();
    assert_eq!(decoded, env);
}

#[test]
fn frame_too_large_rejected() {
    let mut buf = Vec::new();
    let too_big: u32 = MAX_FRAME_BYTES + 1;
    buf.extend_from_slice(&too_big.to_be_bytes());
    buf.extend(std::iter::repeat(0u8).take(4));

    let mut cur = Cursor::new(buf);
    let err = read_envelope_blocking(&mut cur).unwrap_err();
    assert!(matches!(err, ProtocolError::FrameTooLarge(_, _)));
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p voco-ipc --test codec`
Expected: compile error — codec module not found.

- [ ] **Step 3: Implement `src/codec.rs`**

```rust
//! Sync length-prefixed framing for [`Envelope`].

use crate::protocol::{Envelope, ProtocolError, MAX_FRAME_BYTES};
use std::io::{Read, Write};

pub fn write_envelope_blocking<W: Write>(w: &mut W, env: &Envelope) -> Result<(), ProtocolError> {
    let body = serde_json::to_vec(env)?;
    let len: u32 = body
        .len()
        .try_into()
        .map_err(|_| ProtocolError::FrameTooLarge(u32::MAX, MAX_FRAME_BYTES))?;
    if len > MAX_FRAME_BYTES {
        return Err(ProtocolError::FrameTooLarge(len, MAX_FRAME_BYTES));
    }
    w.write_all(&len.to_be_bytes())?;
    w.write_all(&body)?;
    w.flush()?;
    Ok(())
}

pub fn read_envelope_blocking<R: Read>(r: &mut R) -> Result<Envelope, ProtocolError> {
    let mut len_buf = [0u8; 4];
    r.read_exact(&mut len_buf)?;
    let len = u32::from_be_bytes(len_buf);
    if len > MAX_FRAME_BYTES {
        return Err(ProtocolError::FrameTooLarge(len, MAX_FRAME_BYTES));
    }
    let mut body = vec![0u8; len as usize];
    r.read_exact(&mut body)?;
    let env: Envelope = serde_json::from_slice(&body)?;
    Ok(env)
}
```

- [ ] **Step 4: Add `codec` to `lib.rs`**

```rust
// crates/voco-ipc/src/lib.rs
pub mod codec;
pub mod protocol;
pub use protocol::*;
```

- [ ] **Step 5: Run test to verify pass**

Run: `cargo test -p voco-ipc --test codec`
Expected: 2 passed.

- [ ] **Step 6: Run clippy**

Run: `cargo clippy -p voco-ipc -- -D warnings`
Expected: no warnings.

- [ ] **Step 7: Commit**

```sh
git add crates/voco-ipc
git commit -m "feat(ipc): sync length-prefixed JSON codec

read_envelope_blocking / write_envelope_blocking
reject frames > MAX_FRAME_BYTES (1 MiB)"
```

---

## Task 8: voco-ipc — tokio Unix server

**Files:**
- Create: `crates/voco-ipc/src/server.rs`
- Modify: `crates/voco-ipc/src/lib.rs`

- [ ] **Step 1: Implement `src/server.rs`**

```rust
//! Async Unix-domain-socket server for the daemon control channel.

use crate::codec;
use crate::protocol::{Envelope, EnvelopeKind, ProtocolError, Request, Response, PROTOCOL_VERSION, MAX_FRAME_BYTES};
use async_trait::async_trait;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{UnixListener, UnixStream};
use tracing::{debug, error, info, warn};

#[async_trait]
pub trait RequestHandler: Send + Sync + 'static {
    async fn handle(&self, req: Request) -> Response;
}

pub struct IpcServer {
    listener: UnixListener,
    socket_path: PathBuf,
}

impl IpcServer {
    /// Bind to `socket_path`. Refuses to bind if another live daemon is already
    /// listening; clears stale socket files left by crashed daemons.
    pub fn bind(socket_path: impl Into<PathBuf>) -> Result<Self, std::io::Error> {
        let socket_path = socket_path.into();
        if socket_path.exists() {
            // Probe: if we can connect, another daemon owns it.
            match std::os::unix::net::UnixStream::connect(&socket_path) {
                Ok(_) => {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::AddrInUse,
                        format!("daemon already running at {}", socket_path.display()),
                    ));
                }
                Err(_) => {
                    warn!(?socket_path, "removing stale socket");
                    std::fs::remove_file(&socket_path)?;
                }
            }
        }
        if let Some(parent) = socket_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let listener = UnixListener::bind(&socket_path)?;
        info!(?socket_path, "ipc server bound");
        Ok(Self { listener, socket_path })
    }

    pub fn socket_path(&self) -> &Path {
        &self.socket_path
    }

    /// Run forever. Each incoming connection is handled in its own task.
    pub async fn serve<H: RequestHandler>(&self, handler: Arc<H>) {
        loop {
            match self.listener.accept().await {
                Ok((stream, _addr)) => {
                    let h = handler.clone();
                    tokio::spawn(async move {
                        if let Err(e) = handle_connection(stream, h).await {
                            warn!(error = %e, "ipc connection error");
                        }
                    });
                }
                Err(e) => {
                    error!(error = %e, "accept failed");
                    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                }
            }
        }
    }
}

impl Drop for IpcServer {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.socket_path);
    }
}

async fn handle_connection<H: RequestHandler>(
    mut stream: UnixStream,
    handler: Arc<H>,
) -> Result<(), ProtocolError> {
    // Read length prefix
    let mut len_buf = [0u8; 4];
    stream.read_exact(&mut len_buf).await?;
    let len = u32::from_be_bytes(len_buf);
    if len > MAX_FRAME_BYTES {
        return Err(ProtocolError::FrameTooLarge(len, MAX_FRAME_BYTES));
    }
    let mut body = vec![0u8; len as usize];
    stream.read_exact(&mut body).await?;
    let env: Envelope = serde_json::from_slice(&body)?;

    // Version check.
    if env.protocol_version != PROTOCOL_VERSION {
        let resp = Response::Error {
            message: format!(
                "protocol version mismatch: client={}, server={}. Run `voco daemon restart`.",
                env.protocol_version, PROTOCOL_VERSION
            ),
        };
        let out = Envelope::new_response(env.id, &resp)?;
        write_async(&mut stream, &out).await?;
        return Ok(());
    }

    if env.kind != EnvelopeKind::Request {
        let resp = Response::Error {
            message: "expected request envelope".into(),
        };
        let out = Envelope::new_response(env.id, &resp)?;
        write_async(&mut stream, &out).await?;
        return Ok(());
    }

    let req: Request = serde_json::from_value(env.payload.clone())?;
    debug!(?req, "ipc request");
    let resp = handler.handle(req).await;
    let out = Envelope::new_response(env.id, &resp)?;
    write_async(&mut stream, &out).await?;
    Ok(())
}

async fn write_async(stream: &mut UnixStream, env: &Envelope) -> Result<(), ProtocolError> {
    let body = serde_json::to_vec(env)?;
    let len: u32 = body
        .len()
        .try_into()
        .map_err(|_| ProtocolError::FrameTooLarge(u32::MAX, MAX_FRAME_BYTES))?;
    stream.write_all(&len.to_be_bytes()).await?;
    stream.write_all(&body).await?;
    stream.flush().await?;
    Ok(())
}

// Re-export sync codec helpers so integration tests living next to the server
// can use either path.
pub use codec::{read_envelope_blocking, write_envelope_blocking};
```

- [ ] **Step 2: Wire up `server` module**

```rust
// crates/voco-ipc/src/lib.rs
pub mod codec;
pub mod protocol;
#[cfg(feature = "server")]
pub mod server;
pub use protocol::*;
```

- [ ] **Step 3: Compile**

Run: `cargo build -p voco-ipc`
Expected: success.

- [ ] **Step 4: Commit**

```sh
git add crates/voco-ipc
git commit -m "feat(ipc): tokio Unix-socket server with version + kind check

- IpcServer::bind detects stale sockets and refuses if a live daemon is up
- Drop impl removes the socket on shutdown
- Per-connection tokio task; protocol-version mismatch returns a typed Error
- RequestHandler trait lets the daemon plug in its own dispatch"
```

---

## Task 9: voco-ipc — sync client + end-to-end test

**Files:**
- Create: `crates/voco-ipc/src/client.rs`
- Modify: `crates/voco-ipc/src/lib.rs`
- Create: `crates/voco-ipc/tests/e2e.rs`

- [ ] **Step 1: Implement `src/client.rs`**

```rust
//! Synchronous Unix-socket client. CLI uses this — no tokio runtime needed,
//! which keeps `voco status` cold-start under 50ms.

use crate::codec::{read_envelope_blocking, write_envelope_blocking};
use crate::protocol::{Envelope, ProtocolError, Request, Response};
use std::os::unix::net::UnixStream;
use std::path::Path;
use std::time::Duration;

pub struct IpcClient {
    stream: UnixStream,
}

impl IpcClient {
    pub fn connect(socket_path: impl AsRef<Path>) -> Result<Self, ProtocolError> {
        let stream = UnixStream::connect(socket_path)?;
        stream.set_read_timeout(Some(Duration::from_secs(5)))?;
        stream.set_write_timeout(Some(Duration::from_secs(5)))?;
        Ok(Self { stream })
    }

    pub fn call(&mut self, req: &Request) -> Result<Response, ProtocolError> {
        let env = Envelope::new_request(req)?;
        write_envelope_blocking(&mut self.stream, &env)?;
        let resp_env = read_envelope_blocking(&mut self.stream)?;
        resp_env.decode_response()
    }
}
```

- [ ] **Step 2: Wire up `client` module**

```rust
// crates/voco-ipc/src/lib.rs
pub mod client;
pub mod codec;
pub mod protocol;
#[cfg(feature = "server")]
pub mod server;
pub use protocol::*;
```

- [ ] **Step 3: Write the failing end-to-end test**

```rust
// crates/voco-ipc/tests/e2e.rs
//! Spin up a real IpcServer in a tokio task and round-trip a Request through
//! the synchronous IpcClient.

use async_trait::async_trait;
use std::sync::Arc;
use voco_ipc::client::IpcClient;
use voco_ipc::protocol::*;
use voco_ipc::server::{IpcServer, RequestHandler};

struct EchoHandler;

#[async_trait]
impl RequestHandler for EchoHandler {
    async fn handle(&self, req: Request) -> Response {
        match req {
            Request::Status => Response::Status(StatusInfo {
                state: "idle".into(),
                backend: "doubao".into(),
                backend_in_use: "doubao".into(),
                uptime_secs: 0,
                sessions_total: 0,
                sessions_succeeded: 0,
                sessions_failed: 0,
                last_session_latency_ms: None,
                last_first_partial_ms: None,
                recent_errors: vec![],
            }),
            _ => Response::Ok,
        }
    }
}

#[tokio::test]
async fn status_request_roundtrips() {
    let dir = tempfile::tempdir().unwrap();
    let sock = dir.path().join("voco.sock");

    let server = IpcServer::bind(&sock).unwrap();
    let handler = Arc::new(EchoHandler);
    let serve_handle = tokio::spawn(async move {
        server.serve(handler).await;
    });

    tokio::time::sleep(std::time::Duration::from_millis(50)).await;

    let sock_clone = sock.clone();
    let resp = tokio::task::spawn_blocking(move || {
        let mut client = IpcClient::connect(&sock_clone).unwrap();
        client.call(&Request::Status).unwrap()
    })
    .await
    .unwrap();

    match resp {
        Response::Status(s) => {
            assert_eq!(s.state, "idle");
            assert_eq!(s.backend, "doubao");
        }
        other => panic!("expected Status, got {other:?}"),
    }

    serve_handle.abort();
}

#[tokio::test]
async fn version_mismatch_returns_error() {
    use std::io::{Read, Write};
    use std::os::unix::net::UnixStream as StdStream;

    let dir = tempfile::tempdir().unwrap();
    let sock = dir.path().join("voco.sock");

    let server = IpcServer::bind(&sock).unwrap();
    let handler = Arc::new(EchoHandler);
    let serve_handle = tokio::spawn(async move {
        server.serve(handler).await;
    });
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;

    let sock_clone = sock.clone();
    let resp_text = tokio::task::spawn_blocking(move || {
        let env = serde_json::json!({
            "protocol_version": 999,
            "kind": "request",
            "id": uuid::Uuid::new_v4(),
            "payload": { "method": "status" }
        });
        let body = serde_json::to_vec(&env).unwrap();
        let mut stream = StdStream::connect(&sock_clone).unwrap();
        stream.write_all(&(body.len() as u32).to_be_bytes()).unwrap();
        stream.write_all(&body).unwrap();

        let mut len_buf = [0u8; 4];
        stream.read_exact(&mut len_buf).unwrap();
        let len = u32::from_be_bytes(len_buf) as usize;
        let mut body = vec![0u8; len];
        stream.read_exact(&mut body).unwrap();
        String::from_utf8(body).unwrap()
    })
    .await
    .unwrap();

    assert!(resp_text.contains("protocol version mismatch"));
    serve_handle.abort();
}
```

- [ ] **Step 4: Run the tests**

Run: `cargo test -p voco-ipc --test e2e`
Expected: 2 passed.

- [ ] **Step 5: Run clippy**

Run: `cargo clippy -p voco-ipc --all-targets -- -D warnings`
Expected: no warnings.

- [ ] **Step 6: Commit**

```sh
git add crates/voco-ipc
git commit -m "feat(ipc): sync client + end-to-end test

- IpcClient uses std::os::unix::net::UnixStream (no tokio in CLI)
- 5s read/write timeouts to keep CLI from hanging
- e2e test: real server, real socket, real client, Status roundtrip
- e2e test: protocol-version mismatch returns typed error message"
```

---

## Task 10: voco-daemon — skeleton + Orchestrator stub

**Files:**
- Create: `crates/voco-daemon/Cargo.toml`
- Create: `crates/voco-daemon/src/lib.rs`
- Create: `crates/voco-daemon/src/main.rs`
- Create: `crates/voco-daemon/src/state.rs`
- Create: `crates/voco-daemon/src/orchestrator.rs`
- Create: `crates/voco-daemon/src/paths.rs`

- [ ] **Step 1: Create crate manifest**

```toml
# crates/voco-daemon/Cargo.toml
[package]
name = "voco-daemon"
version = "0.1.0"
edition.workspace = true
rust-version.workspace = true
license.workspace = true

[[bin]]
name = "voco-daemon"
path = "src/main.rs"

[dependencies]
voco-config = { path = "../voco-config" }
voco-ipc = { path = "../voco-ipc", features = ["server"] }
async-trait = "0.1"
tokio = { workspace = true }
serde = { workspace = true }
serde_json = { workspace = true }
thiserror = { workspace = true }
tracing = { workspace = true }
tracing-subscriber = { workspace = true }
tracing-appender = { workspace = true }
directories = { workspace = true }
anyhow = { workspace = true }
```

- [ ] **Step 2: Create `src/state.rs`**

```rust
//! Daemon state machine. Phase 1 only uses `Idle`; later phases add the rest.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum DaemonState {
    Idle,
    Recording,
    Transcribing,
    Injecting,
    Error,
}

impl DaemonState {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Recording => "recording",
            Self::Transcribing => "transcribing",
            Self::Injecting => "injecting",
            Self::Error => "error",
        }
    }
}
```

- [ ] **Step 3: Create `src/paths.rs`**

```rust
//! Filesystem paths used by the daemon. Single source of truth so cli + tests
//! agree on where the socket and log live.

use directories::BaseDirs;
use std::path::PathBuf;

pub fn application_support_dir() -> PathBuf {
    BaseDirs::new()
        .map(|b| b.data_dir().join("voco"))
        .unwrap_or_else(|| PathBuf::from("./voco-data"))
}

pub fn logs_dir() -> PathBuf {
    BaseDirs::new()
        .map(|b| b.home_dir().join("Library").join("Logs").join("voco"))
        .unwrap_or_else(|| PathBuf::from("./voco-logs"))
}

pub fn default_socket_path() -> PathBuf {
    application_support_dir().join("voco.sock")
}

pub fn default_log_file() -> PathBuf {
    logs_dir().join("voco.log")
}
```

- [ ] **Step 4: Create `src/orchestrator.rs`** (Phase 1 stub: only `Status` is wired; other requests return typed errors)

```rust
//! Phase 1 orchestrator: only knows how to answer Status.
//! Phases 2-5 progressively grow this into the full state machine in spec §4.1.

use async_trait::async_trait;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::{Notify, RwLock};
use tracing::{info, warn};
use voco_config::Config;
use voco_ipc::protocol::{Request, Response, StatusInfo};
use voco_ipc::server::RequestHandler;

use crate::state::DaemonState;

pub struct Orchestrator {
    started_at: Instant,
    state: Arc<RwLock<DaemonState>>,
    #[allow(dead_code)]
    config: Arc<RwLock<Config>>,
    shutdown: Arc<Notify>,
}

impl Orchestrator {
    pub fn new(config: Config) -> Self {
        Self {
            started_at: Instant::now(),
            state: Arc::new(RwLock::new(DaemonState::Idle)),
            config: Arc::new(RwLock::new(config)),
            shutdown: Arc::new(Notify::new()),
        }
    }

    pub fn shutdown_signal(&self) -> Arc<Notify> {
        self.shutdown.clone()
    }
}

#[async_trait]
impl RequestHandler for Orchestrator {
    async fn handle(&self, req: Request) -> Response {
        match req {
            Request::Status => {
                let state = *self.state.read().await;
                let cfg = self.config.read().await;
                Response::Status(StatusInfo {
                    state: state.as_str().into(),
                    backend: format!("{:?}", cfg.backend).to_lowercase(),
                    backend_in_use: "(not yet implemented)".into(),
                    uptime_secs: self.started_at.elapsed().as_secs(),
                    sessions_total: 0,
                    sessions_succeeded: 0,
                    sessions_failed: 0,
                    last_session_latency_ms: None,
                    last_first_partial_ms: None,
                    recent_errors: vec![],
                })
            }
            Request::DaemonShutdown => {
                info!("shutdown requested via IPC");
                self.shutdown.notify_one();
                Response::Ok
            }
            Request::ReloadConfig => {
                warn!("reload not yet implemented in Phase 1");
                Response::Error {
                    message: "reload_config: not yet implemented".into(),
                }
            }
            Request::RecordingStart | Request::RecordingStop => Response::Error {
                message: "recording: not yet implemented (Phase 3)".into(),
            },
        }
    }
}
```

- [ ] **Step 5: Create `src/lib.rs`**

```rust
pub mod orchestrator;
pub mod paths;
pub mod state;

pub use orchestrator::Orchestrator;
pub use paths::*;
pub use state::DaemonState;
```

- [ ] **Step 6: Create `src/main.rs`**

```rust
//! voco-daemon binary. Phase 1: bind IPC socket, answer Status, exit on
//! SIGTERM/SIGINT/IPC-shutdown.

use std::sync::Arc;
use tracing::{error, info};
use tracing_subscriber::EnvFilter;
use voco_config::ConfigIo;
use voco_daemon::{default_socket_path, logs_dir, Orchestrator};
use voco_ipc::server::IpcServer;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    init_logging()?;
    info!(version = env!("CARGO_PKG_VERSION"), "voco-daemon starting");

    let cfg = ConfigIo::load().unwrap_or_else(|e| {
        error!(error = %e, "failed to load config; using defaults");
        Default::default()
    });

    let socket_path = default_socket_path();
    let server = IpcServer::bind(&socket_path)?;

    let orch = Arc::new(Orchestrator::new(cfg));
    let shutdown = orch.shutdown_signal();

    let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    let mut sigint = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())?;

    let serve_handle = tokio::spawn({
        let orch = orch.clone();
        async move { server.serve(orch).await }
    });

    tokio::select! {
        _ = sigterm.recv()      => info!("SIGTERM received, exiting"),
        _ = sigint.recv()       => info!("SIGINT received, exiting"),
        _ = shutdown.notified() => info!("IPC shutdown received"),
    }

    serve_handle.abort();
    info!("voco-daemon stopped");
    Ok(())
}

fn init_logging() -> anyhow::Result<()> {
    let dir = logs_dir();
    std::fs::create_dir_all(&dir)?;
    let appender = tracing_appender::rolling::Builder::new()
        .filename_prefix("voco")
        .filename_suffix("log")
        .max_log_files(5)
        .build(&dir)?;
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info,voco=debug"));
    tracing_subscriber::fmt()
        .with_env_filter(env_filter)
        .with_writer(appender)
        .with_ansi(false)
        .json()
        .init();
    Ok(())
}
```

- [ ] **Step 7: Verify it compiles**

Run: `cargo build --bin voco-daemon`
Expected: success.

- [ ] **Step 8: Smoke test by hand**

Run (terminal A):
```sh
cargo run --bin voco-daemon
```
Expected: stays running, logs in `~/Library/Logs/voco/voco.YYYY-MM-DD.log`. Ctrl-C exits cleanly.

Run (terminal B):
```sh
ls -la ~/Library/Application\ Support/voco/voco.sock
```
Expected: socket file exists.

- [ ] **Step 9: Commit**

```sh
git add crates/voco-daemon
git commit -m "feat(daemon): Phase 1 skeleton with IPC server + Status

- DaemonState enum mirrors spec §4.1 state machine (only Idle wired in)
- Orchestrator stub answers Status; ReloadConfig/Recording return error
- IPC DaemonShutdown notifies the main loop via tokio::sync::Notify
- Logs to ~/Library/Logs/voco/ via tracing-appender (json, rotated)
- Socket at ~/Library/Application Support/voco/voco.sock
- SIGTERM/SIGINT/IPC-shutdown trigger clean shutdown; Drop removes socket"
```

---

## Task 11: voco-cli — clap skeleton + status subcommand

**Files:**
- Create: `crates/voco-cli/Cargo.toml`
- Create: `crates/voco-cli/src/main.rs`
- Create: `crates/voco-cli/src/commands/mod.rs`
- Create: `crates/voco-cli/src/commands/status.rs`
- Create: `crates/voco-cli/src/commands/daemon.rs` (stub; replaced in Task 12)
- Create: `crates/voco-cli/src/commands/config.rs` (stub; Phase 2 fills it)
- Create: `crates/voco-cli/src/commands/doctor.rs` (stub; Phase 2 fills it)

- [ ] **Step 1: Create crate manifest**

```toml
# crates/voco-cli/Cargo.toml
[package]
name = "voco-cli"
version = "0.1.0"
edition.workspace = true
rust-version.workspace = true
license.workspace = true

[[bin]]
name = "voco"
path = "src/main.rs"

[dependencies]
voco-config = { path = "../voco-config" }
voco-ipc = { path = "../voco-ipc", default-features = false, features = ["client"] }
voco-daemon = { path = "../voco-daemon" }
clap = { workspace = true }
serde = { workspace = true }
serde_json = { workspace = true }
anyhow = { workspace = true }
tracing = { workspace = true }
tracing-subscriber = { workspace = true }
```

- [ ] **Step 2: Create `src/main.rs`**

```rust
//! voco — terminal entry point.

use clap::{Parser, Subcommand};

mod commands;

#[derive(Parser)]
#[command(
    name = "voco",
    version,
    about = "Terminal-controlled voice input for macOS"
)]
struct Cli {
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Show daemon status
    Status,
    /// Daemon lifecycle: start | stop | restart | logs
    Daemon {
        #[command(subcommand)]
        action: DaemonAction,
    },
    /// Configuration: wizard | show | set | edit | reset | validate
    Config {
        #[command(subcommand)]
        action: Option<ConfigAction>,
    },
    /// Self-diagnostic
    Doctor,
}

#[derive(Subcommand)]
pub enum DaemonAction {
    Start,
    Stop,
    Restart,
    Logs {
        #[arg(short, long)]
        follow: bool,
    },
}

#[derive(Subcommand)]
pub enum ConfigAction {
    Show,
    Set { key: String, value: String },
    Edit,
    Reset,
    Validate,
}

fn main() -> anyhow::Result<()> {
    init_log();
    let cli = Cli::parse();
    match cli.command {
        Cmd::Status => commands::status::run(),
        Cmd::Daemon { action } => commands::daemon::run(action),
        Cmd::Config { action } => commands::config::run(action),
        Cmd::Doctor => commands::doctor::run(),
    }
}

fn init_log() {
    let env = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("warn"));
    let _ = tracing_subscriber::fmt()
        .with_env_filter(env)
        .with_writer(std::io::stderr)
        .with_target(false)
        .compact()
        .try_init();
}
```

- [ ] **Step 3: Create `src/commands/mod.rs`**

```rust
pub mod config;
pub mod daemon;
pub mod doctor;
pub mod status;
```

- [ ] **Step 4: Create `src/commands/status.rs`**

```rust
//! `voco status` — connect to daemon, ask for status, render human-friendly.

use anyhow::Result;
use voco_daemon::default_socket_path;
use voco_ipc::client::IpcClient;
use voco_ipc::protocol::{Request, Response, StatusInfo};

pub fn run() -> Result<()> {
    let path = default_socket_path();
    let mut client = match IpcClient::connect(&path) {
        Ok(c) => c,
        Err(_) => {
            println!("✗ daemon not running (socket: {})", path.display());
            println!("  start it with: voco daemon start");
            std::process::exit(1);
        }
    };

    match client.call(&Request::Status)? {
        Response::Status(s) => render(&s),
        Response::Error { message } => {
            eprintln!("✗ daemon error: {}", message);
            std::process::exit(1);
        }
        other => {
            eprintln!("✗ unexpected response: {:?}", other);
            std::process::exit(1);
        }
    }
    Ok(())
}

fn render(s: &StatusInfo) {
    let h = s.uptime_secs / 3600;
    let m = (s.uptime_secs % 3600) / 60;
    println!("✓ daemon running (uptime {h}h {m}m)");
    println!("  state:           {}", s.state);
    println!("  backend:         {}", s.backend);
    println!("  backend in use:  {}", s.backend_in_use);
    println!(
        "  sessions:        {} total ({} ok, {} failed)",
        s.sessions_total, s.sessions_succeeded, s.sessions_failed
    );
    if let Some(ms) = s.last_first_partial_ms {
        println!("  last first partial: {}ms", ms);
    }
    if let Some(ms) = s.last_session_latency_ms {
        println!("  last total latency: {}ms", ms);
    }
    if !s.recent_errors.is_empty() {
        println!("  recent errors:");
        for e in &s.recent_errors {
            println!("    {} — {}", e.timestamp_unix_secs, e.message);
        }
    }
}
```

- [ ] **Step 5: Create stub `src/commands/daemon.rs`** (real implementation in Task 12)

```rust
use crate::DaemonAction;
use anyhow::Result;

pub fn run(_action: DaemonAction) -> Result<()> {
    eprintln!("voco daemon: not yet implemented (Task 12 fills this in)");
    std::process::exit(1);
}
```

- [ ] **Step 6: Create stub `src/commands/config.rs`**

```rust
use crate::ConfigAction;
use anyhow::Result;

pub fn run(_action: Option<ConfigAction>) -> Result<()> {
    eprintln!("voco config: implemented in Phase 2");
    std::process::exit(1);
}
```

- [ ] **Step 7: Create stub `src/commands/doctor.rs`**

```rust
use anyhow::Result;

pub fn run() -> Result<()> {
    eprintln!("voco doctor: implemented in Phase 2");
    std::process::exit(1);
}
```

- [ ] **Step 8: Verify compile**

Run: `cargo build --workspace`
Expected: success.

- [ ] **Step 9: Smoke-test status against running daemon**

Terminal A:
```sh
cargo run --bin voco-daemon
```

Terminal B:
```sh
cargo run --bin voco -- status
```
Expected:
```
✓ daemon running (uptime 0h 0m)
  state:           idle
  backend:         doubao
  backend in use:  (not yet implemented)
  sessions:        0 total (0 ok, 0 failed)
```

- [ ] **Step 10: Commit**

```sh
git add crates/voco-cli
git commit -m "feat(cli): clap skeleton with working voco status

- Subcommands: status, daemon (start/stop/restart/logs), config, doctor
- daemon/config/doctor are stubs — Task 12 and Phase 2 fill them in
- status connects via IpcClient and prints a human summary
- IpcClient connection failure suggests 'voco daemon start'"
```

---

## Task 12: voco daemon start/stop/restart/logs (foreground mode)

Phase 1 ships **foreground daemon control**: `voco daemon start` runs `voco-daemon` as a child process, redirecting stdout/stderr to the log file. We do **not** install a launchctl plist yet — Phase 6 owns the proper LaunchAgent registration. Phase 1 is enough for development testing.

**Files:**
- Modify: `crates/voco-cli/src/commands/daemon.rs`
- Modify: `crates/voco-cli/Cargo.toml`

- [ ] **Step 1: Replace `daemon.rs` with a working implementation**

```rust
//! `voco daemon` — Phase 1 lifecycle: spawn, signal-stop, restart, tail logs.
//! Phase 6 will replace this with launchctl-managed registration.

use crate::DaemonAction;
use anyhow::{anyhow, bail, Result};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
use voco_daemon::{default_log_file, default_socket_path};
use voco_ipc::client::IpcClient;
use voco_ipc::protocol::{Request, Response};

pub fn run(action: DaemonAction) -> Result<()> {
    match action {
        DaemonAction::Start => start(),
        DaemonAction::Stop => stop(),
        DaemonAction::Restart => {
            let _ = stop();
            std::thread::sleep(Duration::from_millis(200));
            start()
        }
        DaemonAction::Logs { follow } => logs(follow),
    }
}

fn start() -> Result<()> {
    if is_daemon_running() {
        println!("✓ daemon already running");
        return Ok(());
    }

    let bin = locate_daemon_binary()?;
    let log_file = default_log_file();
    if let Some(parent) = log_file.parent() {
        std::fs::create_dir_all(parent)?;
    }

    // Phase 1 spawns the daemon as a child process with stdout/stderr piped
    // to the log file. Detachment from the controlling terminal happens in
    // Phase 6 via launchctl; for development this is enough.
    let log = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_file)?;
    let log_dup = log.try_clone()?;

    let child = Command::new(&bin)
        .stdin(Stdio::null())
        .stdout(log)
        .stderr(log_dup)
        .spawn()?;

    let pid = child.id();
    println!("✓ daemon started (pid {pid})");
    println!("  logs: {}", log_file.display());

    // Wait up to 2s for the socket to appear so 'voco status' works immediately.
    let deadline = Instant::now() + Duration::from_secs(2);
    let sock = default_socket_path();
    while Instant::now() < deadline {
        if UnixStream::connect(&sock).is_ok() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    Err(anyhow!(
        "daemon spawned but socket {} not ready after 2s — check {}",
        sock.display(),
        log_file.display()
    ))
}

fn stop() -> Result<()> {
    let sock = default_socket_path();
    let mut client = match IpcClient::connect(&sock) {
        Ok(c) => c,
        Err(_) => {
            println!("✓ daemon already stopped");
            return Ok(());
        }
    };
    match client.call(&Request::DaemonShutdown)? {
        Response::Ok => {
            println!("✓ shutdown requested; waiting for daemon to exit");
            let deadline = Instant::now() + Duration::from_secs(3);
            while Instant::now() < deadline {
                if UnixStream::connect(&sock).is_err() {
                    println!("✓ daemon stopped");
                    return Ok(());
                }
                std::thread::sleep(Duration::from_millis(100));
            }
            bail!("daemon did not exit within 3s")
        }
        other => bail!("unexpected response: {:?}", other),
    }
}

fn logs(follow: bool) -> Result<()> {
    let path = default_log_file();
    if !path.exists() {
        println!("(no log file yet at {})", path.display());
        return Ok(());
    }
    let mut cmd = Command::new("tail");
    if follow {
        cmd.arg("-F");
    }
    cmd.arg(path);
    let status = cmd.status()?;
    if !status.success() {
        bail!("tail exited with {}", status);
    }
    Ok(())
}

fn is_daemon_running() -> bool {
    UnixStream::connect(default_socket_path()).is_ok()
}

fn locate_daemon_binary() -> Result<PathBuf> {
    // 1. Same dir as the current 'voco' executable.
    let here = std::env::current_exe()?;
    let candidate = here.with_file_name("voco-daemon");
    if candidate.exists() {
        return Ok(candidate);
    }
    // 2. PATH lookup.
    if let Ok(path_var) = std::env::var("PATH") {
        for dir in std::env::split_paths(&path_var) {
            let p = dir.join("voco-daemon");
            if p.exists() {
                return Ok(p);
            }
        }
    }
    Err(anyhow!(
        "could not find voco-daemon binary; expected next to {} or on PATH",
        here.display()
    ))
}
```

- [ ] **Step 2: Compile**

Run: `cargo build --workspace`
Expected: success.

- [ ] **Step 3: Manual smoke test**

```sh
cargo build --workspace --release
./target/release/voco daemon start
./target/release/voco status                # ✓ daemon running, state idle
./target/release/voco daemon logs           # tails ~/Library/Logs/voco/voco.YYYY-MM-DD.log
./target/release/voco daemon stop
./target/release/voco status                # ✗ daemon not running
```

Caveat: because Phase 1 spawns the daemon as a child of the shell rather than via launchctl, killing the shell will also kill the daemon. That's intentional for dev — Phase 6 swaps in launchctl and the daemon survives logout/login.

- [ ] **Step 4: Commit**

```sh
git add crates/voco-cli
git commit -m "feat(cli): voco daemon start/stop/restart/logs (foreground)

- start: spawn voco-daemon child with stdout/stderr piped to
  ~/Library/Logs/voco/voco.log; wait up to 2s for socket
- stop: IPC DaemonShutdown then poll socket; bail after 3s
- restart: stop then start
- logs: shell out to tail -F
- Phase 6 replaces foreground spawn with launchctl LaunchAgent"
```

---

## Task 13: launchctl plist template (Phase 6 prep — files only)

We file the plist template alongside the source so Phase 6 has somewhere to start, but no installer code runs yet.

**Files:**
- Create: `packaging/com.voco.daemon.plist.tmpl`
- Create: `packaging/README.md`

- [ ] **Step 1: Create the plist template**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.voco.daemon</string>

  <key>ProgramArguments</key>
  <array>
    <string>{{VOCO_DAEMON_PATH}}</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>ProcessType</key>
  <string>Interactive</string>

  <key>StandardOutPath</key>
  <string>{{HOME}}/Library/Logs/voco/voco.out.log</string>

  <key>StandardErrorPath</key>
  <string>{{HOME}}/Library/Logs/voco/voco.err.log</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>RUST_LOG</key>
    <string>info,voco=debug</string>
  </dict>
</dict>
</plist>
```

- [ ] **Step 2: README for packaging**

```markdown
# packaging/

LaunchAgent template + bundle assets.

## com.voco.daemon.plist.tmpl

Templated LaunchAgent. Phase 6 will:
1. Substitute `{{VOCO_DAEMON_PATH}}` and `{{HOME}}`
2. Write to `~/Library/LaunchAgents/com.voco.daemon.plist`
3. `launchctl load -w ~/Library/LaunchAgents/com.voco.daemon.plist`

For now (Phase 1) the daemon is started with `voco daemon start`,
which spawns the process directly.
```

- [ ] **Step 3: Commit**

```sh
git add packaging/
git commit -m "docs(packaging): file LaunchAgent plist template for Phase 6

Not consumed yet. Phase 6 owns the installer that substitutes the
template and registers it with launchctl."
```

---

## Task 14: End-to-end smoke test

Real subprocess test — runs the cargo-built binaries and verifies the Phase 1 verification statement at the top of this plan.

**Files:**
- Create: `crates/voco-cli/tests/smoke.rs`
- Modify: `crates/voco-cli/Cargo.toml`

- [ ] **Step 1: Add `assert_cmd`, `predicates`, `serial_test` dev deps**

```toml
# crates/voco-cli/Cargo.toml — add
[dev-dependencies]
assert_cmd = "2"
predicates = "3"
serial_test = "3"
tempfile = { workspace = true }
```

- [ ] **Step 2: Write the smoke test**

```rust
// crates/voco-cli/tests/smoke.rs
//! End-to-end verification: voco daemon start && voco status returns idle.
//!
//! These tests touch the real ~/Library/Application Support/voco/voco.sock
//! because Phase 1 hasn't introduced a path-override env var yet (that lands
//! in Phase 2). serial_test prevents them from racing each other.

use assert_cmd::prelude::*;
use predicates::prelude::*;
use std::process::Command;
use std::time::Duration;

fn voco() -> Command {
    Command::cargo_bin("voco").unwrap()
}

#[test]
#[serial_test::serial]
fn daemon_start_status_stop_cycle() -> anyhow::Result<()> {
    // Make sure voco-daemon is built so the locate_daemon_binary lookup hits.
    let _ = Command::cargo_bin("voco-daemon")?;

    voco()
        .args(["daemon", "start"])
        .assert()
        .success()
        .stdout(predicate::str::contains("daemon started"));

    voco()
        .arg("status")
        .assert()
        .success()
        .stdout(predicate::str::contains("daemon running"))
        .stdout(predicate::str::contains("state:           idle"));

    voco()
        .args(["daemon", "stop"])
        .assert()
        .success()
        .stdout(predicate::str::contains("daemon stopped"));

    voco()
        .arg("status")
        .assert()
        .failure()
        .stdout(predicate::str::contains("daemon not running"));

    Ok(())
}

#[test]
#[serial_test::serial]
fn double_start_is_idempotent() -> anyhow::Result<()> {
    let _ = Command::cargo_bin("voco-daemon")?;

    voco().args(["daemon", "start"]).assert().success();

    voco()
        .args(["daemon", "start"])
        .assert()
        .success()
        .stdout(predicate::str::contains("already running"));

    voco().args(["daemon", "stop"]).assert().success();
    Ok(())
}

#[test]
#[serial_test::serial]
fn stop_without_start_is_idempotent() -> anyhow::Result<()> {
    let _ = voco().args(["daemon", "stop"]).output();
    std::thread::sleep(Duration::from_millis(200));

    voco()
        .args(["daemon", "stop"])
        .assert()
        .success()
        .stdout(predicate::str::contains("already stopped"));
    Ok(())
}
```

- [ ] **Step 3: Run the smoke tests**

Run: `cargo test -p voco-cli --test smoke -- --test-threads=1`
Expected: 3 passed.

- [ ] **Step 4: Run full workspace test + clippy**

```sh
cargo fmt --all
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```
Expected: all green.

- [ ] **Step 5: Commit**

```sh
git add crates/voco-cli/Cargo.toml crates/voco-cli/tests/smoke.rs
git commit -m "test(cli): end-to-end smoke test for daemon start/status/stop

- Real subprocesses via assert_cmd
- serial_test makes them safe to coexist with each other (but they still
  touch the real ~/Library paths — Phase 2 will introduce VOCO_HOME for
  isolation)
- Covers: cycle, double-start idempotent, double-stop idempotent"
```

---

## Phase 1 — Verification (must pass before Phase 2 starts)

- [ ] `cargo fmt --check` clean
- [ ] `cargo clippy --workspace --all-targets -- -D warnings` clean
- [ ] `cargo test --workspace` passes (target: ≥ 12 unit/integration tests across the 4 crates)
- [ ] `cargo build --release --workspace` produces `target/release/voco` and `target/release/voco-daemon`
- [ ] Manual: `./target/release/voco daemon start && ./target/release/voco status` prints `state: idle`
- [ ] Manual: `./target/release/voco daemon logs` shows the daemon's startup line
- [ ] Manual: `./target/release/voco daemon stop` cleanly stops; subsequent `status` reports daemon not running
- [ ] CI workflow runs green on a push

---

## What Phase 1 explicitly does NOT do (and why)

| Item | Phase that owns it |
|---|---|
| Audio capture (cpal) | Phase 3 |
| Doubao WebSocket backend | Phase 3 |
| Global hotkey (CGEventTap) | Phase 4 |
| Text injection (CGEvent) | Phase 4 |
| `voco config` interactive wizard | Phase 2 |
| `voco doctor` self-checks | Phase 2 |
| SwiftUI HUD + swift-bridge | Phase 5 |
| launchctl plist installer | Phase 6 |
| Voco.app bundle + Info.plist | Phase 6 |

Each "stub" returning `not yet implemented` is intentional — it makes the gap explicit and gives future phases a clear lock-on point.

---

## Open issues for Phase 2 carry-over

1. **`VOCO_HOME` env var.** Phase 1's `default_socket_path` reads directly from `directories`; Phase 2 should add an env override so integration tests get isolated tempdirs.
2. **`voco config` wizard input loop.** The wizard chooses between hardcoded options today; Phase 2 needs to handle "Custom..." for the hotkey by entering raw mode and capturing a real keypress.
3. **Doctor checks taxonomy.** Phase 2 will hit "is daemon socket reachable", "is config valid", "is microphone permission granted" — each needs its own pass/warn/fail variant to render uniformly.

---

## Total committed scope

14 tasks, ~14 commits. Estimated effort: 2-3 days of focused work for an engineer comfortable with Rust + tokio. About half the time goes to test plumbing (`assert_cmd` smoke tests, IPC e2e fixtures), which directly lowers the cost of every later phase.
