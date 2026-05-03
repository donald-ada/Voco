---
title: Voco Phase 6-A — LaunchAgent Lifecycle
date: 2026-05-03
status: design-approved
target_platform: macOS 14+ user LaunchAgent
scope: LaunchAgent-first packaging
---

# Voco Phase 6-A — LaunchAgent Lifecycle 设计文档

## 1. Goal

Phase 6-A upgrades daemon lifecycle management from development-only direct process spawning to a user-level macOS LaunchAgent.

The user should be able to install Voco once, then start, stop, restart, and inspect the daemon through `voco daemon ...` commands without keeping the terminal process alive. After installation, macOS owns the daemon process lifecycle through `launchctl`; if the daemon exits unexpectedly, `KeepAlive=true` brings it back.

This phase keeps the Phase 5 architecture intact: Rust daemon owns hotkey/audio/ASR/injection, and the daemon starts the separate Swift `voco-hud` helper. Phase 6-A does not merge Rust and Swift into a single `.app` process.

## 2. Scope

### In Scope

- Add `voco daemon install`.
- Add `voco daemon uninstall`.
- Render `packaging/com.voco.daemon.plist.tmpl` into `~/Library/LaunchAgents/com.voco.daemon.plist`.
- Replace template variables with concrete local paths.
- Manage installed daemon lifecycle with `launchctl`:
  - `bootstrap gui/<uid> <plist>`
  - `bootout gui/<uid>/com.voco.daemon`
  - `kickstart -k gui/<uid>/com.voco.daemon`
  - `print gui/<uid>/com.voco.daemon`
- Preserve a development fallback for uninstalled source-tree runs.
- Keep `voco status` IPC-based.
- Keep `voco daemon logs` reading the existing log directory.
- Add tests for plist rendering, command decision logic, and non-`launchctl` fallbacks.
- Add manual smoke documentation for installing, starting, stopping, and uninstalling.

### Out of Scope

- `Voco.app` bundle construction.
- Code signing, notarization, entitlements, or DMG/pkg distribution.
- System-level `/Library/LaunchAgents` installation.
- `sudo` install path.
- Auto-update.
- Keychain migration.
- Menu bar app.
- Replacing the Phase 5 separate Swift HUD helper.

## 3. User-Facing Behavior

### Commands

```text
voco daemon install
voco daemon uninstall
voco daemon start
voco daemon stop
voco daemon restart
voco daemon logs [-f] [--lines N]
```

### Install

`voco daemon install` resolves the current `voco-daemon` binary, renders a LaunchAgent plist, and writes it to `~/Library/LaunchAgents/com.voco.daemon.plist`.

Install does not start the daemon in the current session. `voco daemon start` owns `launchctl bootstrap` and `launchctl kickstart`. This keeps `install` side effects narrow and makes the command sequence explicit.

Expected successful output:

```text
✓ installed LaunchAgent: ~/Library/LaunchAgents/com.voco.daemon.plist
  start it with: voco daemon start
```

If the LaunchAgent is already installed with identical content, install is idempotent and reports that no file change was needed. If the existing file differs, the command rewrites it. If the service is currently loaded, the next `voco daemon restart` reloads the updated plist.

### Uninstall

`voco daemon uninstall` stops the LaunchAgent if loaded, removes `~/Library/LaunchAgents/com.voco.daemon.plist`, and leaves user config/logs intact.

Expected successful output:

```text
✓ daemon stopped
✓ removed LaunchAgent: ~/Library/LaunchAgents/com.voco.daemon.plist
```

### Start

If the LaunchAgent is installed, `voco daemon start` uses `launchctl bootstrap` if needed and `launchctl kickstart -k` to start or restart the job in the current user GUI domain. It then waits for the IPC socket so `voco status` works immediately.

If the LaunchAgent is not installed, `start` keeps the existing development fallback: locate `voco-daemon`, spawn it directly, pipe stdout/stderr to logs, and wait for the socket.

This preserves the current source-tree workflow:

```bash
cargo build --workspace
target/debug/voco daemon start
target/debug/voco status
```

### Stop

If the LaunchAgent is installed, `voco daemon stop` uses `launchctl bootout gui/<uid>/com.voco.daemon`.

If the LaunchAgent is not installed, `stop` keeps the existing IPC shutdown fallback.

### Restart

If installed, restart runs `bootout` followed by `bootstrap` and `kickstart -k`, then waits for the socket.

If not installed, restart keeps the existing development fallback: IPC stop, short delay, direct spawn start.

### Logs

`voco daemon logs` remains unchanged. It reads the latest log under `~/Library/Logs/voco` using the existing resolver.

## 4. LaunchAgent Design

### Domain

Phase 6-A uses the current user's GUI launchd domain:

```text
gui/<uid>
```

The service label is:

```text
com.voco.daemon
```

This avoids `sudo`, keeps permissions simple, and matches Voco's per-user config, socket, and logs.

### Plist Path

```text
~/Library/LaunchAgents/com.voco.daemon.plist
```

The command creates `~/Library/LaunchAgents` when missing.

### Template Variables

The existing `packaging/com.voco.daemon.plist.tmpl` remains the canonical template.

Variables:

```text
{{VOCO_DAEMON_PATH}} absolute path to voco-daemon
{{HOME}}             user home directory
{{WORKING_DIR}}      directory used by the daemon process
```

`{{WORKING_DIR}}` is important for source-tree installs because the Phase 5 daemon can resolve `hud/.build/debug/voco-hud` relative to the repository root during development.

### Working Directory Resolution

The install command chooses `WorkingDirectory` as follows:

1. If the current directory contains `Cargo.toml`, `hud/Package.swift`, and `packaging/com.voco.daemon.plist.tmpl`, use the current repository root.
2. Otherwise, use the parent directory of the resolved `voco-daemon` binary.

This supports both development installs and future copied binary installs.

### KeepAlive

The LaunchAgent keeps:

```xml
<key>KeepAlive</key>
<true/>
```

Crash recovery is a primary Phase 6-A deliverable. An intentional `voco daemon stop` uses `bootout`, which unloads the job and prevents immediate relaunch.

## 5. Internal Modules

### CLI Parser

`DaemonAction` gains two variants:

```rust
Install
Uninstall
```

The command surface remains under `voco daemon`.

### LaunchAgent Module

Create a focused module under the CLI crate:

```text
crates/voco-cli/src/commands/daemon/launch_agent.rs
```

Responsibilities:

- Resolve LaunchAgent paths.
- Render plist content.
- Compare rendered content with existing installed content.
- Write plist atomically.
- Run `launchctl`.
- Classify common `launchctl` outcomes.
- Provide unit-testable functions that do not call `launchctl`.

Core public surface inside the CLI crate:

```rust
pub struct LaunchAgentPaths {
    pub plist_path: PathBuf,
    pub daemon_path: PathBuf,
    pub working_dir: PathBuf,
    pub home: PathBuf,
}

pub struct LaunchAgent {
    pub label: &'static str,
    pub paths: LaunchAgentPaths,
}

impl LaunchAgent {
    pub fn discover() -> Result<Self>;
    pub fn is_installed(&self) -> bool;
    pub fn install(&self) -> Result<InstallOutcome>;
    pub fn uninstall(&self) -> Result<()>;
    pub fn start(&self) -> Result<()>;
    pub fn stop(&self) -> Result<()>;
    pub fn restart(&self) -> Result<()>;
}

pub enum InstallOutcome {
    Created,
    Updated,
    Unchanged,
}
```

Implementation can keep this module private to `commands::daemon`. No workspace crate is needed for Phase 6-A.

## 6. Launchctl Error Handling

Every `launchctl` invocation captures stdout, stderr, and exit status.

Rules:

- `bootout` with “service not found”, “No such process”, or exit code commonly emitted for an unloaded job is treated as already stopped.
- `bootstrap` with “service already loaded” is not treated as fatal; the command proceeds to `kickstart -k`.
- Any other non-zero exit returns an actionable error including:
  - command name;
  - domain or service target;
  - exit code;
  - stderr.

Example error:

```text
launchctl bootstrap gui/501 /Users/me/Library/LaunchAgents/com.voco.daemon.plist failed with exit 5: Input/output error
```

No `launchctl` failure is silently ignored.

## 7. Testing Strategy

### Unit Tests

Unit tests do not call real `launchctl`.

Required coverage:

- Plist rendering replaces all variables.
- Plist rendering XML-escapes paths containing `&`, `<`, `>`, `"`, and `'`.
- `WorkingDirectory` chooses repo root when source-tree markers exist.
- `WorkingDirectory` falls back to daemon binary parent outside the repo.
- Install outcome is `Unchanged` when existing plist content matches.
- Install outcome is `Updated` when existing plist content differs.
- `bootout` “service not found” classification maps to already stopped.
- Non-zero unknown `launchctl` output maps to a descriptive error.

### Integration Tests

Existing daemon smoke tests continue to use the direct-spawn fallback unless they explicitly create a temporary installed plist. CI should not mutate the real user LaunchAgents directory.

No test in CI writes to:

```text
~/Library/LaunchAgents
```

### Manual Smoke

Manual verification on a development Mac:

```bash
cargo build --workspace
target/debug/voco daemon install
target/debug/voco daemon start
target/debug/voco status
launchctl print gui/$(id -u)/com.voco.daemon
pkill -9 voco-daemon
sleep 1
target/debug/voco status
target/debug/voco daemon stop
target/debug/voco daemon uninstall
test ! -f ~/Library/LaunchAgents/com.voco.daemon.plist
```

Expected:

- install writes the plist;
- start makes the IPC socket reachable;
- `launchctl print` shows the service;
- killing `voco-daemon` is followed by relaunch because `KeepAlive=true`;
- stop unloads the job;
- uninstall removes the plist;
- config and logs remain.

## 8. Documentation Updates

Update `README.md` with:

- development start path;
- installed LaunchAgent path;
- install/start/status/stop/uninstall quickstart;
- note that no `sudo` is required;
- note that app bundle/signing are still future work.

Update `packaging/README.md` to describe the Phase 6-A installed behavior instead of saying the template is only future prep.

## 9. Open Decisions Resolved

- Install path: user-level `~/Library/LaunchAgents/com.voco.daemon.plist`.
- No `sudo`.
- `voco status` remains IPC-based.
- Direct spawn remains as development fallback.
- App bundle is deferred to a later Phase 6-B or v0.1 packaging pass.
