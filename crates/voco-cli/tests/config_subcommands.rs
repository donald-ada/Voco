//! Integration tests for `voco config show / set / validate / reset / edit`.
//! Each test gets its own VOCO_HOME tempdir so they don't race.

use assert_cmd::prelude::*;
use predicates::prelude::*;
use std::fs;
use std::process::Command;
use tempfile::TempDir;

fn voco(tmp: &TempDir) -> Command {
    let mut c = Command::cargo_bin("voco").unwrap();
    c.env("VOCO_HOME", tmp.path());
    c
}

#[test]
fn show_masks_access_token() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    // Seed a config file with a token.
    let cfg_path = tmp.path().join("config.toml");
    fs::write(
        &cfg_path,
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
app_id = "APP-123"
access_token = "MY-SUPER-SECRET-TOKEN"
endpoint = "wss://x/api"
model_id = "bigmodel"
"#,
    )?;

    voco(&tmp)
        .args(["config", "show"])
        .assert()
        .success()
        .stdout(predicate::str::contains("APP-123"))
        .stdout(predicate::str::contains("********"))
        .stdout(predicate::str::contains("MY-SUPER-SECRET-TOKEN").not());

    Ok(())
}

#[test]
fn show_unsafe_reveals_token() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    let cfg_path = tmp.path().join("config.toml");
    fs::write(
        &cfg_path,
        r#"backend = "doubao"
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
app_id = "APP-123"
access_token = "REVEALED-XYZ"
endpoint = "wss://x/api"
model_id = "bigmodel"
"#,
    )?;
    voco(&tmp)
        .args(["config", "show", "--unsafe-show-secrets"])
        .assert()
        .success()
        .stdout(predicate::str::contains("REVEALED-XYZ"));
    Ok(())
}

#[test]
fn set_writes_then_reads_back() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;

    voco(&tmp)
        .args(["config", "set", "output.mode", "clipboard_only"])
        .assert()
        .success()
        .stdout(predicate::str::contains("output.mode = clipboard_only"));

    voco(&tmp)
        .args(["config", "show"])
        .assert()
        .success()
        .stdout(predicate::str::contains("clipboard_only"));
    Ok(())
}

#[test]
fn set_token_message_is_masked() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    // Need backend creds for validate to pass. Set app_id first.
    voco(&tmp)
        .args(["config", "set", "doubao.app_id", "APP-1"])
        .assert()
        .success();
    voco(&tmp)
        .args(["config", "set", "doubao.access_token", "VERYSECRET"])
        .assert()
        .success()
        .stdout(predicate::str::contains("Saved (token masked)"))
        .stdout(predicate::str::contains("VERYSECRET").not());
    Ok(())
}

#[test]
fn set_unknown_key_fails() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    voco(&tmp)
        .args(["config", "set", "bogus.field", "x"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("unknown leaf key"));
    Ok(())
}

#[test]
fn set_invalid_value_does_not_corrupt_file() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    voco(&tmp)
        .args(["config", "set", "output.mode", "garbage"])
        .assert()
        .failure();
    // Subsequent show works (file is either default or untouched).
    voco(&tmp).args(["config", "show"]).assert().success();
    Ok(())
}

#[test]
fn validate_default_reports_missing_creds() -> anyhow::Result<()> {
    // Phase 1 contract: Config::default() picks backend=doubao but ships no
    // creds — validation must surface this so users know to fill it in.
    let tmp = tempfile::tempdir()?;
    voco(&tmp)
        .args(["config", "validate"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("backend=doubao requires"));
    Ok(())
}

#[test]
fn validate_passes_after_seeding_creds() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    for (k, v) in [
        ("doubao.app_id", "APP-1"),
        ("doubao.access_token", "TOKEN"),
        ("doubao.endpoint", "wss://x/api"),
        ("doubao.model_id", "bigmodel"),
    ] {
        voco(&tmp).args(["config", "set", k, v]).assert().success();
    }
    voco(&tmp)
        .args(["config", "validate"])
        .assert()
        .success()
        .stdout(predicate::str::contains("valid"));
    Ok(())
}

#[test]
fn validate_corrupted_fails() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    fs::write(
        tmp.path().join("config.toml"),
        "this is not toml at all <<<",
    )?;
    voco(&tmp)
        .args(["config", "validate"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("failed to load"));
    Ok(())
}

#[test]
fn reset_yes_writes_default() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    // Mutate first.
    voco(&tmp)
        .args(["config", "set", "output.mode", "clipboard_only"])
        .assert()
        .success();
    voco(&tmp)
        .args(["config", "reset", "--yes"])
        .assert()
        .success()
        .stdout(predicate::str::contains("reset to defaults"));
    voco(&tmp)
        .args(["config", "show"])
        .assert()
        .success()
        .stdout(predicate::str::contains("inject_then_clipboard"));
    Ok(())
}

#[test]
fn edit_with_noop_editor_succeeds() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    // `true` is the no-op POSIX command; it always exits 0.
    voco(&tmp)
        .env("EDITOR", "true")
        .args(["config", "edit"])
        .assert()
        .success();
    Ok(())
}
