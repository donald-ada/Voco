use assert_cmd::prelude::*;
use predicates::prelude::*;
use std::process::Command;
use std::time::{Duration, Instant};
use tempfile::TempDir;

fn voco(tmp: &TempDir) -> Command {
    let mut c = Command::cargo_bin("voco").unwrap();
    c.env("VOCO_HOME", tmp.path());
    c.env("VOCO_FORCE_MOCK_BACKEND", "1");
    c
}

fn voco_with_mock_delay(tmp: &TempDir, delay_ms: u64) -> Command {
    let mut c = voco(tmp);
    c.env("VOCO_MOCK_RECORDING_DELAY_MS", delay_ms.to_string());
    c
}

fn wait_for_socket(tmp: &TempDir, deadline: Duration) {
    let p = tmp.path().join("data").join("voco.sock");
    let start = Instant::now();
    while start.elapsed() < deadline {
        if std::os::unix::net::UnixStream::connect(&p).is_ok() {
            return;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    panic!("socket {} never appeared", p.display());
}

#[test]
#[serial_test::serial]
fn internal_record_with_mock_backend_returns_canned_final() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;

    voco(&tmp).args(["daemon", "start"]).assert().success();
    wait_for_socket(&tmp, Duration::from_secs(2));

    voco(&tmp)
        .args(["_internal_record", "--duration", "1"])
        .assert()
        .success()
        .stdout(predicate::str::contains("recording for 1s"))
        .stdout(predicate::str::contains("final: \"mock final\""))
        .stdout(predicate::str::contains("logid: mock-logid"));

    voco(&tmp).args(["daemon", "stop"]).assert().success();
    Ok(())
}

#[test]
#[serial_test::serial]
fn internal_record_partials_flag_emits_partials() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;

    voco(&tmp).args(["daemon", "start"]).assert().success();
    wait_for_socket(&tmp, Duration::from_secs(2));

    voco(&tmp)
        .args(["_internal_record", "--duration", "1", "--show-partials"])
        .assert()
        .success()
        .stdout(predicate::str::contains("partial[1]"))
        .stdout(predicate::str::contains("mock"))
        .stdout(predicate::str::contains("final: \"mock final\""));

    voco(&tmp).args(["daemon", "stop"]).assert().success();
    Ok(())
}

#[test]
#[serial_test::serial]
fn internal_record_returns_busy_when_concurrent() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;

    voco_with_mock_delay(&tmp, 200)
        .args(["daemon", "start"])
        .assert()
        .success();
    wait_for_socket(&tmp, Duration::from_secs(2));

    let mut first = voco(&tmp)
        .args(["_internal_record", "--duration", "1"])
        .spawn()?;
    std::thread::sleep(Duration::from_millis(50));

    voco(&tmp)
        .args(["_internal_record", "--duration", "1"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("busy: state=Recording"));

    let first_status = first.wait()?;
    assert!(first_status.success(), "first exited with {first_status}");

    voco(&tmp).args(["daemon", "stop"]).assert().success();
    Ok(())
}
