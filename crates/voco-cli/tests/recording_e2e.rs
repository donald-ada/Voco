use assert_cmd::prelude::*;
use predicates::prelude::*;
use std::path::Path;
use std::process::Command;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tempfile::TempDir;

static DAEMON_BINARY_READY: OnceLock<()> = OnceLock::new();

fn voco(tmp: &TempDir) -> Command {
    ensure_daemon_binary();
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

fn ensure_daemon_binary() {
    DAEMON_BINARY_READY.get_or_init(|| {
        let cargo = std::env::var("CARGO").unwrap_or_else(|_| "cargo".into());
        let workspace = Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .and_then(Path::parent)
            .expect("voco-cli lives under crates/")
            .to_path_buf();
        let status = Command::new(cargo)
            .current_dir(workspace)
            .args(["build", "-p", "voco-daemon", "--bin", "voco-daemon"])
            .status()
            .expect("failed to run cargo build for voco-daemon");
        assert!(status.success(), "cargo build -p voco-daemon failed");
    });
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
fn mock_backend_full_session_returns_final() -> anyhow::Result<()> {
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
fn mock_backend_partials_arrive_in_order() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;

    voco(&tmp).args(["daemon", "start"]).assert().success();
    wait_for_socket(&tmp, Duration::from_secs(2));

    let output = voco(&tmp)
        .args(["_internal_record", "--duration", "1", "--show-partials"])
        .output()?;
    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    let first = stdout
        .find("partial[1] (stable=4): \"mock\"")
        .expect("missing first partial");
    let second = stdout
        .find("partial[2] (stable=10): \"mock final\"")
        .expect("missing second partial");
    let final_line = stdout
        .find("final: \"mock final\"")
        .expect("missing final line");
    assert!(first < second, "partials not ordered:\n{stdout}");
    assert!(
        second < final_line,
        "partials printed after final:\n{stdout}"
    );

    voco(&tmp).args(["daemon", "stop"]).assert().success();
    Ok(())
}

#[test]
#[serial_test::serial]
fn recording_busy_response_when_concurrent() -> anyhow::Result<()> {
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
