//! `voco daemon` — Phase 1 lifecycle: spawn, signal-stop, restart, tail logs.
//! Phase 6 will replace this with launchctl-managed registration.

mod launch_agent;

use crate::DaemonAction;
use anyhow::{anyhow, bail, Result};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
use voco_daemon::{default_log_file, default_socket_path, latest_log_file, logs_dir};
use voco_ipc::client::IpcClient;
use voco_ipc::protocol::{Request, Response};

pub fn run(action: DaemonAction) -> Result<()> {
    match action {
        DaemonAction::Install { app_bundle } => install(app_bundle),
        DaemonAction::Uninstall => uninstall(),
        DaemonAction::Start => start(),
        DaemonAction::Stop => stop(),
        DaemonAction::Restart => restart(),
        DaemonAction::Logs { follow, lines } => logs(follow, lines),
    }
}

fn install(app_bundle: Option<PathBuf>) -> Result<()> {
    let agent = discover_launch_agent(app_bundle.as_deref())?;
    match agent.install()? {
        launch_agent::InstallOutcome::Created => {
            println!(
                "✓ installed LaunchAgent: {}",
                agent.paths.plist_path.display()
            );
        }
        launch_agent::InstallOutcome::Updated => {
            println!(
                "✓ updated LaunchAgent: {}",
                agent.paths.plist_path.display()
            );
        }
        launch_agent::InstallOutcome::Unchanged => {
            println!(
                "✓ LaunchAgent already installed: {}",
                agent.paths.plist_path.display()
            );
        }
    }
    println!("  daemon: {}", agent.paths.daemon_path.display());
    println!("  working directory: {}", agent.paths.working_dir.display());
    println!("  start it with: voco daemon start");
    Ok(())
}

fn uninstall() -> Result<()> {
    let agent = discover_launch_agent(None)?;
    if agent.is_installed() {
        agent.stop()?;
        let _ = wait_for_socket_to_disappear(Duration::from_secs(3));
    }
    if agent.uninstall_plist()? {
        println!(
            "✓ removed LaunchAgent: {}",
            agent.paths.plist_path.display()
        );
    } else {
        println!("✓ LaunchAgent already uninstalled");
    }
    Ok(())
}

fn discover_launch_agent(
    app_bundle: Option<&std::path::Path>,
) -> Result<launch_agent::LaunchAgent> {
    if let Some(bundle_path) = app_bundle {
        let bundle = launch_agent::AppBundle::discover(bundle_path)?;
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .ok_or_else(|| anyhow!("HOME is not set; cannot resolve LaunchAgent path"))?;
        return Ok(launch_agent::LaunchAgent::from_parts(
            home,
            bundle.daemon_path,
            bundle.working_dir,
        ));
    }

    let daemon_path = locate_daemon_binary()?;
    launch_agent::LaunchAgent::discover(daemon_path)
}

fn start() -> Result<()> {
    if is_daemon_running() {
        println!("✓ daemon already running");
        return Ok(());
    }

    let agent = discover_launch_agent(None)?;
    if agent.is_installed() {
        agent.start()?;
        wait_for_socket(Duration::from_secs(3))?;
        println!("✓ daemon started via launchctl");
        println!("  service: {}", agent.service_target()?);
        return Ok(());
    }

    start_direct_spawn()
}

fn start_direct_spawn() -> Result<()> {
    let bin = locate_daemon_binary()?;
    let log_file = default_log_file();
    if let Some(parent) = log_file.parent() {
        std::fs::create_dir_all(parent)?;
    }

    // Phase 1 spawns the daemon as a child process with stdout/stderr piped
    // to the log file. Detachment from the controlling terminal happens in
    // Phase 6 via launchctl; for development this is enough.
    let log = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_file)?;
    let log_dup = log.try_clone()?;

    let child = Command::new(&bin)
        .stdin(Stdio::null())
        .stdout(log)
        .stderr(log_dup)
        .spawn()?;

    let pid = child.id();
    println!("✓ daemon started (pid {pid})");
    println!("  logs: {}", log_file.display());

    wait_for_socket(Duration::from_secs(2)).map_err(|_| {
        anyhow!(
            "daemon spawned but socket {} not ready after 2s — check {}",
            default_socket_path().display(),
            log_file.display()
        )
    })
}

fn stop() -> Result<()> {
    let agent = discover_launch_agent(None)?;
    if agent.is_installed() {
        agent.stop()?;
        wait_for_socket_to_disappear(Duration::from_secs(3))?;
        println!("✓ daemon stopped");
        return Ok(());
    }

    stop_via_ipc()
}

fn stop_via_ipc() -> Result<()> {
    let sock = default_socket_path();
    let mut client = match IpcClient::connect(&sock) {
        Ok(c) => c,
        Err(_) => {
            println!("✓ daemon already stopped");
            return Ok(());
        }
    };
    match client.call(&Request::DaemonShutdown)? {
        Response::Ok => {
            println!("✓ shutdown requested; waiting for daemon to exit");
            let deadline = Instant::now() + Duration::from_secs(3);
            while Instant::now() < deadline {
                if UnixStream::connect(&sock).is_err() {
                    println!("✓ daemon stopped");
                    return Ok(());
                }
                std::thread::sleep(Duration::from_millis(100));
            }
            bail!("daemon did not exit within 3s")
        }
        other => bail!("unexpected response: {:?}", other),
    }
}

fn restart() -> Result<()> {
    let agent = discover_launch_agent(None)?;
    if agent.is_installed() {
        agent.restart()?;
        wait_for_socket(Duration::from_secs(3))?;
        println!("✓ daemon restarted via launchctl");
        println!("  service: {}", agent.service_target()?);
        return Ok(());
    }

    let _ = stop_via_ipc();
    std::thread::sleep(Duration::from_millis(200));
    start_direct_spawn()
}

fn wait_for_socket(timeout: Duration) -> Result<()> {
    let deadline = Instant::now() + timeout;
    let sock = default_socket_path();
    while Instant::now() < deadline {
        if UnixStream::connect(&sock).is_ok() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    Err(anyhow!(
        "daemon socket {} not ready after {:?}",
        sock.display(),
        timeout
    ))
}

fn wait_for_socket_to_disappear(timeout: Duration) -> Result<()> {
    let deadline = Instant::now() + timeout;
    let sock = default_socket_path();
    while Instant::now() < deadline {
        if UnixStream::connect(&sock).is_err() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    bail!(
        "daemon socket {} still reachable after {:?}",
        sock.display(),
        timeout
    )
}

fn logs(follow: bool, lines: u32) -> Result<()> {
    let path = match latest_log_file() {
        Some(p) => p,
        None => {
            let dir = logs_dir();
            println!("(no log files yet in {})", dir.display());
            if !is_daemon_running() {
                println!("  start the daemon with: voco daemon start");
            }
            return Ok(());
        }
    };
    let mut cmd = Command::new("tail");
    cmd.arg("-n").arg(lines.to_string());
    if follow {
        cmd.arg("-F");
    }
    cmd.arg(&path);
    let status = cmd.status()?;
    if !status.success() {
        bail!("tail exited with {}", status);
    }
    Ok(())
}

fn is_daemon_running() -> bool {
    UnixStream::connect(default_socket_path()).is_ok()
}

fn locate_daemon_binary() -> Result<PathBuf> {
    // 1. Same dir as the current 'voco' executable.
    let here = std::env::current_exe()?;
    let candidate = here.with_file_name("voco-daemon");
    if candidate.exists() {
        return Ok(candidate);
    }
    // 2. PATH lookup.
    if let Ok(path_var) = std::env::var("PATH") {
        for dir in std::env::split_paths(&path_var) {
            let p = dir.join("voco-daemon");
            if p.exists() {
                return Ok(p);
            }
        }
    }
    Err(anyhow!(
        "could not find voco-daemon binary; expected next to {} or on PATH",
        here.display()
    ))
}
