---
title: Voco Phase 7 — Per-User App Install
date: 2026-05-04
status: design-approved
target_platform: macOS 14+ per-user app install
scope: Install generated Voco.app under ~/Applications and point LaunchAgent at it
---

# Voco Phase 7 — Per-User App Install 设计文档

## 1. Goal

Phase 7 adds a local per-user install path for the generated `Voco.app` bundle.

Phase 6-A made the user LaunchAgent lifecycle real. Phase 6-B made `target/Voco.app` reproducible. Phase 6-C allowed the LaunchAgent to run `voco-daemon` from an explicit bundle path. Phase 7 turns that development bundle into a user-installed app bundle:

```bash
packaging/build_app_bundle.sh --profile release
target/release/voco app install --app-bundle target/Voco.app
target/release/voco daemon start
target/release/voco status
```

The installed bundle lives at:

```text
~/Applications/Voco.app
```

The user LaunchAgent is installed or updated so `ProgramArguments:0` points at:

```text
~/Applications/Voco.app/Contents/MacOS/voco-daemon
```

This phase is a local install workflow, not a signed distribution workflow.

## 2. Scope

### In Scope

- Add a new top-level CLI namespace:

```bash
voco app install --app-bundle <PATH>
```

- Install the provided app bundle to `~/Applications/Voco.app`.
- Create `~/Applications` if it does not exist.
- Validate the source bundle before copying.
- Copy via a temporary bundle path and rename into place.
- Preserve a previous installed bundle until the new bundle has been copied and validated.
- Validate the installed bundle before LaunchAgent registration.
- Install or update `~/Library/LaunchAgents/com.voco.daemon.plist` so it points at the installed bundle.
- Keep `voco daemon install --app-bundle <PATH>` as the lower-level development path.
- Update README and packaging docs with the per-user install workflow.
- Add automated tests for CLI parsing, path resolution, bundle copying, failure modes, and missing bundle smoke behavior.
- Add manual verification for installed plist paths and start/status/stop/uninstall lifecycle.

### Out of Scope

- Installing to `/Applications`.
- Requiring `sudo`.
- Code signing.
- Notarization.
- DMG or pkg creation.
- Auto-updates.
- Menu bar UI.
- Settings UI.
- Keychain credential migration.
- Changing the LaunchAgent label.
- Changing config, logs, socket, or credential paths.
- Removing user config or logs.
- Implementing `voco app uninstall`.

## 3. User-Facing Behavior

### Install Flow

The intended Phase 7 flow is:

```bash
packaging/build_app_bundle.sh --profile release
target/release/voco app install --app-bundle target/Voco.app
target/release/voco daemon start
target/release/voco status
```

Successful `app install` output should be explicit about both the installed bundle and LaunchAgent paths:

```text
✓ installed app bundle: /Users/me/Applications/Voco.app
✓ installed LaunchAgent: /Users/me/Library/LaunchAgents/com.voco.daemon.plist
  daemon: /Users/me/Applications/Voco.app/Contents/MacOS/voco-daemon
  working directory: /Users/me/Applications/Voco.app/Contents/MacOS
  start it with: voco daemon start
```

If the LaunchAgent plist already exists with identical content, the LaunchAgent line can use the existing Phase 6 wording:

```text
✓ LaunchAgent already installed: /Users/me/Library/LaunchAgents/com.voco.daemon.plist
```

The daemon and working directory lines must still be printed so the user can verify what is installed.

### Existing Behavior Remains

This still works and keeps the source-tree or explicit development bundle behavior:

```bash
target/debug/voco daemon install
target/debug/voco daemon install --app-bundle target/Voco.app
```

`voco daemon start`, `stop`, `restart`, `logs`, and `status` keep their Phase 6 behavior.

### Uninstall and Cleanup

Phase 7 does not add `voco app uninstall`.

To stop and unregister the LaunchAgent:

```bash
voco daemon stop
voco daemon uninstall
```

To remove the installed app bundle, the user can remove:

```text
~/Applications/Voco.app
```

Config and logs remain in place.

## 4. CLI Shape

Add a top-level `App` command:

```rust
Cmd::App {
    action: AppAction,
}
```

Add an app action enum:

```rust
pub enum AppAction {
    Install {
        #[arg(long, value_name = "PATH")]
        app_bundle: PathBuf,
    },
}
```

`--app-bundle` is required for Phase 7. The command must not auto-detect `target/Voco.app` when omitted. That keeps user intent explicit and prevents accidentally installing a stale development bundle.

## 5. Architecture and Module Boundaries

### New CLI Module

Create:

```text
crates/voco-cli/src/commands/app.rs
```

Responsibilities:

- Parse `AppAction`.
- Resolve `HOME`.
- Resolve the default install destination:

```text
$HOME/Applications/Voco.app
```

- Validate the source bundle using the existing app bundle resolver.
- Copy the bundle to the per-user install location.
- Validate the installed bundle.
- Install the LaunchAgent from the installed bundle.
- Print clear user-facing output.

### LaunchAgent Resolver Reuse

Phase 6-C currently keeps bundle validation and LaunchAgent rendering under `commands::daemon::launch_agent`.

Phase 7 should reuse that code rather than duplicating plist validation or path rendering. Move `launch_agent.rs` from:

```text
crates/voco-cli/src/commands/daemon/launch_agent.rs
```

to:

```text
crates/voco-cli/src/commands/launch_agent.rs
```

Then expose it from `commands/mod.rs` as:

```rust
pub(crate) mod launch_agent;
```

`commands::daemon` and `commands::app` should both import this shared module. This makes app bundle validation, plist rendering, and LaunchAgent lifecycle behavior single-source within `voco-cli`.

### Shared LaunchAgent Install Helper

The daemon installer currently owns private helper behavior for:

- discovering a `LaunchAgent`;
- calling `agent.install()`;
- printing install outcome;
- printing daemon and working directory.

Phase 7 should avoid duplicating that user-facing install sequence. Add a small crate-private helper in `commands::launch_agent`:

```rust
pub(crate) fn install_and_print(agent: &LaunchAgent) -> Result<()>
```

The helper should call `agent.install()`, print the install outcome, and print the daemon and working directory lines. `daemon install` and `app install` should both use this helper for plist writes and user-facing output. `app install` is responsible for copying and validating the bundle first; after that it builds a `LaunchAgent` from the installed bundle and delegates plist installation to the shared helper.

## 6. Bundle Copy Strategy

The installer should not directly remove the old app and then copy the new one. That risks leaving the user with no installed bundle if copying fails.

Use a temp-and-rename strategy under `~/Applications`:

```text
~/Applications/Voco.app
~/Applications/.Voco.app.tmp-<pid>
~/Applications/.Voco.app.backup-<pid>
```

Algorithm:

1. Validate the source bundle with `AppBundle::discover`.
2. Create `~/Applications` if needed.
3. Fail if `~/Applications` exists and is not a directory.
4. Remove any stale temp path for this process.
5. Copy the source bundle directory into the temp path.
6. Validate the temp bundle with `AppBundle::discover`.
7. If `~/Applications/Voco.app` exists:
   - fail if it is not a directory;
   - rename it to the backup path.
8. Rename the temp bundle to `~/Applications/Voco.app`.
9. Validate the final installed bundle.
10. Remove the backup path.
11. Install or update the LaunchAgent from the final installed bundle.

If the final rename fails after the backup rename succeeds, the installer should attempt to restore the backup to `~/Applications/Voco.app` and return a descriptive error if restoration also fails.

If LaunchAgent installation fails after the bundle is installed, do not roll back the app bundle. The app copy succeeded and the LaunchAgent failure is a separate operational error. The error message must state that the bundle was installed but LaunchAgent registration failed.

## 7. File Copy Rules

The source `Voco.app` is a directory tree. Use a small Rust recursive copy helper based on `std::fs`, not `/bin/cp -R`. This keeps the copy path testable and avoids shell quoting issues. Preserve executable bits by copying file permissions after file contents.

Minimum required preservation:

- `Contents/Info.plist` remains a file.
- `Contents/MacOS/voco` remains executable.
- `Contents/MacOS/voco-daemon` remains executable.
- `Contents/MacOS/voco-hud` remains executable.

Symlink handling is not a Phase 7 requirement because the generated development bundle contains regular files. If a symlink is encountered, fail loud with the path instead of silently dereferencing or skipping it.

## 8. Error Handling

All filesystem and LaunchAgent errors must include the path being operated on.

Expected failures:

```text
app bundle not found: target/Missing.app
missing app bundle Info.plist: target/Voco.app/Contents/Info.plist
missing executable in app bundle: target/Voco.app/Contents/MacOS/voco-daemon
HOME is not set; cannot resolve app install path
Applications path is not a directory: /Users/me/Applications
installed app path exists but is not a directory: /Users/me/Applications/Voco.app
copy app bundle from <source> to <tmp> failed: <io error>
replace installed app bundle at <destination> failed: <io error>
installed app bundle at <destination> but LaunchAgent install failed: <error>
```

No network or external service is involved in Phase 7.

## 9. Testing Strategy

### Parser Tests

Extend CLI parser tests to cover:

```bash
voco app install --app-bundle target/Voco.app
```

Expected parsed shape:

```rust
Cmd::App {
    action: AppAction::Install {
        app_bundle: PathBuf::from("target/Voco.app"),
    },
}
```

### Unit Tests

Add unit tests for app install path helpers:

- `$HOME=/tmp/home` resolves to `/tmp/home/Applications/Voco.app`.
- Missing `HOME` fails with a descriptive error.
- Existing `~/Applications` as a regular file fails.
- Existing destination as a regular file fails and is not removed.
- Copying a valid fake bundle preserves `Contents/MacOS/voco-daemon` executable permission.
- Replacing an existing valid bundle leaves the new daemon path executable.

### Smoke Tests

Add a CLI smoke test:

```rust
#[test]
#[serial_test::serial]
fn app_install_with_missing_bundle_fails_loudly()
```

Expected stderr contains:

```text
app bundle not found
```

This test should use temp `HOME` and `VOCO_HOME` and must not write to the real `~/Applications`.

### Focused Manual Verification

Manual Phase 7 smoke on a development Mac:

```bash
packaging/tests/app_bundle_smoke.sh
target/debug/voco daemon uninstall || true
target/debug/voco app install --app-bundle target/Voco.app
test -x ~/Applications/Voco.app/Contents/MacOS/voco-daemon
plutil -lint ~/Library/LaunchAgents/com.voco.daemon.plist
/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" ~/Library/LaunchAgents/com.voco.daemon.plist
/usr/libexec/PlistBuddy -c "Print :WorkingDirectory" ~/Library/LaunchAgents/com.voco.daemon.plist
target/debug/voco daemon start
target/debug/voco status
target/debug/voco daemon stop
target/debug/voco daemon uninstall
test ! -f ~/Library/LaunchAgents/com.voco.daemon.plist
```

Expected:

- `~/Applications/Voco.app/Contents/MacOS/voco-daemon` exists and is executable.
- The plist is valid.
- `ProgramArguments:0` points at `~/Applications/Voco.app/Contents/MacOS/voco-daemon`.
- `WorkingDirectory` points at `~/Applications/Voco.app/Contents/MacOS`.
- daemon starts via launchctl.
- status reports daemon running and state idle.
- stop succeeds.
- uninstall removes the plist.
- The installed app bundle remains in `~/Applications/Voco.app`.

## 10. Documentation

Update `README.md` with the per-user local install flow:

```bash
packaging/build_app_bundle.sh --profile release
target/release/voco app install --app-bundle target/Voco.app
target/release/voco daemon start
target/release/voco status
```

Document that:

- `app install` copies the bundle to `~/Applications/Voco.app`.
- `app install` installs or updates the user LaunchAgent to point at the installed bundle.
- no `sudo` is required.
- the phase does not sign, notarize, create a DMG/pkg, or install under `/Applications`.

Update `packaging/README.md` with:

- development bundle build command;
- local app install command;
- installed LaunchAgent plist paths;
- note that `daemon install --app-bundle target/Voco.app` remains available for development installs that point directly at `target/Voco.app`.

## 11. Verification Gates

Automated gates:

```bash
packaging/tests/app_bundle_smoke.sh
cargo fmt --all --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
git diff --check
```

Manual gates:

```bash
target/debug/voco daemon uninstall || true
target/debug/voco app install --app-bundle target/Voco.app
test -x ~/Applications/Voco.app/Contents/MacOS/voco-daemon
plutil -lint ~/Library/LaunchAgents/com.voco.daemon.plist
/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" ~/Library/LaunchAgents/com.voco.daemon.plist
/usr/libexec/PlistBuddy -c "Print :WorkingDirectory" ~/Library/LaunchAgents/com.voco.daemon.plist
target/debug/voco daemon start
target/debug/voco status
target/debug/voco daemon stop
target/debug/voco daemon uninstall
```

The implementation plan must record the observed command outcomes in the Phase 7 plan before final commit.

## 12. Non-Goals and Future Work

Future phases can add:

- `/Applications` install mode.
- code signing.
- notarization.
- DMG or pkg packaging.
- app uninstall command.
- menu bar or settings UI.
- automatic update flow.

Those should not be smuggled into Phase 7. The success criterion for this phase is a reliable per-user install of an already generated bundle plus a LaunchAgent that points at that installed bundle.
