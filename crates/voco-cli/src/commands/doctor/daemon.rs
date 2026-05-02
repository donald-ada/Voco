//! Daemon-side checks: socket reachable + hotkey installed.

use super::CheckResult;
use std::os::unix::net::UnixStream;
use voco_daemon::default_socket_path;

pub fn socket_reachable() -> CheckResult {
    let p = default_socket_path();
    match UnixStream::connect(&p) {
        Ok(_) => CheckResult::Ok(p.display().to_string()),
        Err(_) => CheckResult::Warn {
            headline: format!("daemon not running ({})", p.display()),
            hint: "voco daemon start".into(),
        },
    }
}

pub fn hotkey_installed() -> CheckResult {
    CheckResult::Skip("CGEventTap wiring lands in Phase 4".into())
}
