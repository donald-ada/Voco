use anyhow::Result;
use std::ffi::OsStr;
use std::path::{Path, PathBuf};

pub const LABEL: &str = "com.voco.daemon";

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LaunchAgentPaths {
    pub plist_path: PathBuf,
    pub daemon_path: PathBuf,
    pub working_dir: PathBuf,
    pub home: PathBuf,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InstallOutcome {
    Created,
    Updated,
    Unchanged,
}

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
    text.contains("service already loaded") || text.contains("already bootstrapped")
}

pub fn launchctl_error(action: &str, target: &str, output: &LaunchctlOutput) -> anyhow::Error {
    anyhow::anyhow!(
        "launchctl {action} {target} failed with exit {}: {}{}{}",
        output
            .status_code
            .map(|code| code.to_string())
            .unwrap_or_else(|| "signal".to_string()),
        output.stderr.trim(),
        if output.stdout.trim().is_empty() {
            ""
        } else {
            "\nstdout: "
        },
        output.stdout.trim()
    )
}

fn run_launchctl<I, S>(args: I) -> Result<LaunchctlOutput>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let output = std::process::Command::new("launchctl")
        .args(args)
        .output()?;
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

pub fn render_plist(paths: &LaunchAgentPaths) -> String {
    render_plist_from_template(plist_template(), paths)
}

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

fn render_plist_from_template(template: &str, paths: &LaunchAgentPaths) -> String {
    template
        .replace(
            "{{VOCO_DAEMON_PATH}}",
            &xml_escape(&paths.daemon_path.display().to_string()),
        )
        .replace("{{HOME}}", &xml_escape(&paths.home.display().to_string()))
        .replace(
            "{{WORKING_DIR}}",
            &xml_escape(&paths.working_dir.display().to_string()),
        )
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
        let rendered =
            "<plist><dict><key>Label</key><string>com.voco.daemon</string></dict></plist>";

        assert_eq!(
            install_plist(&paths.plist_path, rendered)?,
            InstallOutcome::Created
        );
        assert_eq!(std::fs::read_to_string(&paths.plist_path)?, rendered);
        Ok(())
    }

    #[test]
    fn install_plist_reports_unchanged_for_identical_content() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let paths = temp_paths(&tmp);
        let rendered = "<plist>same</plist>";

        assert_eq!(
            install_plist(&paths.plist_path, rendered)?,
            InstallOutcome::Created
        );
        assert_eq!(
            install_plist(&paths.plist_path, rendered)?,
            InstallOutcome::Unchanged
        );
        Ok(())
    }

    #[test]
    fn install_plist_reports_updated_for_different_content() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let paths = temp_paths(&tmp);

        assert_eq!(
            install_plist(&paths.plist_path, "<plist>old</plist>")?,
            InstallOutcome::Created
        );
        assert_eq!(
            install_plist(&paths.plist_path, "<plist>new</plist>")?,
            InstallOutcome::Updated
        );
        assert_eq!(
            std::fs::read_to_string(&paths.plist_path)?,
            "<plist>new</plist>"
        );
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
}
