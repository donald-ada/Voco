//! End-to-end verification: voco daemon start && voco status returns idle.
//!
//! These tests touch the real ~/Library/Application Support/voco/voco.sock
//! because Phase 1 hasn't introduced a path-override env var yet (that lands
//! in Phase 2). serial_test prevents them from racing each other.

use assert_cmd::prelude::*;
use predicates::prelude::*;
use std::process::Command;
use std::time::Duration;

fn voco() -> Command {
    Command::cargo_bin("voco").unwrap()
}

#[test]
#[serial_test::serial]
fn daemon_start_status_stop_cycle() -> anyhow::Result<()> {
    // Make sure voco-daemon is built so the locate_daemon_binary lookup hits.
    let _ = Command::cargo_bin("voco-daemon")?;

    voco()
        .args(["daemon", "start"])
        .assert()
        .success()
        .stdout(predicate::str::contains("daemon started"));

    voco()
        .arg("status")
        .assert()
        .success()
        .stdout(predicate::str::contains("daemon running"))
        .stdout(predicate::str::contains("state:           idle"));

    voco()
        .args(["daemon", "stop"])
        .assert()
        .success()
        .stdout(predicate::str::contains("daemon stopped"));

    voco()
        .arg("status")
        .assert()
        .failure()
        .stdout(predicate::str::contains("daemon not running"));

    Ok(())
}

#[test]
#[serial_test::serial]
fn double_start_is_idempotent() -> anyhow::Result<()> {
    let _ = Command::cargo_bin("voco-daemon")?;

    voco().args(["daemon", "start"]).assert().success();

    voco()
        .args(["daemon", "start"])
        .assert()
        .success()
        .stdout(predicate::str::contains("already running"));

    voco().args(["daemon", "stop"]).assert().success();
    Ok(())
}

#[test]
#[serial_test::serial]
fn stop_without_start_is_idempotent() -> anyhow::Result<()> {
    let _ = voco().args(["daemon", "stop"]).output();
    std::thread::sleep(Duration::from_millis(200));

    voco()
        .args(["daemon", "stop"])
        .assert()
        .success()
        .stdout(predicate::str::contains("already stopped"));
    Ok(())
}
