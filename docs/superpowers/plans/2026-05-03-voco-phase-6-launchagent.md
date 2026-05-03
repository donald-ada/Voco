# Voco Phase 6-A LaunchAgent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user-level macOS LaunchAgent installation and lifecycle management for `voco-daemon` while preserving the current direct-spawn development workflow.

**Architecture:** Keep Phase 5's process model: `voco-daemon` remains the long-running Rust process and starts the separate Swift `voco-hud` helper. Add a focused private CLI module for LaunchAgent path discovery, plist rendering, atomic plist writes, and `launchctl` execution. `voco status` remains IPC-based; `voco daemon logs` remains file-based.

**Tech Stack:** Rust, clap, std filesystem/process APIs, macOS `launchctl`, existing `packaging/com.voco.daemon.plist.tmpl`, existing `voco-cli` integration tests.

---

## File Structure

- Modify `crates/voco-cli/src/main.rs` — add `install` and `uninstall` subcommands to `DaemonAction` and parser tests.
- Modify `crates/voco-cli/src/commands/daemon.rs` — keep public `run(action)` entry point, preserve direct-spawn fallback, and delegate installed LaunchAgent behavior to the new module.
- Create `crates/voco-cli/src/commands/daemon/launch_agent.rs` — private implementation for plist rendering, installation file operations, `launchctl` command execution, and classification of common launchctl outcomes.
- Modify `packaging/com.voco.daemon.plist.tmpl` — add `WorkingDirectory` using `{{WORKING_DIR}}`.
- Modify `README.md` — document development fallback and installed LaunchAgent quickstart.
- Modify `packaging/README.md` — document the now-active Phase 6-A LaunchAgent behavior.
- Modify `docs/superpowers/plans/2026-05-03-voco-phase-6-launchagent.md` — track task completion notes and manual smoke results.

---

## Task 1: LaunchAgent Plist Rendering and Path Model

**Files:**
- Modify: `crates/voco-cli/src/commands/daemon.rs`
- Create: `crates/voco-cli/src/commands/daemon/launch_agent.rs`
- Modify: `packaging/com.voco.daemon.plist.tmpl`

- [ ] **Step 1: Add the module declaration and failing renderer tests**

In `crates/voco-cli/src/commands/daemon.rs`, add this near the top after imports:

```rust
mod launch_agent;
```

Create `crates/voco-cli/src/commands/daemon/launch_agent.rs` with this test-first skeleton:

```rust
use std::path::{Path, PathBuf};

pub const LABEL: &str = "com.voco.daemon";

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LaunchAgentPaths {
    pub plist_path: PathBuf,
    pub daemon_path: PathBuf,
    pub working_dir: PathBuf,
    pub home: PathBuf,
}

pub fn render_plist(paths: &LaunchAgentPaths) -> String {
    render_plist_from_template(plist_template(), paths)
}

fn render_plist_from_template(template: &str, paths: &LaunchAgentPaths) -> String {
    template
        .replace("{{VOCO_DAEMON_PATH}}", &xml_escape(&paths.daemon_path.display().to_string()))
        .replace("{{HOME}}", &xml_escape(&paths.home.display().to_string()))
        .replace("{{WORKING_DIR}}", &xml_escape(&paths.working_dir.display().to_string()))
}

fn plist_template() -> &'static str {
    include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../packaging/com.voco.daemon.plist.tmpl"
    ))
}

fn xml_escape(input: &str) -> String {
    input
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

pub fn choose_working_dir(current_dir: &Path, daemon_path: &Path) -> PathBuf {
    let source_tree = current_dir.join("Cargo.toml").is_file()
        && current_dir.join("hud/Package.swift").is_file()
        && current_dir
            .join("packaging/com.voco.daemon.plist.tmpl")
            .is_file();
    if source_tree {
        current_dir.to_path_buf()
    } else {
        daemon_path
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_else(|| current_dir.to_path_buf())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn paths(home: &str, daemon: &str, working_dir: &str) -> LaunchAgentPaths {
        LaunchAgentPaths {
            plist_path: PathBuf::from(home).join("Library/LaunchAgents/com.voco.daemon.plist"),
            daemon_path: PathBuf::from(daemon),
            working_dir: PathBuf::from(working_dir),
            home: PathBuf::from(home),
        }
    }

    #[test]
    fn renders_plist_with_replaced_values() {
        let rendered = render_plist_from_template(
            "<string>{{VOCO_DAEMON_PATH}}</string><string>{{HOME}}</string><string>{{WORKING_DIR}}</string>",
            &paths("/Users/me", "/opt/voco/voco-daemon", "/opt/voco"),
        );

        assert_eq!(
            rendered,
            "<string>/opt/voco/voco-daemon</string><string>/Users/me</string><string>/opt/voco</string>"
        );
    }

    #[test]
    fn renders_plist_with_xml_escaped_paths() {
        let rendered = render_plist_from_template(
            "<string>{{VOCO_DAEMON_PATH}}</string><string>{{HOME}}</string><string>{{WORKING_DIR}}</string>",
            &paths(
                "/Users/a&b",
                "/tmp/voco<debug>/voco-daemon",
                "/tmp/quote\"single'work",
            ),
        );

        assert_eq!(
            rendered,
            "<string>/tmp/voco&lt;debug&gt;/voco-daemon</string><string>/Users/a&amp;b</string><string>/tmp/quote&quot;single&apos;work</string>"
        );
    }

    #[test]
    fn real_template_renders_working_directory() {
        let rendered = render_plist(&paths("/Users/me", "/opt/voco/voco-daemon", "/opt/voco"));

        assert!(rendered.contains("<key>WorkingDirectory</key>"));
        assert!(rendered.contains("<string>/opt/voco</string>"));
        assert!(!rendered.contains("{{WORKING_DIR}}"));
    }

    #[test]
    fn source_tree_current_dir_is_working_dir() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        std::fs::write(tmp.path().join("Cargo.toml"), "[workspace]\n")?;
        std::fs::create_dir_all(tmp.path().join("hud"))?;
        std::fs::write(tmp.path().join("hud/Package.swift"), "// swift\n")?;
        std::fs::create_dir_all(tmp.path().join("packaging"))?;
        std::fs::write(
            tmp.path().join("packaging/com.voco.daemon.plist.tmpl"),
            "<plist/>",
        )?;

        let daemon = tmp.path().join("target/debug/voco-daemon");
        assert_eq!(choose_working_dir(tmp.path(), &daemon), tmp.path());
        Ok(())
    }

    #[test]
    fn non_source_tree_uses_daemon_parent_as_working_dir() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let bin_dir = tmp.path().join("bin");
        std::fs::create_dir_all(&bin_dir)?;
        let daemon = bin_dir.join("voco-daemon");

        assert_eq!(choose_working_dir(tmp.path(), &daemon), bin_dir);
        Ok(())
    }
}
```

- [ ] **Step 2: Run renderer tests and confirm the missing template variable failure**

Run:

```bash
cargo test -p voco-cli real_template_renders_working_directory -- --nocapture
```

Expected: tests that exercise the real template fail because `packaging/com.voco.daemon.plist.tmpl` does not yet contain `{{WORKING_DIR}}`.

- [ ] **Step 3: Add `WorkingDirectory` to the plist template**

In `packaging/com.voco.daemon.plist.tmpl`, insert this block after the `ProgramArguments` array and before `RunAtLoad`:

```xml
  <key>WorkingDirectory</key>
  <string>{{WORKING_DIR}}</string>
```

- [ ] **Step 4: Run renderer and path tests**

Run:

```bash
cargo test -p voco-cli launch_agent
```

Expected: all LaunchAgent renderer and path tests pass.

- [ ] **Step 5: Run formatting**

Run:

```bash
cargo fmt --all
cargo fmt --all --check
```

Expected: formatting check exits 0.

- [ ] **Step 6: Commit**

Run:

```bash
git add crates/voco-cli/src/commands/daemon.rs crates/voco-cli/src/commands/daemon/launch_agent.rs packaging/com.voco.daemon.plist.tmpl
git commit -m "feat(cli): add LaunchAgent plist renderer"
```

---

## Task 2: Atomic Plist Install and Remove Operations

**Files:**
- Modify: `crates/voco-cli/src/commands/daemon/launch_agent.rs`

- [ ] **Step 1: Add failing install outcome tests**

Append these tests to the existing `#[cfg(test)] mod tests` in `crates/voco-cli/src/commands/daemon/launch_agent.rs`:

```rust
    fn temp_paths(tmp: &tempfile::TempDir) -> LaunchAgentPaths {
        LaunchAgentPaths {
            plist_path: tmp
                .path()
                .join("home/Library/LaunchAgents/com.voco.daemon.plist"),
            daemon_path: tmp.path().join("bin/voco-daemon"),
            working_dir: tmp.path().join("bin"),
            home: tmp.path().join("home"),
        }
    }

    #[test]
    fn install_plist_creates_file_and_parent_dir() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let paths = temp_paths(&tmp);
        let rendered = "<plist><dict><key>Label</key><string>com.voco.daemon</string></dict></plist>";

        assert_eq!(install_plist(&paths.plist_path, rendered)?, InstallOutcome::Created);
        assert_eq!(std::fs::read_to_string(&paths.plist_path)?, rendered);
        Ok(())
    }

    #[test]
    fn install_plist_reports_unchanged_for_identical_content() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let paths = temp_paths(&tmp);
        let rendered = "<plist>same</plist>";

        assert_eq!(install_plist(&paths.plist_path, rendered)?, InstallOutcome::Created);
        assert_eq!(install_plist(&paths.plist_path, rendered)?, InstallOutcome::Unchanged);
        Ok(())
    }

    #[test]
    fn install_plist_reports_updated_for_different_content() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let paths = temp_paths(&tmp);

        assert_eq!(install_plist(&paths.plist_path, "<plist>old</plist>")?, InstallOutcome::Created);
        assert_eq!(install_plist(&paths.plist_path, "<plist>new</plist>")?, InstallOutcome::Updated);
        assert_eq!(std::fs::read_to_string(&paths.plist_path)?, "<plist>new</plist>");
        Ok(())
    }

    #[test]
    fn remove_plist_is_idempotent() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let paths = temp_paths(&tmp);

        assert!(!remove_plist(&paths.plist_path)?);
        install_plist(&paths.plist_path, "<plist/>")?;
        assert!(remove_plist(&paths.plist_path)?);
        assert!(!paths.plist_path.exists());
        assert!(!remove_plist(&paths.plist_path)?);
        Ok(())
    }
```

- [ ] **Step 2: Run install tests and confirm failure**

Run:

```bash
cargo test -p voco-cli install_plist -- --nocapture
```

Expected: compile fails because `InstallOutcome`, `install_plist`, and `remove_plist` do not exist.

- [ ] **Step 3: Implement install outcomes and atomic file operations**

Add `anyhow::Result` to the imports at the top of `crates/voco-cli/src/commands/daemon/launch_agent.rs`:

```rust
use anyhow::Result;
```

Add this near the `LaunchAgentPaths` definition:

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InstallOutcome {
    Created,
    Updated,
    Unchanged,
}
```

Add these functions below `render_plist`:

```rust
pub fn install_plist(path: &Path, rendered: &str) -> Result<InstallOutcome> {
    let existed = path.exists();
    if let Ok(existing) = std::fs::read_to_string(path) {
        if existing == rendered {
            return Ok(InstallOutcome::Unchanged);
        }
    }

    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let tmp_path = path.with_extension("plist.tmp");
    std::fs::write(&tmp_path, rendered)?;
    std::fs::rename(&tmp_path, path)?;

    Ok(if existed {
        InstallOutcome::Updated
    } else {
        InstallOutcome::Created
    })
}

pub fn remove_plist(path: &Path) -> Result<bool> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(true),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(err) => Err(err.into()),
    }
}
```

- [ ] **Step 4: Run install/remove tests**

Run:

```bash
cargo test -p voco-cli install_plist -- --nocapture
cargo test -p voco-cli remove_plist_is_idempotent -- --nocapture
```

Expected: install and remove tests pass.

- [ ] **Step 5: Verify formatting and focused tests**

Run:

```bash
cargo fmt --all --check
cargo test -p voco-cli install_plist
cargo test -p voco-cli remove_plist_is_idempotent
```

Expected: formatting check exits 0 and focused tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add crates/voco-cli/src/commands/daemon/launch_agent.rs
git commit -m "feat(cli): install LaunchAgent plist atomically"
```

---

## Task 3: `voco daemon install` and `uninstall` CLI Commands

**Files:**
- Modify: `crates/voco-cli/src/main.rs`
- Modify: `crates/voco-cli/src/commands/daemon.rs`
- Modify: `crates/voco-cli/src/commands/daemon/launch_agent.rs`

- [ ] **Step 1: Add failing clap parser tests**

Append this test module to `crates/voco-cli/src/main.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    #[test]
    fn parses_daemon_install_uninstall_actions() {
        let install = Cli::try_parse_from(["voco", "daemon", "install"]).unwrap();
        assert!(matches!(
            install.command,
            Cmd::Daemon {
                action: DaemonAction::Install
            }
        ));

        let uninstall = Cli::try_parse_from(["voco", "daemon", "uninstall"]).unwrap();
        assert!(matches!(
            uninstall.command,
            Cmd::Daemon {
                action: DaemonAction::Uninstall
            }
        ));
    }
}
```

- [ ] **Step 2: Run parser test and confirm failure**

Run:

```bash
cargo test -p voco-cli parses_daemon_install_uninstall_actions
```

Expected: compile fails because `DaemonAction::Install` and `DaemonAction::Uninstall` do not exist.

- [ ] **Step 3: Add command variants**

In `crates/voco-cli/src/main.rs`, replace the `DaemonAction` enum with:

```rust
#[derive(Subcommand)]
pub enum DaemonAction {
    /// Install the user LaunchAgent plist without starting the daemon.
    Install,
    /// Stop and remove the user LaunchAgent plist. Config and logs are preserved.
    Uninstall,
    Start,
    Stop,
    Restart,
    Logs {
        #[arg(short, long)]
        follow: bool,
        /// How many trailing lines to show before following.
        #[arg(short = 'n', long, default_value_t = 50)]
        lines: u32,
    },
}
```

- [ ] **Step 4: Add LaunchAgent discovery and high-level install/uninstall helpers**

In `crates/voco-cli/src/commands/daemon/launch_agent.rs`, add this type and implementation below `InstallOutcome`:

```rust
#[derive(Clone, Debug)]
pub struct LaunchAgent {
    pub label: &'static str,
    pub paths: LaunchAgentPaths,
}

impl LaunchAgent {
    pub fn discover(daemon_path: PathBuf) -> Result<Self> {
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .ok_or_else(|| anyhow::anyhow!("HOME is not set; cannot resolve LaunchAgent path"))?;
        let current_dir = std::env::current_dir()?;
        let working_dir = choose_working_dir(&current_dir, &daemon_path);
        let plist_path = home.join("Library/LaunchAgents/com.voco.daemon.plist");

        Ok(Self {
            label: LABEL,
            paths: LaunchAgentPaths {
                plist_path,
                daemon_path,
                working_dir,
                home,
            },
        })
    }

    pub fn is_installed(&self) -> bool {
        self.paths.plist_path.is_file()
    }

    pub fn install(&self) -> Result<InstallOutcome> {
        install_plist(&self.paths.plist_path, &render_plist(&self.paths))
    }

    pub fn uninstall_plist(&self) -> Result<bool> {
        remove_plist(&self.paths.plist_path)
    }
}
```

- [ ] **Step 5: Wire install/uninstall actions**

In `crates/voco-cli/src/commands/daemon.rs`, update `run`:

```rust
pub fn run(action: DaemonAction) -> Result<()> {
    match action {
        DaemonAction::Install => install(),
        DaemonAction::Uninstall => uninstall(),
        DaemonAction::Start => start(),
        DaemonAction::Stop => stop(),
        DaemonAction::Restart => {
            let _ = stop();
            std::thread::sleep(Duration::from_millis(200));
            start()
        }
        DaemonAction::Logs { follow, lines } => logs(follow, lines),
    }
}
```

Add these functions above `start()`:

```rust
fn install() -> Result<()> {
    let daemon_path = locate_daemon_binary()?;
    let agent = launch_agent::LaunchAgent::discover(daemon_path)?;
    match agent.install()? {
        launch_agent::InstallOutcome::Created => {
            println!("✓ installed LaunchAgent: {}", agent.paths.plist_path.display());
        }
        launch_agent::InstallOutcome::Updated => {
            println!("✓ updated LaunchAgent: {}", agent.paths.plist_path.display());
        }
        launch_agent::InstallOutcome::Unchanged => {
            println!("✓ LaunchAgent already installed: {}", agent.paths.plist_path.display());
        }
    }
    println!("  start it with: voco daemon start");
    Ok(())
}

fn uninstall() -> Result<()> {
    let daemon_path = locate_daemon_binary()?;
    let agent = launch_agent::LaunchAgent::discover(daemon_path)?;
    if agent.uninstall_plist()? {
        println!("✓ removed LaunchAgent: {}", agent.paths.plist_path.display());
    } else {
        println!("✓ LaunchAgent already uninstalled");
    }
    Ok(())
}
```

- [ ] **Step 6: Run parser and focused module tests**

Run:

```bash
cargo test -p voco-cli parses_daemon_install_uninstall_actions
cargo test -p voco-cli install_plist
cargo test -p voco-cli remove_plist_is_idempotent
```

Expected: parser tests and LaunchAgent file operation tests pass.

- [ ] **Step 7: Run `--help` smoke**

Run:

```bash
cargo run -p voco-cli -- daemon --help
```

Expected: output includes `install`, `uninstall`, `start`, `stop`, `restart`, and `logs`.

- [ ] **Step 8: Commit**

Run:

```bash
git add crates/voco-cli/src/main.rs crates/voco-cli/src/commands/daemon.rs crates/voco-cli/src/commands/daemon/launch_agent.rs
git commit -m "feat(cli): add daemon install commands"
```

---

## Task 4: Launchctl Runner and Installed Lifecycle Routing

**Files:**
- Modify: `crates/voco-cli/src/commands/daemon.rs`
- Modify: `crates/voco-cli/src/commands/daemon/launch_agent.rs`
- Test: `crates/voco-cli/tests/smoke.rs`

- [ ] **Step 1: Add failing launchctl classification tests**

Append these tests to `crates/voco-cli/src/commands/daemon/launch_agent.rs`:

```rust
    #[test]
    fn bootout_service_not_found_is_already_stopped() {
        let output = LaunchctlOutput {
            status_code: Some(3),
            stdout: String::new(),
            stderr: "Boot-out failed: 3: No such process".to_string(),
        };

        assert!(bootout_means_already_stopped(&output));
    }

    #[test]
    fn bootstrap_service_already_loaded_is_non_fatal() {
        let output = LaunchctlOutput {
            status_code: Some(5),
            stdout: String::new(),
            stderr: "Bootstrap failed: 5: Input/output error: service already loaded".to_string(),
        };

        assert!(bootstrap_means_already_loaded(&output));
    }

    #[test]
    fn unknown_launchctl_failure_is_descriptive() {
        let output = LaunchctlOutput {
            status_code: Some(78),
            stdout: "stdout detail".to_string(),
            stderr: "bad plist".to_string(),
        };

        let err = launchctl_error("bootstrap", "gui/501", &output).to_string();
        assert!(err.contains("launchctl bootstrap gui/501 failed with exit 78"));
        assert!(err.contains("bad plist"));
    }
```

- [ ] **Step 2: Run classification tests and confirm failure**

Run:

```bash
cargo test -p voco-cli bootout_service_not_found_is_already_stopped
cargo test -p voco-cli bootstrap_service_already_loaded_is_non_fatal
cargo test -p voco-cli unknown_launchctl_failure_is_descriptive
```

Expected: compile fails because `LaunchctlOutput`, `bootout_means_already_stopped`, `bootstrap_means_already_loaded`, and `launchctl_error` do not exist.

- [ ] **Step 3: Implement launchctl output classification**

In `crates/voco-cli/src/commands/daemon/launch_agent.rs`, add:

```rust
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LaunchctlOutput {
    pub status_code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
}

pub fn bootout_means_already_stopped(output: &LaunchctlOutput) -> bool {
    let text = format!("{}\n{}", output.stdout, output.stderr).to_lowercase();
    text.contains("no such process")
        || text.contains("service not found")
        || text.contains("could not find service")
}

pub fn bootstrap_means_already_loaded(output: &LaunchctlOutput) -> bool {
    let text = format!("{}\n{}", output.stdout, output.stderr).to_lowercase();
    text.contains("service already loaded")
        || text.contains("already bootstrapped")
        || text.contains("bootstrap failed: 5")
}

pub fn launchctl_error(action: &str, target: &str, output: &LaunchctlOutput) -> anyhow::Error {
    anyhow::anyhow!(
        "launchctl {action} {target} failed with exit {}: {}{}{}",
        output
            .status_code
            .map(|code| code.to_string())
            .unwrap_or_else(|| "signal".to_string()),
        output.stderr.trim(),
        if output.stdout.trim().is_empty() { "" } else { "\nstdout: " },
        output.stdout.trim()
    )
}
```

- [ ] **Step 4: Implement real launchctl commands**

In `crates/voco-cli/src/commands/daemon/launch_agent.rs`, add:

```rust
impl LaunchAgent {
    pub fn domain(&self) -> Result<String> {
        let output = std::process::Command::new("id").arg("-u").output()?;
        if !output.status.success() {
            return Err(anyhow::anyhow!(
                "id -u failed: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }
        let uid = String::from_utf8(output.stdout)?.trim().to_string();
        Ok(format!("gui/{uid}"))
    }

    pub fn service_target(&self) -> Result<String> {
        Ok(format!("{}/{}", self.domain()?, self.label))
    }

    pub fn bootstrap(&self) -> Result<()> {
        let domain = self.domain()?;
        let plist = self.paths.plist_path.display().to_string();
        let output = run_launchctl(["bootstrap", domain.as_str(), plist.as_str()])?;
        if output.status_code.is_none() {
            return Ok(());
        }
        if bootstrap_means_already_loaded(&output) {
            return Ok(());
        }
        Err(launchctl_error("bootstrap", &domain, &output))
    }

    pub fn kickstart(&self) -> Result<()> {
        let target = self.service_target()?;
        let output = run_launchctl(["kickstart", "-k", target.as_str()])?;
        if output.status_code.is_none() {
            return Ok(());
        }
        Err(launchctl_error("kickstart", &target, &output))
    }

    pub fn bootout(&self) -> Result<()> {
        let target = self.service_target()?;
        let output = run_launchctl(["bootout", target.as_str()])?;
        if output.status_code.is_none() || bootout_means_already_stopped(&output) {
            return Ok(());
        }
        Err(launchctl_error("bootout", &target, &output))
    }

    pub fn start(&self) -> Result<()> {
        self.bootstrap()?;
        self.kickstart()
    }

    pub fn stop(&self) -> Result<()> {
        self.bootout()
    }

    pub fn restart(&self) -> Result<()> {
        self.bootout()?;
        self.bootstrap()?;
        self.kickstart()
    }
}

fn run_launchctl<I, S>(args: I) -> Result<LaunchctlOutput>
where
    I: IntoIterator<Item = S>,
    S: AsRef<std::ffi::OsStr>,
{
    let output = std::process::Command::new("launchctl").args(args).output()?;
    Ok(LaunchctlOutput {
        status_code: if output.status.success() {
            None
        } else {
            output.status.code()
        },
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
    })
}
```

- [ ] **Step 5: Route installed start/stop/restart through LaunchAgent**

In `crates/voco-cli/src/commands/daemon.rs`, replace the `Restart` match arm:

```rust
DaemonAction::Restart => restart(),
```

Add this helper:

```rust
fn discover_launch_agent() -> Result<launch_agent::LaunchAgent> {
    let daemon_path = locate_daemon_binary()?;
    launch_agent::LaunchAgent::discover(daemon_path)
}
```

Update `start()` so installed services use launchctl and uninstalled services use direct spawn:

```rust
fn start() -> Result<()> {
    if is_daemon_running() {
        println!("✓ daemon already running");
        return Ok(());
    }

    let agent = discover_launch_agent()?;
    if agent.is_installed() {
        agent.start()?;
        wait_for_socket(Duration::from_secs(3))?;
        println!("✓ daemon started via launchctl");
        println!("  service: {}", agent.service_target()?);
        return Ok(());
    }

    start_direct_spawn()
}
```

Rename the existing `start()` body to `start_direct_spawn()` and keep its current output.

Replace `stop()` with:

```rust
fn stop() -> Result<()> {
    let agent = discover_launch_agent()?;
    if agent.is_installed() {
        agent.stop()?;
        wait_for_socket_to_disappear(Duration::from_secs(3))?;
        println!("✓ daemon stopped");
        return Ok(());
    }

    stop_via_ipc()
}
```

Rename the existing `stop()` body to `stop_via_ipc()`.

Add:

```rust
fn restart() -> Result<()> {
    let agent = discover_launch_agent()?;
    if agent.is_installed() {
        agent.restart()?;
        wait_for_socket(Duration::from_secs(3))?;
        println!("✓ daemon restarted via launchctl");
        println!("  service: {}", agent.service_target()?);
        return Ok(());
    }

    let _ = stop_via_ipc();
    std::thread::sleep(Duration::from_millis(200));
    start_direct_spawn()
}

fn wait_for_socket(timeout: Duration) -> Result<()> {
    let deadline = Instant::now() + timeout;
    let sock = default_socket_path();
    while Instant::now() < deadline {
        if UnixStream::connect(&sock).is_ok() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    Err(anyhow!("daemon socket {} not ready after {:?}", sock.display(), timeout))
}

fn wait_for_socket_to_disappear(timeout: Duration) -> Result<()> {
    let deadline = Instant::now() + timeout;
    let sock = default_socket_path();
    while Instant::now() < deadline {
        if UnixStream::connect(&sock).is_err() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    bail!("daemon socket {} still reachable after {:?}", sock.display(), timeout)
}
```

- [ ] **Step 6: Keep install/uninstall behavior narrow**

Update `uninstall()` in `crates/voco-cli/src/commands/daemon.rs` so it unloads if installed before deleting the plist:

```rust
fn uninstall() -> Result<()> {
    let agent = discover_launch_agent()?;
    if agent.is_installed() {
        agent.stop()?;
        let _ = wait_for_socket_to_disappear(Duration::from_secs(3));
    }
    if agent.uninstall_plist()? {
        println!("✓ removed LaunchAgent: {}", agent.paths.plist_path.display());
    } else {
        println!("✓ LaunchAgent already uninstalled");
    }
    Ok(())
}
```

- [ ] **Step 7: Keep smoke tests away from the real user LaunchAgents directory**

In `crates/voco-cli/tests/smoke.rs`, replace `voco_with_home` with:

```rust
fn voco_with_home(tmp: &TempDir) -> Command {
    let mut c = Command::cargo_bin("voco").unwrap();
    let home = tmp.path().join("home");
    std::fs::create_dir_all(&home).unwrap();
    c.env("VOCO_HOME", tmp.path());
    c.env("HOME", home);
    c
}
```

This keeps `LaunchAgent::discover()` from reading or writing the developer's real `~/Library/LaunchAgents` during tests.

- [ ] **Step 8: Run focused tests and existing direct-spawn smoke**

Run:

```bash
cargo test -p voco-cli bootout_service_not_found_is_already_stopped
cargo test -p voco-cli bootstrap_service_already_loaded_is_non_fatal
cargo test -p voco-cli unknown_launchctl_failure_is_descriptive
cargo test -p voco-cli --test smoke
```

Expected: launchctl classification tests pass; existing smoke tests still pass using the uninstalled direct-spawn fallback.

- [ ] **Step 9: Commit**

Run:

```bash
git add crates/voco-cli/src/commands/daemon.rs crates/voco-cli/src/commands/daemon/launch_agent.rs crates/voco-cli/tests/smoke.rs
git commit -m "feat(cli): manage installed daemon with launchctl"
```

---

## Task 5: Documentation and Manual Smoke Checklist

**Files:**
- Modify: `README.md`
- Modify: `packaging/README.md`
- Modify: `docs/superpowers/plans/2026-05-03-voco-phase-6-launchagent.md`

- [ ] **Step 1: Update README quickstart**

Replace the README `Status` and `Build` sections with this content:

````markdown
## Status

Phase 6-A development: Phase 5 hotkey recording, text injection, and hidden Swift HUD helper are implemented. Phase 6-A adds a user-level LaunchAgent so the daemon can be installed under `~/Library/LaunchAgents` and managed by `launchctl`.

## Build

```sh
cargo build --workspace
cd hud && swift build && cd ..
```

## Development Daemon

Without installing the LaunchAgent, `voco daemon start` keeps the direct-spawn development workflow:

```bash
target/debug/voco daemon start
target/debug/voco status
target/debug/voco daemon stop
```

## LaunchAgent Install

Install the user LaunchAgent without `sudo`:

```bash
target/debug/voco daemon install
target/debug/voco daemon start
target/debug/voco status
```

The plist is written to:

```text
~/Library/LaunchAgents/com.voco.daemon.plist
```

Stop and remove the LaunchAgent:

```bash
target/debug/voco daemon stop
target/debug/voco daemon uninstall
```

`Voco.app` bundling, signing, notarization, and installer packaging remain future work.
````

Keep the existing Phase 5 HUD development section after this new quickstart.

- [ ] **Step 2: Update packaging README**

Replace `packaging/README.md` with:

````markdown
# packaging/

LaunchAgent template and future bundle assets.

## com.voco.daemon.plist.tmpl

`voco daemon install` renders this template to:

```text
~/Library/LaunchAgents/com.voco.daemon.plist
```

Template variables:

```text
{{VOCO_DAEMON_PATH}} absolute path to voco-daemon
{{HOME}}             user home directory
{{WORKING_DIR}}      daemon working directory
```

Phase 6-A uses a user-level LaunchAgent and does not require `sudo`.

`Voco.app`, signing, notarization, and installer packaging are deferred.
````

- [ ] **Step 3: Run documentation grep checks**

Run:

```bash
rg -n "Phase 6-A|LaunchAgent|voco daemon install|voco daemon uninstall|sudo|Voco.app" README.md packaging/README.md docs/superpowers/plans/2026-05-03-voco-phase-6-launchagent.md
```

Expected: output includes the new install/uninstall quickstart, says no `sudo`, and says `Voco.app` is future work.

- [ ] **Step 4: Run formatting and focused tests**

Run:

```bash
cargo fmt --all --check
cargo test -p voco-cli parses_daemon_install_uninstall_actions
cargo test -p voco-cli --test smoke
```

Expected: all commands pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add README.md packaging/README.md docs/superpowers/plans/2026-05-03-voco-phase-6-launchagent.md
git commit -m "docs: document Phase 6 LaunchAgent workflow"
```

---

## Task 6: Final Verification and Manual LaunchAgent Smoke

**Files:**
- Modify: `docs/superpowers/plans/2026-05-03-voco-phase-6-launchagent.md`

- [ ] **Step 1: Run full automated gates**

Run:

```bash
cd hud && swift test && swift build && cd ..
cargo fmt --all --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo build --workspace --release
git diff --check
```

Expected:

- Swift HUD tests pass with 0 failures.
- Swift HUD build exits 0.
- Rust formatting check exits 0.
- Rust workspace tests pass; live network/microphone tests stay ignored unless explicitly enabled.
- Clippy exits 0 with `-D warnings`.
- Release build exits 0.
- `git diff --check` exits 0.

- [ ] **Step 2: Run manual LaunchAgent smoke**

Run on the development Mac:

```bash
target/debug/voco daemon uninstall || true
cargo build --workspace
target/debug/voco daemon install
test -f ~/Library/LaunchAgents/com.voco.daemon.plist
target/debug/voco daemon start
target/debug/voco status
launchctl print gui/$(id -u)/com.voco.daemon
pgrep -x voco-daemon
pkill -9 voco-daemon
sleep 12
target/debug/voco status
pgrep -x voco-daemon
target/debug/voco daemon stop
target/debug/voco daemon uninstall
test ! -f ~/Library/LaunchAgents/com.voco.daemon.plist
```

Expected:

- install creates `~/Library/LaunchAgents/com.voco.daemon.plist`;
- start makes `voco status` report daemon running and state idle;
- `launchctl print gui/$(id -u)/com.voco.daemon` exits 0;
- after `pkill -9 voco-daemon`, `KeepAlive=true` relaunches the daemon after launchd's default throttle interval and `voco status` works again;
- stop unloads the service;
- uninstall removes the plist;
- config and logs remain in place.

- [ ] **Step 3: Record verification results in this plan**

Append a note under this task with the exact command outcomes from Step 1 and Step 2. Use this format, replacing each description with the real observed command result before committing:

```markdown
Task 6 note (2026-05-03):
- `cd hud && swift test && swift build && cd ..` passed: Swift HUD test count, failure count, and build status observed in terminal.
- `cargo fmt --all --check` passed.
- `cargo test --workspace` passed: Rust workspace test summary observed in terminal.
- `cargo clippy --workspace --all-targets -- -D warnings` passed.
- `cargo build --workspace --release` passed.
- `git diff --check` passed.
- Manual LaunchAgent smoke passed or was blocked by a named environment condition. Details include the exact failing command or the successful smoke summary.
```

Task 6 note (2026-05-03):
- `cd hud && swift test && swift build && cd ..` passed: Swift HUD executed 7 tests with 0 failures, then `swift build` completed successfully.
- `cargo fmt --all --check` passed.
- `cargo test --workspace` passed: Rust workspace tests passed; live Doubao network and microphone tests remained ignored as designed.
- `cargo clippy --workspace --all-targets -- -D warnings` passed.
- `cargo build --workspace --release` passed.
- `git diff --check` passed.
- Manual LaunchAgent smoke passed after adjusting the crash-recovery wait to 12 seconds to account for launchd's default `minimum runtime = 10` throttle. The smoke created `~/Library/LaunchAgents/com.voco.daemon.plist`, started `gui/501/com.voco.daemon`, confirmed `voco status` idle, confirmed `launchctl print` and `pgrep -x voco-daemon`, killed `voco-daemon`, confirmed launchd relaunched it with a new pid, then stopped and uninstalled the service. Cleanup was verified: plist absent, no `voco-daemon` process, and `launchctl print gui/501/com.voco.daemon` reported the service missing.

- [ ] **Step 4: Commit verification update**

Run:

```bash
git add docs/superpowers/plans/2026-05-03-voco-phase-6-launchagent.md
git commit -m "docs: mark Phase 6 LaunchAgent verification"
```

- [ ] **Step 5: Finish branch**

Use `superpowers:finishing-a-development-branch` after all automated gates pass and the manual LaunchAgent smoke is either passed or explicitly recorded as blocked by an environment issue.
