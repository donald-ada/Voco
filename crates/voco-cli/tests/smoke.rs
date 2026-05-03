//! End-to-end verification: voco daemon start && voco status returns idle.
//!
//! Each test sets `VOCO_HOME` to a tempdir so the cli + spawned daemon
//! share an isolated socket/log/config root. `~/Library` is never touched.

use assert_cmd::prelude::*;
use predicates::prelude::*;
use std::process::Command;
use std::time::Duration;
use tempfile::TempDir;

fn voco_with_home(tmp: &TempDir) -> Command {
    let mut c = Command::cargo_bin("voco").unwrap();
    let home = tmp.path().join("home");
    std::fs::create_dir_all(&home).unwrap();
    c.env("VOCO_HOME", tmp.path());
    c.env("HOME", home);
    c
}

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

#[test]
#[serial_test::serial]
fn daemon_start_status_stop_cycle() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;

    voco_with_home(&tmp)
        .args(["daemon", "start"])
        .assert()
        .success()
        .stdout(predicate::str::contains("daemon started"));

    voco_with_home(&tmp)
        .arg("status")
        .assert()
        .success()
        .stdout(predicate::str::contains("daemon running"))
        .stdout(predicate::str::contains("state:           idle"));

    voco_with_home(&tmp)
        .args(["daemon", "stop"])
        .assert()
        .success()
        .stdout(predicate::str::contains("daemon stopped"));

    voco_with_home(&tmp)
        .arg("status")
        .assert()
        .failure()
        .stdout(predicate::str::contains("daemon not running"));

    Ok(())
}

#[test]
#[serial_test::serial]
fn double_start_is_idempotent() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;

    voco_with_home(&tmp)
        .args(["daemon", "start"])
        .assert()
        .success();

    voco_with_home(&tmp)
        .args(["daemon", "start"])
        .assert()
        .success()
        .stdout(predicate::str::contains("already running"));

    voco_with_home(&tmp)
        .args(["daemon", "stop"])
        .assert()
        .success();
    Ok(())
}

#[test]
#[serial_test::serial]
fn stop_without_start_is_idempotent() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    // Pre-flight: ensure no daemon is bound to *this* tempdir's socket.
    let _ = voco_with_home(&tmp).args(["daemon", "stop"]).output();
    std::thread::sleep(Duration::from_millis(200));

    voco_with_home(&tmp)
        .args(["daemon", "stop"])
        .assert()
        .success()
        .stdout(predicate::str::contains("already stopped"));
    Ok(())
}

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
