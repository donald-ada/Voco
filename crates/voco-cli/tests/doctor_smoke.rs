//! End-to-end: `voco doctor` runs all five groups and exits with code
//! 0 unless something Fail-grade is detected.

use assert_cmd::prelude::*;
use predicates::prelude::*;
use std::process::Command;
use tempfile::TempDir;

fn voco(tmp: &TempDir) -> Command {
    let mut c = Command::cargo_bin("voco").unwrap();
    c.env("VOCO_HOME", tmp.path());
    // Force the CI gate so TCC checks Skip cleanly even on dev macs.
    c.env("CI", "1");
    c
}

#[test]
fn doctor_runs_all_groups() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    let out = voco(&tmp).arg("doctor").output()?;
    let stdout = String::from_utf8_lossy(&out.stdout);

    for group in ["Permissions", "Config", "Daemon", "Microphone", "Backend"] {
        assert!(
            stdout.contains(group),
            "expected group `{group}` in output, got:\n{stdout}"
        );
    }
    assert!(stdout.contains("Summary:"));
    Ok(())
}

#[test]
fn doctor_skips_tcc_on_ci() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    voco(&tmp)
        .arg("doctor")
        .assert()
        .stdout(predicate::str::contains("Accessibility (CI=true)"))
        .stdout(predicate::str::contains("Input Monitoring").not());
    Ok(())
}

#[test]
fn doctor_skips_hotkey_install_check_on_ci() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    voco(&tmp)
        .arg("doctor")
        .assert()
        .stdout(predicate::str::contains("Hotkey installed (CI=true)"))
        .stdout(predicate::str::contains("CGEventTap wiring lands in Phase 4").not());
    Ok(())
}

#[test]
fn doctor_fails_when_config_unparseable() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    std::fs::write(tmp.path().join("config.toml"), "not toml @@@")?;
    voco(&tmp)
        .arg("doctor")
        .assert()
        .failure()
        .stdout(predicate::str::contains("unparseable"));
    Ok(())
}

#[test]
fn doctor_warns_when_daemon_not_running() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    voco(&tmp)
        .arg("doctor")
        .assert()
        .stdout(predicate::str::contains("daemon not running"));
    Ok(())
}

#[test]
fn doctor_reports_missing_doubao_creds_as_fail() -> anyhow::Result<()> {
    // Default config has backend=doubao but no creds — this should Fail.
    let tmp = tempfile::tempdir()?;
    voco(&tmp)
        .arg("doctor")
        .assert()
        .failure()
        .stdout(predicate::str::contains("[doubao] section missing"));
    Ok(())
}

#[test]
fn doctor_accepts_new_console_api_key_creds() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    std::fs::write(
        tmp.path().join("config.toml"),
        r#"
backend = "doubao"
log_level = "info"
recording_max_duration_secs = 60

[hotkey]
keycode = 54
modifiers = 0
display_name = "Right Command"

[output]
mode = "inject_then_clipboard"
trim_trailing_punct = false
auto_capitalize = false

[hud]
style = "capsule"

[doubao]
app_id = ""
access_token = ""
api_key = "NEW-CONSOLE-KEY"
endpoint = "wss://example.invalid/asr"
model_id = "bigmodel"
resource_id = "volc.bigasr.sauc.duration"
"#,
    )?;

    voco(&tmp)
        .arg("doctor")
        .assert()
        .success()
        .stdout(predicate::str::contains("Doubao credentials"))
        .stdout(predicate::str::contains("auth=api_key"))
        .stdout(predicate::str::contains("NEW-CONSOLE-KEY").not());
    Ok(())
}
