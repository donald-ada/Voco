//! Best-effort daemon reload after a config write. Failures here never fail
//! the parent command — they're surfaced as a hint and the user can run
//! `voco daemon restart` if they want.

use voco_daemon::default_socket_path;
use voco_ipc::client::IpcClient;
use voco_ipc::protocol::{Request, Response};

pub enum ReloadOutcome {
    DaemonNotRunning,
    Reloaded,
    ReloadFailed(String),
}

pub fn notify_daemon_reload() -> ReloadOutcome {
    let mut client = match IpcClient::connect(default_socket_path()) {
        Err(_) => return ReloadOutcome::DaemonNotRunning,
        Ok(c) => c,
    };
    match client.call(&Request::ReloadConfig) {
        Ok(Response::Ok) => ReloadOutcome::Reloaded,
        Ok(Response::Error { message }) => ReloadOutcome::ReloadFailed(message),
        Ok(other) => ReloadOutcome::ReloadFailed(format!("unexpected response: {:?}", other)),
        Err(e) => ReloadOutcome::ReloadFailed(e.to_string()),
    }
}

pub fn print_outcome(o: ReloadOutcome) {
    match o {
        ReloadOutcome::DaemonNotRunning => {
            println!("  (daemon not running; change takes effect on next start)");
        }
        ReloadOutcome::Reloaded => {
            println!("✓ Daemon reloaded.");
        }
        ReloadOutcome::ReloadFailed(msg) => {
            // Phase 1 daemon returns a "not yet implemented" message — treat as
            // a hint, not a failure. Phase 2 Task 6 makes this real.
            println!("  (daemon could not reload: {msg})");
            println!("  run `voco daemon restart` to apply.");
        }
    }
}
