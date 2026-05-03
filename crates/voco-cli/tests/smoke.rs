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
