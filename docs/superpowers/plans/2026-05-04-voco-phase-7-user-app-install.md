# Voco Phase 7 User App Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `voco app install --app-bundle <PATH>` so a generated `Voco.app` can be copied to `~/Applications/Voco.app` and the user LaunchAgent can point at the installed bundle.

**Architecture:** Keep Phase 6-C's explicit bundle-aware LaunchAgent as the lower-level primitive. Move LaunchAgent path/render/install code into a shared `commands::launch_agent` module, add a focused `commands::app` module for per-user bundle copying, and reuse the same plist validation/rendering path after copy. Copy via temp + backup rename so a failed copy does not destroy an existing installed bundle.

**Tech Stack:** Rust 2021, clap derive, anyhow, std::fs recursive copy, macOS PlistBuddy/plutil through existing LaunchAgent bundle validation, user LaunchAgent plist under `~/Library/LaunchAgents`.

---

## File Structure

- Modify: `crates/voco-cli/src/main.rs` — add `Cmd::App`, `AppAction::Install`, parser tests, and dispatch.
- Modify: `crates/voco-cli/src/commands/mod.rs` — export `app` and shared `launch_agent` modules.
- Move: `crates/voco-cli/src/commands/daemon/launch_agent.rs` -> `crates/voco-cli/src/commands/launch_agent.rs`.
- Modify: `crates/voco-cli/src/commands/daemon.rs` — import shared `launch_agent` and use shared install printing helper.
- Create: `crates/voco-cli/src/commands/app.rs` — per-user app bundle install/copy logic.
- Modify: `crates/voco-cli/tests/smoke.rs` — add app install missing-bundle and valid fake-bundle smoke tests.
- Modify: `README.md` — document `voco app install` per-user install workflow.
- Modify: `packaging/README.md` — document installed app path and LaunchAgent plist pointing at installed bundle.
- Modify: `docs/superpowers/plans/2026-05-04-voco-phase-7-user-app-install.md` — record final verification.

## Task 1: CLI Parser Red Test

**Files:**
- Modify: `crates/voco-cli/src/main.rs`

- [ ] **Step 1: Add failing parser test for app install**

In `crates/voco-cli/src/main.rs`, inside `#[cfg(test)] mod tests`, add this test after `parses_daemon_install_uninstall_actions`:

```rust
#[test]
fn parses_app_install_action() {
    let install = Cli::try_parse_from([
        "voco",
        "app",
        "install",
        "--app-bundle",
        "target/Voco.app",
    ])
    .unwrap();

    match install.command {
        Cmd::App {
            action:
                AppAction::Install {
                    app_bundle: path,
                },
        } => assert_eq!(path, std::path::PathBuf::from("target/Voco.app")),
        _ => panic!("unexpected command"),
    }
}
```

- [ ] **Step 2: Run parser test and confirm RED**

Run:

```bash
cargo test -p voco-cli parses_app_install_action
```

Expected: FAIL to compile because `Cmd::App` and `AppAction` do not exist yet.

- [ ] **Step 3: Commit RED parser test**

Run:

```bash
git add crates/voco-cli/src/main.rs
git commit -m "test(cli): cover app install parser"
```

## Task 2: CLI Parser Implementation Stub

**Files:**
- Modify: `crates/voco-cli/src/main.rs`
- Modify: `crates/voco-cli/src/commands/mod.rs`
- Create: `crates/voco-cli/src/commands/app.rs`

- [ ] **Step 1: Add app command shape**

In `crates/voco-cli/src/main.rs`, add `Cmd::App` after `Cmd::Daemon`:

```rust
/// App bundle install and local app lifecycle.
App {
    #[command(subcommand)]
    action: AppAction,
},
```

Add `AppAction` after `DaemonAction`:

```rust
#[derive(Subcommand)]
pub enum AppAction {
    /// Copy a generated Voco.app to ~/Applications and install its LaunchAgent.
    Install {
        /// Generated Voco.app bundle to install.
        #[arg(long, value_name = "PATH")]
        app_bundle: PathBuf,
    },
}
```

Update the `main()` match:

```rust
Cmd::App { action } => commands::app::run(action),
```

- [ ] **Step 2: Export app module**

In `crates/voco-cli/src/commands/mod.rs`, add:

```rust
pub mod app;
```

- [ ] **Step 3: Create stub app command module**

Create `crates/voco-cli/src/commands/app.rs`:

```rust
use crate::AppAction;
use anyhow::{bail, Result};

pub fn run(action: AppAction) -> Result<()> {
    match action {
        AppAction::Install { .. } => {
            bail!("voco app install is parsed but install implementation is not wired yet")
        }
    }
}
```

- [ ] **Step 4: Run parser test and confirm GREEN**

Run:

```bash
cargo test -p voco-cli parses_app_install_action
```

Expected: PASS.

- [ ] **Step 5: Run existing parser test**

Run:

```bash
cargo test -p voco-cli parses_daemon_install_uninstall_actions
```

Expected: PASS.

- [ ] **Step 6: Commit parser implementation**

Run:

```bash
git add crates/voco-cli/src/main.rs crates/voco-cli/src/commands/mod.rs crates/voco-cli/src/commands/app.rs
git commit -m "feat(cli): parse app install command"
```

## Task 3: Share LaunchAgent Module

**Files:**
- Move: `crates/voco-cli/src/commands/daemon/launch_agent.rs` -> `crates/voco-cli/src/commands/launch_agent.rs`
- Modify: `crates/voco-cli/src/commands/mod.rs`
- Modify: `crates/voco-cli/src/commands/daemon.rs`

- [ ] **Step 1: Run focused baseline before refactor**

Run:

```bash
cargo test -p voco-cli commands::daemon::launch_agent::tests
```

Expected: PASS before moving the module.

- [ ] **Step 2: Move launch_agent module**

Run:

```bash
git mv crates/voco-cli/src/commands/daemon/launch_agent.rs crates/voco-cli/src/commands/launch_agent.rs
```

- [ ] **Step 3: Export shared launch_agent module**

In `crates/voco-cli/src/commands/mod.rs`, add:

```rust
pub(crate) mod launch_agent;
```

- [ ] **Step 4: Update daemon module import**

In `crates/voco-cli/src/commands/daemon.rs`, delete:

```rust
mod launch_agent;
```

Add near the imports:

```rust
use super::launch_agent;
```

- [ ] **Step 5: Add shared LaunchAgent print helper**

In `crates/voco-cli/src/commands/launch_agent.rs`, after `impl LaunchAgent`, add:

```rust
pub fn install_and_print(agent: &LaunchAgent) -> Result<()> {
    match agent.install()? {
        InstallOutcome::Created => {
            println!(
                "✓ installed LaunchAgent: {}",
                agent.paths.plist_path.display()
            );
        }
        InstallOutcome::Updated => {
            println!(
                "✓ updated LaunchAgent: {}",
                agent.paths.plist_path.display()
            );
        }
        InstallOutcome::Unchanged => {
            println!(
                "✓ LaunchAgent already installed: {}",
                agent.paths.plist_path.display()
            );
        }
    }
    println!("  daemon: {}", agent.paths.daemon_path.display());
    println!("  working directory: {}", agent.paths.working_dir.display());
    println!("  start it with: voco daemon start");
    Ok(())
}
```

- [ ] **Step 6: Reuse shared helper from daemon install**

In `crates/voco-cli/src/commands/daemon.rs`, replace the body of `fn install(app_bundle: Option<PathBuf>) -> Result<()>` with:

```rust
fn install(app_bundle: Option<PathBuf>) -> Result<()> {
    let agent = discover_launch_agent(app_bundle.as_deref())?;
    launch_agent::install_and_print(&agent)
}
```

- [ ] **Step 7: Run moved LaunchAgent tests**

Run:

```bash
cargo test -p voco-cli commands::launch_agent::tests
```

Expected: PASS after module move.

- [ ] **Step 8: Run daemon smoke test**

Run:

```bash
cargo test -p voco-cli install_with_missing_app_bundle_fails_loudly
```

Expected: PASS; existing daemon bundle-install error behavior is unchanged.

- [ ] **Step 9: Commit shared LaunchAgent module**

Run:

```bash
git add crates/voco-cli/src/commands/mod.rs crates/voco-cli/src/commands/daemon.rs crates/voco-cli/src/commands/launch_agent.rs
git commit -m "refactor(cli): share LaunchAgent install helpers"
```

## Task 4: App Installer Unit Red Tests

**Files:**
- Modify: `crates/voco-cli/src/commands/app.rs`

- [ ] **Step 1: Replace app stub with tests that describe filesystem behavior**

In `crates/voco-cli/src/commands/app.rs`, keep the stub `run` function for now and append this test module:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};

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

    fn create_test_bundle(tmp: &tempfile::TempDir, name: &str) -> anyhow::Result<PathBuf> {
        let bundle = tmp.path().join(name);
        let macos = bundle.join("Contents/MacOS");
        std::fs::create_dir_all(&macos)?;
        write_bundle_plist(
            &bundle.join("Contents/Info.plist"),
            "com.voco.app",
            "voco-daemon",
        )?;
        for executable in ["voco", "voco-daemon", "voco-hud"] {
            let path = macos.join(executable);
            std::fs::write(&path, b"#!/bin/sh\n")?;
            make_executable(&path)?;
        }
        Ok(bundle)
    }

    #[test]
    fn install_destination_defaults_to_home_applications() {
        let home = Path::new("/tmp/voco-home");

        assert_eq!(
            install_destination(home),
            PathBuf::from("/tmp/voco-home/Applications/Voco.app")
        );
    }

    #[test]
    fn missing_home_fails_loudly() {
        let err = home_dir_from(None).unwrap_err();

        assert!(err
            .to_string()
            .contains("HOME is not set; cannot resolve app install path"));
    }

    #[test]
    fn applications_path_as_file_fails_without_deleting_file() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let source = create_test_bundle(&tmp, "source/Voco.app")?;
        let home = tmp.path().join("home");
        std::fs::create_dir_all(&home)?;
        let applications = home.join("Applications");
        std::fs::write(&applications, b"not a directory")?;

        let err = install_app_bundle(&source, &home).unwrap_err();

        assert!(err.to_string().contains("Applications path is not a directory"));
        assert_eq!(std::fs::read(&applications)?, b"not a directory");
        Ok(())
    }

    #[test]
    fn destination_file_fails_without_deleting_file() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let source = create_test_bundle(&tmp, "source/Voco.app")?;
        let home = tmp.path().join("home");
        let applications = home.join("Applications");
        std::fs::create_dir_all(&applications)?;
        let destination = applications.join("Voco.app");
        std::fs::write(&destination, b"not a directory")?;

        let err = install_app_bundle(&source, &home).unwrap_err();

        assert!(err
            .to_string()
            .contains("installed app path exists but is not a directory"));
        assert_eq!(std::fs::read(&destination)?, b"not a directory");
        Ok(())
    }

    #[test]
    fn install_app_bundle_copies_bundle_and_preserves_executables() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let source = create_test_bundle(&tmp, "source/Voco.app")?;
        let home = tmp.path().join("home");

        let installed = install_app_bundle(&source, &home)?;

        assert_eq!(installed.bundle_path, home.join("Applications/Voco.app").canonicalize()?);
        assert!(installed.daemon_path.is_file());
        assert!(is_executable(&installed.daemon_path));
        assert!(is_executable(&installed.working_dir.join("voco")));
        assert!(is_executable(&installed.working_dir.join("voco-hud")));
        Ok(())
    }

    #[test]
    fn replacing_existing_bundle_keeps_new_bundle() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let first = create_test_bundle(&tmp, "first/Voco.app")?;
        let second = create_test_bundle(&tmp, "second/Voco.app")?;
        let home = tmp.path().join("home");

        install_app_bundle(&first, &home)?;
        std::fs::write(
            home.join("Applications/Voco.app/Contents/MacOS/marker"),
            b"old",
        )?;
        let installed = install_app_bundle(&second, &home)?;

        assert!(installed.daemon_path.is_file());
        assert!(!home
            .join("Applications/Voco.app/Contents/MacOS/marker")
            .exists());
        Ok(())
    }

    #[cfg(unix)]
    fn is_executable(path: &Path) -> bool {
        use std::os::unix::fs::PermissionsExt;
        std::fs::metadata(path)
            .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    }
}
```

- [ ] **Step 2: Run app unit tests and confirm RED**

Run:

```bash
cargo test -p voco-cli commands::app::tests
```

Expected: FAIL to compile because `install_destination`, `home_dir_from`, and `install_app_bundle` do not exist.

- [ ] **Step 3: Commit RED app installer tests**

Run:

```bash
git add crates/voco-cli/src/commands/app.rs
git commit -m "test(cli): cover per-user app bundle install paths"
```

## Task 5: App Installer Filesystem Implementation

**Files:**
- Modify: `crates/voco-cli/src/commands/app.rs`

- [ ] **Step 1: Replace app stub with filesystem implementation**

Replace the top-level implementation in `crates/voco-cli/src/commands/app.rs` before the test module with:

```rust
use crate::commands::launch_agent::AppBundle;
use crate::AppAction;
use anyhow::{anyhow, bail, Context, Result};
use std::ffi::OsString;
use std::path::{Path, PathBuf};

pub fn run(action: AppAction) -> Result<()> {
    match action {
        AppAction::Install { app_bundle } => install(app_bundle),
    }
}

fn install(app_bundle: PathBuf) -> Result<()> {
    let home = home_dir()?;
    let installed = install_app_bundle(&app_bundle, &home)?;
    println!("✓ installed app bundle: {}", installed.bundle_path.display());
    bail!("app bundle copied but LaunchAgent install is not wired yet");
}

fn home_dir() -> Result<PathBuf> {
    home_dir_from(std::env::var_os("HOME"))
}

fn home_dir_from(home: Option<OsString>) -> Result<PathBuf> {
    home.map(PathBuf::from)
        .ok_or_else(|| anyhow!("HOME is not set; cannot resolve app install path"))
}

fn install_destination(home: &Path) -> PathBuf {
    home.join("Applications/Voco.app")
}

fn install_app_bundle(source_bundle: &Path, home: &Path) -> Result<AppBundle> {
    let source = AppBundle::discover(source_bundle)?;
    let destination = install_destination(home);
    let applications = destination
        .parent()
        .ok_or_else(|| anyhow!("cannot resolve Applications directory for {}", destination.display()))?;

    if applications.exists() && !applications.is_dir() {
        bail!(
            "Applications path is not a directory: {}",
            applications.display()
        );
    }
    std::fs::create_dir_all(applications)
        .with_context(|| format!("create Applications directory {}", applications.display()))?;

    if destination.exists() && !destination.is_dir() {
        bail!(
            "installed app path exists but is not a directory: {}",
            destination.display()
        );
    }

    let pid = std::process::id();
    let tmp = applications.join(format!(".Voco.app.tmp-{pid}"));
    let backup = applications.join(format!(".Voco.app.backup-{pid}"));
    remove_dir_if_exists(&tmp)?;
    remove_dir_if_exists(&backup)?;

    copy_dir_recursive(&source.bundle_path, &tmp).with_context(|| {
        format!(
            "copy app bundle from {} to {} failed",
            source.bundle_path.display(),
            tmp.display()
        )
    })?;
    AppBundle::discover(&tmp)?;

    let mut backup_created = false;
    if destination.exists() {
        std::fs::rename(&destination, &backup).with_context(|| {
            format!(
                "replace installed app bundle at {} failed",
                destination.display()
            )
        })?;
        backup_created = true;
    }

    if let Err(err) = std::fs::rename(&tmp, &destination) {
        if backup_created {
            let _ = std::fs::rename(&backup, &destination);
        }
        return Err(anyhow!(
            "replace installed app bundle at {} failed: {}",
            destination.display(),
            err
        ));
    }

    let installed = AppBundle::discover(&destination)?;
    if backup_created {
        remove_dir_if_exists(&backup)?;
    }
    Ok(installed)
}

fn remove_dir_if_exists(path: &Path) -> Result<()> {
    match std::fs::remove_dir_all(path) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(err).with_context(|| format!("remove {}", path.display())),
    }
}

fn copy_dir_recursive(source: &Path, destination: &Path) -> Result<()> {
    let metadata = std::fs::symlink_metadata(source)
        .with_context(|| format!("inspect {}", source.display()))?;
    if metadata.file_type().is_symlink() {
        bail!("symlink in app bundle is not supported: {}", source.display());
    }
    if metadata.is_dir() {
        std::fs::create_dir(destination)
            .with_context(|| format!("create directory {}", destination.display()))?;
        std::fs::set_permissions(destination, metadata.permissions()).with_context(|| {
            format!("copy permissions to directory {}", destination.display())
        })?;
        for entry in std::fs::read_dir(source)
            .with_context(|| format!("read directory {}", source.display()))?
        {
            let entry = entry?;
            copy_dir_recursive(&entry.path(), &destination.join(entry.file_name()))?;
        }
        return Ok(());
    }
    if metadata.is_file() {
        std::fs::copy(source, destination).with_context(|| {
            format!("copy file {} to {}", source.display(), destination.display())
        })?;
        std::fs::set_permissions(destination, metadata.permissions())
            .with_context(|| format!("copy permissions to file {}", destination.display()))?;
        return Ok(());
    }
    bail!("unsupported file in app bundle: {}", source.display())
}
```

- [ ] **Step 2: Run app unit tests and confirm GREEN**

Run:

```bash
cargo test -p voco-cli commands::app::tests
```

Expected: PASS.

- [ ] **Step 3: Run app parser test**

Run:

```bash
cargo test -p voco-cli parses_app_install_action
```

Expected: PASS.

- [ ] **Step 4: Commit filesystem implementation**

Run:

```bash
git add crates/voco-cli/src/commands/app.rs
git commit -m "feat(cli): copy Voco app bundle to user Applications"
```

## Task 6: Wire App Install to LaunchAgent

**Files:**
- Modify: `crates/voco-cli/src/commands/app.rs`
- Modify: `crates/voco-cli/tests/smoke.rs`

- [ ] **Step 1: Add missing-bundle app smoke test**

In `crates/voco-cli/tests/smoke.rs`, add this test after `install_with_missing_app_bundle_fails_loudly`:

```rust
#[test]
#[serial_test::serial]
fn app_install_with_missing_bundle_fails_loudly() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;

    voco_with_home(&tmp)
        .args(["app", "install", "--app-bundle", "target/Missing.app"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("app bundle not found"));

    Ok(())
}
```

- [ ] **Step 2: Add valid app install smoke helpers and test**

In `crates/voco-cli/tests/smoke.rs`, add these helpers near `voco_with_home`:

```rust
fn write_bundle_plist(path: &std::path::Path) -> anyhow::Result<()> {
    let contents = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.voco.app</string>
  <key>CFBundleExecutable</key>
  <string>voco-daemon</string>
</dict>
</plist>
"#;
    std::fs::write(path, contents)?;
    Ok(())
}

#[cfg(unix)]
fn make_executable(path: &std::path::Path) -> anyhow::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let mut permissions = std::fs::metadata(path)?.permissions();
    permissions.set_mode(0o755);
    std::fs::set_permissions(path, permissions)?;
    Ok(())
}

fn create_test_bundle(tmp: &TempDir) -> anyhow::Result<std::path::PathBuf> {
    let bundle = tmp.path().join("target/Voco.app");
    let macos = bundle.join("Contents/MacOS");
    std::fs::create_dir_all(&macos)?;
    write_bundle_plist(&bundle.join("Contents/Info.plist"))?;
    for executable in ["voco", "voco-daemon", "voco-hud"] {
        let path = macos.join(executable);
        std::fs::write(&path, b"#!/bin/sh\n")?;
        make_executable(&path)?;
    }
    Ok(bundle)
}
```

Add this test after `app_install_with_missing_bundle_fails_loudly`:

```rust
#[test]
#[serial_test::serial]
fn app_install_copies_bundle_and_installs_launch_agent() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    let bundle = create_test_bundle(&tmp)?;
    let home = tmp.path().join("home");
    let installed_daemon = home.join("Applications/Voco.app/Contents/MacOS/voco-daemon");
    let plist = home.join("Library/LaunchAgents/com.voco.daemon.plist");

    voco_with_home(&tmp)
        .args(["app", "install", "--app-bundle"])
        .arg(&bundle)
        .assert()
        .success()
        .stdout(predicate::str::contains("installed app bundle"))
        .stdout(predicate::str::contains("Applications/Voco.app"))
        .stdout(predicate::str::contains("Contents/MacOS/voco-daemon"));

    assert!(installed_daemon.is_file());
    assert!(plist.is_file());
    let rendered = std::fs::read_to_string(plist)?;
    assert!(rendered.contains(&installed_daemon.display().to_string()));
    assert!(rendered.contains(
        &home
            .join("Applications/Voco.app/Contents/MacOS")
            .display()
            .to_string()
    ));
    Ok(())
}
```

- [ ] **Step 3: Run app install smoke tests and confirm RED**

Run:

```bash
cargo test -p voco-cli app_install_
```

Expected: FAIL. The missing-bundle test may already pass if filesystem implementation runs first, but the valid install test must fail because app install still bails with `app bundle copied but LaunchAgent install is not wired yet`.

- [ ] **Step 4: Wire app install to shared LaunchAgent helper**

In `crates/voco-cli/src/commands/app.rs`, update imports:

```rust
use crate::commands::launch_agent::{self, AppBundle, LaunchAgent};
```

Replace `fn install(app_bundle: PathBuf) -> Result<()>` with:

```rust
fn install(app_bundle: PathBuf) -> Result<()> {
    let home = home_dir()?;
    let installed = install_app_bundle(&app_bundle, &home)?;
    println!("✓ installed app bundle: {}", installed.bundle_path.display());
    let agent = LaunchAgent::from_parts(
        home,
        installed.daemon_path.clone(),
        installed.working_dir.clone(),
    );
    launch_agent::install_and_print(&agent).map_err(|err| {
        anyhow!(
            "installed app bundle at {} but LaunchAgent install failed: {}",
            installed.bundle_path.display(),
            err
        )
    })
}
```

- [ ] **Step 5: Run app install smoke tests and confirm GREEN**

Run:

```bash
cargo test -p voco-cli app_install_
```

Expected: PASS.

- [ ] **Step 6: Run full voco-cli smoke tests**

Run:

```bash
cargo test -p voco-cli --test smoke
```

Expected: PASS; direct daemon start/stop behavior remains unchanged.

- [ ] **Step 7: Commit LaunchAgent app install wiring**

Run:

```bash
git add crates/voco-cli/src/commands/app.rs crates/voco-cli/tests/smoke.rs
git commit -m "feat(cli): install LaunchAgent from user app bundle"
```

## Task 7: Documentation

**Files:**
- Modify: `README.md`
- Modify: `packaging/README.md`

- [ ] **Step 1: Update README with per-user install flow**

In `README.md`, under `## Development App Bundle`, replace the current bundle install wording with:

````markdown
Build and install a local per-user app bundle:

```bash
packaging/build_app_bundle.sh --profile release
target/release/voco app install --app-bundle target/Voco.app
target/release/voco daemon start
target/release/voco status
```

`app install` copies the generated bundle to:

```text
~/Applications/Voco.app
```

It also installs or updates `~/Library/LaunchAgents/com.voco.daemon.plist`
so launchd runs:

```text
~/Applications/Voco.app/Contents/MacOS/voco-daemon
```

No `sudo` is required. This local install flow does not sign, notarize,
create a DMG/pkg, or install under `/Applications`.
````

- [ ] **Step 2: Update packaging README with app install details**

In `packaging/README.md`, after the generated bundle contents list, add:

````markdown
Install the generated bundle for the current user:

```bash
target/debug/voco app install --app-bundle target/Voco.app
```

The command copies the bundle to:

```text
~/Applications/Voco.app
```

and renders `~/Library/LaunchAgents/com.voco.daemon.plist` so
`ProgramArguments:0` points at:

```text
~/Applications/Voco.app/Contents/MacOS/voco-daemon
```

For development-only plist rendering without copying the app, this lower-level
command remains available:

```bash
target/debug/voco daemon install --app-bundle target/Voco.app
```
````

Update the final deferred-work paragraph to:

```markdown
Signing, notarization, DMG/pkg creation, and `/Applications` installation are
deferred.
```

- [ ] **Step 3: Verify docs mention app install and installed daemon path**

Run:

```bash
rg -n "app install|~/Applications/Voco.app|Contents/MacOS/voco-daemon|/Applications|DMG|notar" README.md packaging/README.md
```

Expected: output includes both README files, the `app install` command, the installed bundle path, and the explicit deferred distribution work.

- [ ] **Step 4: Commit docs**

Run:

```bash
git add README.md packaging/README.md
git commit -m "docs(packaging): document user app install"
```

## Task 8: Final Verification and Manual App Install Smoke

**Files:**
- Modify: `docs/superpowers/plans/2026-05-04-voco-phase-7-user-app-install.md`

- [ ] **Step 1: Build and verify development bundle**

Run:

```bash
packaging/tests/app_bundle_smoke.sh
```

Expected: PASS and `target/Voco.app` exists.

- [ ] **Step 2: Run Rust formatting**

Run:

```bash
cargo fmt --all --check
```

Expected: PASS.

- [ ] **Step 3: Run Rust tests**

Run:

```bash
cargo test --workspace
```

Expected: PASS. Live Doubao network and microphone tests remain ignored unless explicitly enabled.

- [ ] **Step 4: Run Rust clippy**

Run:

```bash
cargo clippy --workspace --all-targets -- -D warnings
```

Expected: PASS.

- [ ] **Step 5: Run manual app install smoke**

Run:

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
test ! -f ~/Library/LaunchAgents/com.voco.daemon.plist
```

Expected:

- `app install` succeeds and prints `~/Applications/Voco.app`.
- `~/Applications/Voco.app/Contents/MacOS/voco-daemon` exists and is executable.
- plist lint passes.
- `ProgramArguments:0` points at `~/Applications/Voco.app/Contents/MacOS/voco-daemon`.
- `WorkingDirectory` points at `~/Applications/Voco.app/Contents/MacOS`.
- daemon starts via launchctl.
- `voco status` reports daemon running and state idle.
- stop succeeds.
- uninstall removes the plist.
- installed app bundle remains in `~/Applications/Voco.app`.

- [ ] **Step 6: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 7: Record verification results in this plan**

Append this note under Task 8, replacing descriptions with observed results:

```markdown
Verification note (2026-05-04):

- `packaging/tests/app_bundle_smoke.sh` passed.
- `cargo fmt --all --check` passed.
- `cargo test --workspace` passed; live network/microphone tests remained ignored as designed.
- `cargo clippy --workspace --all-targets -- -D warnings` passed.
- `target/debug/voco app install --app-bundle target/Voco.app` passed and copied the bundle to `~/Applications/Voco.app`.
- `~/Applications/Voco.app/Contents/MacOS/voco-daemon` existed and was executable.
- Installed plist `ProgramArguments:0` pointed at `~/Applications/Voco.app/Contents/MacOS/voco-daemon`.
- Installed plist `WorkingDirectory` pointed at `~/Applications/Voco.app/Contents/MacOS`.
- `target/debug/voco daemon start/status/stop/uninstall` passed.
- `git diff --check` passed.
```

Verification note (2026-05-04):

- `packaging/tests/app_bundle_smoke.sh` passed.
- `cargo fmt --all --check` passed.
- `cargo test --workspace` passed; live network/microphone tests remained ignored as designed.
- `cargo clippy --workspace --all-targets -- -D warnings` passed.
- `target/debug/voco app install --app-bundle target/Voco.app` passed and copied the bundle to `~/Applications/Voco.app`.
- `~/Applications/Voco.app/Contents/MacOS/voco-daemon` existed and was executable.
- `plutil -lint ~/Library/LaunchAgents/com.voco.daemon.plist` passed.
- Installed plist `ProgramArguments:0` pointed at `~/Applications/Voco.app/Contents/MacOS/voco-daemon`.
- Installed plist `WorkingDirectory` pointed at `~/Applications/Voco.app/Contents/MacOS`.
- `target/debug/voco daemon start` passed via `launchctl`.
- `target/debug/voco status` reported daemon running with `state: idle`.
- `target/debug/voco daemon stop` passed.
- `target/debug/voco daemon uninstall` removed the plist.
- `test ! -f ~/Library/LaunchAgents/com.voco.daemon.plist` passed.
- `git diff --check` passed.

- [ ] **Step 8: Commit verification update**

Run:

```bash
git add docs/superpowers/plans/2026-05-04-voco-phase-7-user-app-install.md
git commit -m "docs: mark Phase 7 user app install verification"
```

- [ ] **Step 9: Finish branch**

Use `superpowers:finishing-a-development-branch`.

Expected: present merge/PR/keep/discard options after all automated gates pass and the manual app install smoke is either passed or explicitly recorded as blocked by an environment issue.

## Self-Review

- Spec coverage: parser, per-user destination, source validation, temp copy, destination validation, installed-bundle validation, LaunchAgent plist, docs, and manual verification are covered.
- Scope control: no `/Applications`, `sudo`, signing, notarization, DMG/pkg, menu bar, settings UI, Keychain, or `app uninstall` work is included.
- Type consistency: `Cmd::App`, `AppAction::Install`, `install_app_bundle`, `install_destination`, `home_dir_from`, `AppBundle`, `LaunchAgent`, and `launch_agent::install_and_print` are named consistently across tasks.
