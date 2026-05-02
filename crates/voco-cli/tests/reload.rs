//! End-to-end: editing the config file then `voco config set` (or directly
//! talking to the daemon's ReloadConfig) updates the daemon's effective
//! config. Verified via `Request::DumpConfig`.

use assert_cmd::prelude::*;
use predicates::prelude::*;
use std::process::Command;
use std::time::{Duration, Instant};
use tempfile::TempDir;

fn voco(tmp: &TempDir) -> Command {
    let mut c = Command::cargo_bin("voco").unwrap();
    c.env("VOCO_HOME", tmp.path());
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

/// Dump the daemon config via a one-shot custom client. Returns the raw
/// JSON string. Used to assert reloads took effect.
fn dump_config(tmp: &TempDir) -> String {
    use std::io::{Read, Write};
    use std::os::unix::net::UnixStream;
    let sock = tmp.path().join("data").join("voco.sock");
    let env = serde_json::json!({
        "protocol_version": 2,
        "kind": "request",
        "id": uuid::Uuid::new_v4(),
        "payload": { "method": "dump_config" }
    });
    let body = serde_json::to_vec(&env).unwrap();
    let mut s = UnixStream::connect(&sock).unwrap();
    s.write_all(&(body.len() as u32).to_be_bytes()).unwrap();
    s.write_all(&body).unwrap();
    let mut len_buf = [0u8; 4];
    s.read_exact(&mut len_buf).unwrap();
    let len = u32::from_be_bytes(len_buf) as usize;
    let mut buf = vec![0u8; len];
    s.read_exact(&mut buf).unwrap();
    String::from_utf8(buf).unwrap()
}

#[test]
#[serial_test::serial]
fn reload_picks_up_new_output_mode() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    // Seed valid creds so reload validation passes.
    for (k, v) in [
        ("doubao.app_id", "APP-1"),
        ("doubao.access_token", "T"),
        ("doubao.endpoint", "wss://x"),
        ("doubao.model_id", "bigmodel"),
    ] {
        voco(&tmp).args(["config", "set", k, v]).assert().success();
    }

    voco(&tmp).args(["daemon", "start"]).assert().success();
    wait_for_socket(&tmp, Duration::from_secs(2));

    // Pre-reload dump shows default output mode.
    let pre = dump_config(&tmp);
    assert!(pre.contains("inject_then_clipboard"), "pre={pre}");

    // Mutate the file via `set`; the cli will best-effort notify daemon.
    voco(&tmp)
        .args(["config", "set", "output.mode", "clipboard_only"])
        .assert()
        .success();

    let post = dump_config(&tmp);
    assert!(post.contains("clipboard_only"), "post={post}");
    assert!(!post.contains("inject_then_clipboard"));

    voco(&tmp).args(["daemon", "stop"]).assert().success();
    Ok(())
}

#[test]
#[serial_test::serial]
fn reload_warns_on_backend_swap() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    for (k, v) in [
        ("doubao.app_id", "APP-1"),
        ("doubao.access_token", "T"),
        ("doubao.endpoint", "wss://x"),
        ("doubao.model_id", "bigmodel"),
    ] {
        voco(&tmp).args(["config", "set", k, v]).assert().success();
    }
    voco(&tmp).args(["daemon", "start"]).assert().success();
    wait_for_socket(&tmp, Duration::from_secs(2));

    // Set a sherpa stub so the new config validates (sherpa requires
    // model_dir.is_dir() — point it at the tempdir itself).
    voco(&tmp)
        .args([
            "config",
            "set",
            "sherpa.model_dir",
            tmp.path().to_str().unwrap(),
        ])
        .assert()
        .success();
    voco(&tmp)
        .args(["config", "set", "sherpa.num_threads", "1"])
        .assert()
        .success();
    voco(&tmp)
        .args(["config", "set", "sherpa.provider", "cpu"])
        .assert()
        .success();

    voco(&tmp)
        .args(["config", "set", "backend", "sherpa"])
        .assert()
        .success()
        .stdout(predicate::str::contains(
            "Daemon reloaded, but some changes need a restart",
        ))
        .stdout(predicate::str::contains("backend changed"));

    voco(&tmp).args(["daemon", "stop"]).assert().success();
    Ok(())
}

#[test]
#[serial_test::serial]
fn reload_redacts_token_in_dump() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;
    for (k, v) in [
        ("doubao.app_id", "APP-1"),
        ("doubao.access_token", "TOTALLY-SECRET-TOKEN"),
        ("doubao.endpoint", "wss://x"),
        ("doubao.model_id", "bigmodel"),
    ] {
        voco(&tmp).args(["config", "set", k, v]).assert().success();
    }
    voco(&tmp).args(["daemon", "start"]).assert().success();
    wait_for_socket(&tmp, Duration::from_secs(2));

    let dump = dump_config(&tmp);
    assert!(
        !dump.contains("TOTALLY-SECRET-TOKEN"),
        "dump leaked token: {dump}"
    );
    assert!(dump.contains("********"));

    voco(&tmp).args(["daemon", "stop"]).assert().success();
    Ok(())
}
