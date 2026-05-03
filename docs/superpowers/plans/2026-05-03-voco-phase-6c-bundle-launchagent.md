# Voco Phase 6-C Bundle LaunchAgent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit `voco daemon install --app-bundle <PATH>` support so the user LaunchAgent can run `voco-daemon` from `Voco.app/Contents/MacOS`.

**Architecture:** Keep Phase 6-A direct binary install as the default path. Add a focused app-bundle resolver in the existing private LaunchAgent module, then thread `Option<PathBuf>` from clap into install discovery. Bundle validation happens before plist writes, and no fallback is allowed when `--app-bundle` was explicitly supplied.

**Tech Stack:** Rust 2021, clap derive, macOS `/usr/libexec/PlistBuddy`, LaunchAgent plist rendering, existing shell bundle smoke.

---

## File Structure

- Modify: `crates/voco-cli/src/main.rs` — change `DaemonAction::Install` to accept `--app-bundle <PATH>` and update parser tests.
- Modify: `crates/voco-cli/src/commands/daemon.rs` — pass optional app bundle into install discovery and print installed daemon/working directory.
- Modify: `crates/voco-cli/src/commands/daemon/launch_agent.rs` — add `AppBundle`, bundle validation, `LaunchAgent::from_parts`, and bundle plist rendering tests.
- Modify: `README.md` — document bundle-aware LaunchAgent install flow.
- Modify: `packaging/README.md` — document bundle build + bundle install sequence.
- Modify: `docs/superpowers/plans/2026-05-03-voco-phase-6c-bundle-launchagent.md` — record final verification.

## Task 1: CLI Parser Red Test

**Files:**
- Modify: `crates/voco-cli/src/main.rs`

- [ ] **Step 1: Add parser test for `--app-bundle`**

In `crates/voco-cli/src/main.rs`, replace the existing `parses_daemon_install_uninstall_actions` test with:

```rust
#[test]
fn parses_daemon_install_uninstall_actions() {
    let install = Cli::try_parse_from(["voco", "daemon", "install"]).unwrap();
    assert!(matches!(
        install.command,
        Cmd::Daemon {
            action: DaemonAction::Install { app_bundle: None }
        }
    ));

    let install_bundle =
        Cli::try_parse_from(["voco", "daemon", "install", "--app-bundle", "target/Voco.app"])
            .unwrap();
    match install_bundle.command {
        Cmd::Daemon {
            action:
                DaemonAction::Install {
                    app_bundle: Some(path),
                },
        } => assert_eq!(path, std::path::PathBuf::from("target/Voco.app")),
        _ => panic!("unexpected command"),
    }

    let uninstall = Cli::try_parse_from(["voco", "daemon", "uninstall"]).unwrap();
    assert!(matches!(
        uninstall.command,
        Cmd::Daemon {
            action: DaemonAction::Uninstall
        }
    ));
}
```

- [ ] **Step 2: Run parser test and confirm failure**

Run:

```bash
cargo test -p voco-cli parses_daemon_install_uninstall_actions
```

Expected: FAIL because `DaemonAction::Install` is still a unit variant and has no `app_bundle` field.

- [ ] **Step 3: Commit the red parser test**

```bash
git add crates/voco-cli/src/main.rs
git commit -m "test(cli): cover bundle install parser"
```

## Task 2: CLI Parser Implementation

**Files:**
- Modify: `crates/voco-cli/src/main.rs`
- Modify: `crates/voco-cli/src/commands/daemon.rs`

- [ ] **Step 1: Add `PathBuf` import and struct-like install action**

In `crates/voco-cli/src/main.rs`, add:

```rust
use std::path::PathBuf;
```

Change `DaemonAction::Install` to:

```rust
/// Install the user LaunchAgent plist without starting the daemon.
Install {
    /// Install a LaunchAgent that runs voco-daemon from this Voco.app bundle.
    #[arg(long, value_name = "PATH")]
    app_bundle: Option<PathBuf>,
},
```

- [ ] **Step 2: Update daemon command dispatch**

In `crates/voco-cli/src/commands/daemon.rs`, change:

```rust
DaemonAction::Install => install(),
```

to:

```rust
DaemonAction::Install { app_bundle } => install(app_bundle),
```

Change the install function signature:

```rust
fn install(app_bundle: Option<PathBuf>) -> Result<()> {
    let agent = discover_launch_agent(app_bundle.as_deref())?;
```

Change `discover_launch_agent` to accept the optional path, while still calling the existing direct path for now:

```rust
fn discover_launch_agent(app_bundle: Option<&std::path::Path>) -> Result<launch_agent::LaunchAgent> {
    if app_bundle.is_some() {
        bail!("--app-bundle is parsed but bundle discovery is not wired yet");
    }
    let daemon_path = locate_daemon_binary()?;
    launch_agent::LaunchAgent::discover(daemon_path)
}
```

Update call sites:

```rust
let agent = discover_launch_agent(None)?;
```

for `uninstall`, `start`, `stop`, and `restart`.

- [ ] **Step 3: Run parser test and confirm pass**

Run:

```bash
cargo test -p voco-cli parses_daemon_install_uninstall_actions
```

Expected: PASS.

- [ ] **Step 4: Verify direct install parser behavior remains covered**

Run:

```bash
cargo test -p voco-cli tests::parses_daemon_install_uninstall_actions
```

Expected: PASS.

- [ ] **Step 5: Commit parser implementation**

```bash
git add crates/voco-cli/src/main.rs crates/voco-cli/src/commands/daemon.rs
git commit -m "feat(cli): parse bundle install option"
```

## Task 3: App Bundle Resolver Red Tests

**Files:**
- Modify: `crates/voco-cli/src/commands/daemon/launch_agent.rs`

- [ ] **Step 1: Add failing resolver tests**

Inside the existing `#[cfg(test)] mod tests` in `crates/voco-cli/src/commands/daemon/launch_agent.rs`, add:

```rust
fn write_bundle_plist(path: &Path, identifier: &str, executable: &str) -> anyhow::Result<()> {
    let contents = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>{identifier}</string>
  <key>CFBundleExecutable</key>
  <string>{executable}</string>
</dict>
</plist>
"#
    );
    std::fs::write(path, contents)?;
    Ok(())
}

#[cfg(unix)]
fn make_executable(path: &Path) -> anyhow::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let mut permissions = std::fs::metadata(path)?.permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(path, permissions)?;
    Ok(())
}

fn create_test_bundle(
    tmp: &tempfile::TempDir,
    identifier: &str,
    executable: &str,
) -> anyhow::Result<PathBuf> {
    let bundle = tmp.path().join("target/Voco.app");
    let macos = bundle.join("Contents/MacOS");
    std::fs::create_dir_all(&macos)?;
    write_bundle_plist(&bundle.join("Contents/Info.plist"), identifier, executable)?;
    let daemon = macos.join("voco-daemon");
    std::fs::write(&daemon, b"#!/bin/sh\n")?;
    make_executable(&daemon)?;
    Ok(bundle)
}

#[test]
fn app_bundle_resolution_derives_expected_paths() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    let bundle = create_test_bundle(&tmp, "com.voco.app", "voco-daemon")?;

    let app = AppBundle::discover(&bundle)?;

    assert_eq!(app.bundle_path, bundle.canonicalize()?);
    assert_eq!(app.info_plist_path, app.bundle_path.join("Contents/Info.plist"));
    assert_eq!(app.working_dir, app.bundle_path.join("Contents/MacOS"));
    assert_eq!(app.daemon_path, app.working_dir.join("voco-daemon"));
    Ok(())
}

#[test]
fn app_bundle_missing_directory_fails() {
    let tmp = tempfile::tempdir().unwrap();
    let err = AppBundle::discover(tmp.path().join("missing.app")).unwrap_err();
    assert!(err.to_string().contains("app bundle not found"));
}

#[test]
fn app_bundle_missing_info_plist_fails() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    let bundle = tmp.path().join("target/Voco.app");
    std::fs::create_dir_all(bundle.join("Contents/MacOS"))?;

    let err = AppBundle::discover(&bundle).unwrap_err();

    assert!(err.to_string().contains("missing app bundle Info.plist"));
    Ok(())
}

#[test]
fn app_bundle_missing_daemon_fails() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    let bundle = tmp.path().join("target/Voco.app");
    std::fs::create_dir_all(bundle.join("Contents/MacOS"))?;
    write_bundle_plist(
        &bundle.join("Contents/Info.plist"),
        "com.voco.app",
        "voco-daemon",
    )?;

    let err = AppBundle::discover(&bundle).unwrap_err();

    assert!(err.to_string().contains("missing executable in app bundle"));
    Ok(())
}

#[test]
fn app_bundle_non_executable_daemon_fails() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    let bundle = tmp.path().join("target/Voco.app");
    let macos = bundle.join("Contents/MacOS");
    std::fs::create_dir_all(&macos)?;
    write_bundle_plist(
        &bundle.join("Contents/Info.plist"),
        "com.voco.app",
        "voco-daemon",
    )?;
    std::fs::write(macos.join("voco-daemon"), b"#!/bin/sh\n")?;

    let err = AppBundle::discover(&bundle).unwrap_err();

    assert!(err.to_string().contains("missing executable in app bundle"));
    Ok(())
}

#[test]
fn app_bundle_wrong_identifier_fails() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    let bundle = create_test_bundle(&tmp, "com.example.Other", "voco-daemon")?;

    let err = AppBundle::discover(&bundle).unwrap_err();

    assert!(err.to_string().contains("unexpected CFBundleIdentifier"));
    assert!(err.to_string().contains("com.example.Other"));
    Ok(())
}

#[test]
fn app_bundle_wrong_executable_fails() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    let bundle = create_test_bundle(&tmp, "com.voco.app", "OtherDaemon")?;

    let err = AppBundle::discover(&bundle).unwrap_err();

    assert!(err.to_string().contains("unexpected CFBundleExecutable"));
    assert!(err.to_string().contains("OtherDaemon"));
    Ok(())
}
```

- [ ] **Step 2: Run resolver tests and confirm failure**

Run:

```bash
cargo test -p voco-cli app_bundle_
```

Expected: FAIL because `AppBundle` does not exist yet.

- [ ] **Step 3: Commit red resolver tests**

```bash
git add crates/voco-cli/src/commands/daemon/launch_agent.rs
git commit -m "test(cli): cover app bundle LaunchAgent resolution"
```

## Task 4: App Bundle Resolver Implementation

**Files:**
- Modify: `crates/voco-cli/src/commands/daemon/launch_agent.rs`

- [ ] **Step 1: Add bundle constants and `AppBundle` type**

Near the top of `crates/voco-cli/src/commands/daemon/launch_agent.rs`, after `pub const LABEL`, add:

```rust
const EXPECTED_BUNDLE_ID: &str = "com.voco.app";
const EXPECTED_BUNDLE_EXECUTABLE: &str = "voco-daemon";
```

After `LaunchAgent` struct, add:

```rust
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AppBundle {
    pub bundle_path: PathBuf,
    pub info_plist_path: PathBuf,
    pub daemon_path: PathBuf,
    pub working_dir: PathBuf,
}
```

- [ ] **Step 2: Add `AppBundle::discover`**

In the same file, before `impl LaunchAgent`, add:

```rust
impl AppBundle {
    pub fn discover(path: impl AsRef<Path>) -> Result<Self> {
        let supplied = path.as_ref();
        if !supplied.is_dir() {
            return Err(anyhow::anyhow!(
                "app bundle not found: {}",
                supplied.display()
            ));
        }

        let bundle_path = supplied.canonicalize()?;
        let info_plist_path = bundle_path.join("Contents/Info.plist");
        if !info_plist_path.is_file() {
            return Err(anyhow::anyhow!(
                "missing app bundle Info.plist: {}",
                info_plist_path.display()
            ));
        }

        let working_dir = bundle_path.join("Contents/MacOS");
        let daemon_path = working_dir.join(EXPECTED_BUNDLE_EXECUTABLE);
        if !is_executable_file(&daemon_path) {
            return Err(anyhow::anyhow!(
                "missing executable in app bundle: {}",
                daemon_path.display()
            ));
        }

        let bundle_id = read_plist_key(&info_plist_path, "CFBundleIdentifier")?;
        if bundle_id != EXPECTED_BUNDLE_ID {
            return Err(anyhow::anyhow!(
                "unexpected CFBundleIdentifier in {}: {}",
                info_plist_path.display(),
                bundle_id
            ));
        }

        let executable = read_plist_key(&info_plist_path, "CFBundleExecutable")?;
        if executable != EXPECTED_BUNDLE_EXECUTABLE {
            return Err(anyhow::anyhow!(
                "unexpected CFBundleExecutable in {}: {}",
                info_plist_path.display(),
                executable
            ));
        }

        Ok(Self {
            bundle_path,
            info_plist_path,
            daemon_path,
            working_dir,
        })
    }
}
```

- [ ] **Step 3: Add plist probe and executable helpers**

Before `run_launchctl`, add:

```rust
fn read_plist_key(plist_path: &Path, key: &str) -> Result<String> {
    let output = std::process::Command::new("/usr/libexec/PlistBuddy")
        .arg("-c")
        .arg(format!("Print :{key}"))
        .arg(plist_path)
        .output()?;

    if !output.status.success() {
        return Err(anyhow::anyhow!(
            "read {key} from {} failed: {}",
            plist_path.display(),
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    Ok(String::from_utf8(output.stdout)?.trim().to_string())
}

fn is_executable_file(path: &Path) -> bool {
    if !path.is_file() {
        return false;
    }
    is_executable_file_platform(path)
}

#[cfg(unix)]
fn is_executable_file_platform(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path)
        .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable_file_platform(path: &Path) -> bool {
    path.is_file()
}
```

- [ ] **Step 4: Run resolver tests and confirm pass**

Run:

```bash
cargo test -p voco-cli app_bundle_
```

Expected: PASS.

- [ ] **Step 5: Run LaunchAgent unit tests**

Run:

```bash
cargo test -p voco-cli commands::daemon::launch_agent::tests
```

Expected: PASS.

- [ ] **Step 6: Commit resolver implementation**

```bash
git add crates/voco-cli/src/commands/daemon/launch_agent.rs
git commit -m "feat(cli): resolve Voco app bundle install paths"
```

## Task 5: Bundle LaunchAgent Rendering

**Files:**
- Modify: `crates/voco-cli/src/commands/daemon/launch_agent.rs`

- [ ] **Step 1: Add failing render tests**

Inside `#[cfg(test)] mod tests`, add:

```rust
#[test]
fn launch_agent_from_bundle_paths_renders_daemon_inside_app() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    let bundle = create_test_bundle(&tmp, "com.voco.app", "voco-daemon")?;
    let app = AppBundle::discover(&bundle)?;
    let home = tmp.path().join("home");

    let agent = LaunchAgent::from_parts(home.clone(), app.daemon_path.clone(), app.working_dir.clone());
    let rendered = render_plist(&agent.paths);

    assert_eq!(
        agent.paths.plist_path,
        home.join("Library/LaunchAgents/com.voco.daemon.plist")
    );
    assert!(rendered.contains(&format!(
        "<string>{}</string>",
        app.daemon_path.display()
    )));
    assert!(rendered.contains(&format!(
        "<string>{}</string>",
        app.working_dir.display()
    )));
    Ok(())
}
```

- [ ] **Step 2: Run render test and confirm failure**

Run:

```bash
cargo test -p voco-cli launch_agent_from_bundle_paths_renders_daemon_inside_app
```

Expected: FAIL because `LaunchAgent::from_parts` does not exist.

- [ ] **Step 3: Implement `LaunchAgent::from_parts`**

Inside `impl LaunchAgent`, add:

```rust
pub fn from_parts(home: PathBuf, daemon_path: PathBuf, working_dir: PathBuf) -> Self {
    let plist_path = home.join("Library/LaunchAgents/com.voco.daemon.plist");
    Self {
        label: LABEL,
        paths: LaunchAgentPaths {
            plist_path,
            daemon_path,
            working_dir,
            home,
        },
    }
}
```

Then simplify `LaunchAgent::discover` to reuse it:

```rust
pub fn discover(daemon_path: PathBuf) -> Result<Self> {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| anyhow::anyhow!("HOME is not set; cannot resolve LaunchAgent path"))?;
    let current_dir = std::env::current_dir()?;
    let working_dir = choose_working_dir(&current_dir, &daemon_path);
    Ok(Self::from_parts(home, daemon_path, working_dir))
}
```

- [ ] **Step 4: Run render tests**

Run:

```bash
cargo test -p voco-cli launch_agent_from_bundle_paths_renders_daemon_inside_app
```

Expected: PASS.

- [ ] **Step 5: Run focused LaunchAgent tests**

Run:

```bash
cargo test -p voco-cli commands::daemon::launch_agent::tests
```

Expected: PASS.

- [ ] **Step 6: Commit bundle rendering support**

```bash
git add crates/voco-cli/src/commands/daemon/launch_agent.rs
git commit -m "feat(cli): render LaunchAgent from app bundle paths"
```

## Task 6: Wire Bundle Install Command

**Files:**
- Modify: `crates/voco-cli/src/commands/daemon.rs`

- [ ] **Step 1: Add failing smoke test for invalid explicit bundle**

In `crates/voco-cli/tests/smoke.rs`, add:

```rust
#[test]
#[serial_test::serial]
fn install_with_missing_app_bundle_fails_loudly() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;

    voco_with_home(&tmp)
        .args(["daemon", "install", "--app-bundle", "target/Missing.app"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("app bundle not found"));

    Ok(())
}
```

- [ ] **Step 2: Run smoke test and confirm failure mode**

Run:

```bash
cargo test -p voco-cli install_with_missing_app_bundle_fails_loudly
```

Expected: FAIL if current message is `--app-bundle is parsed but bundle discovery is not wired yet`; this proves command wiring still needs real bundle discovery.

- [ ] **Step 3: Implement bundle discovery in daemon install**

In `crates/voco-cli/src/commands/daemon.rs`, replace `discover_launch_agent` with:

```rust
fn discover_launch_agent(app_bundle: Option<&std::path::Path>) -> Result<launch_agent::LaunchAgent> {
    if let Some(bundle_path) = app_bundle {
        let bundle = launch_agent::AppBundle::discover(bundle_path)?;
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .ok_or_else(|| anyhow!("HOME is not set; cannot resolve LaunchAgent path"))?;
        return Ok(launch_agent::LaunchAgent::from_parts(
            home,
            bundle.daemon_path,
            bundle.working_dir,
        ));
    }

    let daemon_path = locate_daemon_binary()?;
    launch_agent::LaunchAgent::discover(daemon_path)
}
```

- [ ] **Step 4: Print installed daemon and working directory**

At the end of `install`, before `println!("  start it with: voco daemon start");`, add:

```rust
println!("  daemon: {}", agent.paths.daemon_path.display());
println!("  working directory: {}", agent.paths.working_dir.display());
```

- [ ] **Step 5: Run missing bundle smoke test**

Run:

```bash
cargo test -p voco-cli install_with_missing_app_bundle_fails_loudly
```

Expected: PASS.

- [ ] **Step 6: Run direct daemon smoke tests**

Run:

```bash
cargo test -p voco-cli --test smoke
```

Expected: PASS; direct spawn behavior remains unchanged.

- [ ] **Step 7: Commit command wiring**

```bash
git add crates/voco-cli/src/commands/daemon.rs crates/voco-cli/tests/smoke.rs
git commit -m "feat(cli): install LaunchAgent from app bundle"
```

## Task 7: Documentation

**Files:**
- Modify: `README.md`
- Modify: `packaging/README.md`

- [ ] **Step 1: Update README LaunchAgent section**

In `README.md`, after the existing LaunchAgent install commands, add:

````markdown
Install the LaunchAgent from a development `Voco.app` bundle:

```bash
packaging/build_app_bundle.sh --profile debug
target/debug/voco daemon install --app-bundle target/Voco.app
target/debug/voco daemon start
target/debug/voco status
```

Without `--app-bundle`, `daemon install` keeps the source-tree/direct binary
install path. `--app-bundle` does not sign, notarize, copy, or install the app
under `/Applications`.
````

- [ ] **Step 2: Update packaging README**

In `packaging/README.md`, under `Development App Bundle`, add:

````markdown
Install the user LaunchAgent from the generated bundle:

```bash
target/debug/voco daemon install --app-bundle target/Voco.app
```

This renders `~/Library/LaunchAgents/com.voco.daemon.plist` so
`ProgramArguments:0` points at:

```text
target/Voco.app/Contents/MacOS/voco-daemon
```
````

- [ ] **Step 3: Verify documentation references bundle install**

Run:

```bash
rg -n "app-bundle|Contents/MacOS/voco-daemon|direct binary|Applications" README.md packaging/README.md
```

Expected: output includes both README and packaging README updates.

- [ ] **Step 4: Commit docs**

```bash
git add README.md packaging/README.md
git commit -m "docs(packaging): document bundle LaunchAgent install"
```

## Task 8: Final Verification and Manual LaunchAgent Smoke

**Files:**
- Modify: `docs/superpowers/plans/2026-05-03-voco-phase-6c-bundle-launchagent.md`

- [ ] **Step 1: Build app bundle**

Run:

```bash
packaging/tests/app_bundle_smoke.sh
```

Expected: PASS and `target/Voco.app` exists.

- [ ] **Step 2: Run Swift verification**

Run:

```bash
cd hud && swift test && swift build && cd ..
```

Expected: PASS.

- [ ] **Step 3: Run Rust formatting**

Run:

```bash
cargo fmt --all --check
```

Expected: PASS.

- [ ] **Step 4: Run Rust tests**

Run:

```bash
cargo test --workspace
```

Expected: PASS.

- [ ] **Step 5: Run Rust clippy**

Run:

```bash
cargo clippy --workspace --all-targets -- -D warnings
```

Expected: PASS.

- [ ] **Step 6: Install LaunchAgent from bundle**

Run:

```bash
target/debug/voco daemon uninstall || true
target/debug/voco daemon install --app-bundle target/Voco.app
```

Expected: PASS and output prints daemon path under `target/Voco.app/Contents/MacOS/voco-daemon`.

- [ ] **Step 7: Verify installed plist points at bundle paths**

Run:

```bash
plutil -lint ~/Library/LaunchAgents/com.voco.daemon.plist
/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" ~/Library/LaunchAgents/com.voco.daemon.plist
/usr/libexec/PlistBuddy -c "Print :WorkingDirectory" ~/Library/LaunchAgents/com.voco.daemon.plist
```

Expected:

```text
~/Library/LaunchAgents/com.voco.daemon.plist: OK
.../target/Voco.app/Contents/MacOS/voco-daemon
.../target/Voco.app/Contents/MacOS
```

- [ ] **Step 8: Start, status, stop, and uninstall**

Run:

```bash
target/debug/voco daemon start
target/debug/voco status
target/debug/voco daemon stop
target/debug/voco daemon uninstall
```

Expected: daemon starts via launchctl, status reports running/idle, stop succeeds, uninstall removes plist.

- [ ] **Step 9: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 10: Mark verification in this plan**

Update this task with:

```markdown
Verification note (2026-05-03):

- `packaging/tests/app_bundle_smoke.sh` passed.
- `cd hud && swift test && swift build && cd ..` passed.
- `cargo fmt --all --check` passed.
- `cargo test --workspace` passed.
- `cargo clippy --workspace --all-targets -- -D warnings` passed.
- `target/debug/voco daemon install --app-bundle target/Voco.app` passed.
- Installed plist `ProgramArguments:0` pointed at `target/Voco.app/Contents/MacOS/voco-daemon`.
- Installed plist `WorkingDirectory` pointed at `target/Voco.app/Contents/MacOS`.
- `target/debug/voco daemon start/status/stop/uninstall` passed.
- `git diff --check` passed.
```

Verification note (2026-05-03):

- `packaging/tests/app_bundle_smoke.sh` passed and verified `target/Voco.app`.
- Swift verification passed: `swift test` in `hud/` executed 7 XCTest tests with 0 failures, and `swift build` in `hud/` completed successfully. This was run as separate commands instead of the planned chained shell command.
- `cargo fmt --all --check` passed.
- `cargo test --workspace` passed; live Doubao network and microphone tests remained ignored as designed.
- `cargo clippy --workspace --all-targets -- -D warnings` passed.
- `target/debug/voco daemon install --app-bundle target/Voco.app` passed and printed daemon path `/private/tmp/voco-phase-6c-bundle-launchagent/target/Voco.app/Contents/MacOS/voco-daemon`.
- Installed plist `ProgramArguments:0` pointed at `/private/tmp/voco-phase-6c-bundle-launchagent/target/Voco.app/Contents/MacOS/voco-daemon`.
- Installed plist `WorkingDirectory` pointed at `/private/tmp/voco-phase-6c-bundle-launchagent/target/Voco.app/Contents/MacOS`.
- `target/debug/voco daemon start` passed via `gui/501/com.voco.daemon`; `target/debug/voco status` reported daemon running and state idle; `target/debug/voco daemon stop` passed; `target/debug/voco daemon uninstall` removed `/Users/zhangxiaolong/Library/LaunchAgents/com.voco.daemon.plist`.
- `git diff --check` passed.

- [ ] **Step 11: Commit verification update**

```bash
git add docs/superpowers/plans/2026-05-03-voco-phase-6c-bundle-launchagent.md
git commit -m "docs: mark Phase 6-C bundle LaunchAgent verification"
```

- [ ] **Step 12: Finish branch**

Use `superpowers:finishing-a-development-branch`.

Expected: present merge/PR/keep/discard options after all verification passes.

## Self-Review

- Spec coverage: explicit `--app-bundle`, direct install preservation, bundle validation, plist render path, docs, and manual LaunchAgent smoke are covered.
- Marker scan: no unresolved markers or unspecified implementation steps.
- Type consistency: the plan consistently uses `AppBundle`, `LaunchAgent::from_parts`, `DaemonAction::Install { app_bundle }`, `target/Voco.app/Contents/MacOS/voco-daemon`, and `target/Voco.app/Contents/MacOS`.
