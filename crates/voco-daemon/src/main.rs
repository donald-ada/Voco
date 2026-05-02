//! voco-daemon binary. Phase 1: bind IPC socket, answer Status, exit on
//! SIGTERM/SIGINT/IPC-shutdown.

use std::sync::Arc;
use tracing::{error, info};
use tracing_subscriber::EnvFilter;
use voco_config::ConfigIo;
use voco_daemon::{default_socket_path, logs_dir, Orchestrator};
use voco_ipc::server::IpcServer;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    init_logging()?;
    info!(version = env!("CARGO_PKG_VERSION"), "voco-daemon starting");

    let cfg = ConfigIo::load().unwrap_or_else(|e| {
        error!(error = %e, "failed to load config; using defaults");
        Default::default()
    });

    let socket_path = default_socket_path();
    let server = IpcServer::bind(&socket_path)?;

    let orch = Arc::new(Orchestrator::new(cfg));
    let shutdown = orch.shutdown_signal();

    let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    let mut sigint = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())?;

    let serve_handle = tokio::spawn({
        let orch = orch.clone();
        async move { server.serve(orch).await }
    });

    tokio::select! {
        _ = sigterm.recv()      => info!("SIGTERM received, exiting"),
        _ = sigint.recv()       => info!("SIGINT received, exiting"),
        _ = shutdown.notified() => info!("IPC shutdown received"),
    }

    serve_handle.abort();
    info!("voco-daemon stopped");
    Ok(())
}

fn init_logging() -> anyhow::Result<()> {
    let dir = logs_dir();
    std::fs::create_dir_all(&dir)?;
    let appender = tracing_appender::rolling::Builder::new()
        .filename_prefix("voco")
        .filename_suffix("log")
        .max_log_files(5)
        .build(&dir)?;
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info,voco=debug"));
    tracing_subscriber::fmt()
        .with_env_filter(env_filter)
        .with_writer(appender)
        .with_ansi(false)
        .json()
        .init();
    Ok(())
}
