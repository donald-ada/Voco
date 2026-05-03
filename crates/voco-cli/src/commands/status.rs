//! `voco status` — connect to daemon, ask for status, render human-friendly.

use anyhow::Result;
use voco_daemon::default_socket_path;
use voco_ipc::client::IpcClient;
use voco_ipc::protocol::{Request, Response, StatusInfo};

pub fn run() -> Result<()> {
    let path = default_socket_path();
    let mut client = match IpcClient::connect(&path) {
        Ok(c) => c,
        Err(_) => {
            println!("✗ daemon not running (socket: {})", path.display());
            println!("  start it with: voco daemon start");
            std::process::exit(1);
        }
    };

    match client.call(&Request::Status)? {
        Response::Status(s) => render(&s),
        Response::Error { message } => {
            eprintln!("✗ daemon error: {}", message);
            std::process::exit(1);
        }
        other => {
            eprintln!("✗ unexpected response: {:?}", other);
            std::process::exit(1);
        }
    }
    Ok(())
}

fn render(s: &StatusInfo) {
    let h = s.uptime_secs / 3600;
    let m = (s.uptime_secs % 3600) / 60;
    println!("✓ daemon running (uptime {h}h {m}m)");
    println!("  state:           {}", s.state);
    println!("  backend:         {}", s.backend);
    println!("  backend in use:  {}", s.backend_in_use);
    println!(
        "  sessions:        {} total ({} ok, {} failed)",
        s.sessions_total, s.sessions_succeeded, s.sessions_failed
    );
    if let Some(ms) = s.last_first_partial_ms {
        println!("  last first partial: {}ms", ms);
    }
    if let Some(ms) = s.last_session_latency_ms {
        println!("  last total latency: {}ms", ms);
    }
    if let Some(logid) = &s.last_session_logid {
        println!("  last logid:        {}", logid);
    }
    if !s.recent_errors.is_empty() {
        println!("  recent errors:");
        for e in &s.recent_errors {
            println!("    {} — {}", e.timestamp_unix_secs, e.message);
        }
    }
}
