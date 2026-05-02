//! Phase 1 orchestrator: only knows how to answer Status.
//! Phases 2-5 progressively grow this into the full state machine in spec §4.1.

use async_trait::async_trait;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::{Notify, RwLock};
use tracing::{info, warn};
use voco_config::Config;
use voco_ipc::protocol::{Request, Response, StatusInfo};
use voco_ipc::server::RequestHandler;

use crate::state::DaemonState;

pub struct Orchestrator {
    started_at: Instant,
    state: Arc<RwLock<DaemonState>>,
    #[allow(dead_code)]
    config: Arc<RwLock<Config>>,
    shutdown: Arc<Notify>,
}

impl Orchestrator {
    pub fn new(config: Config) -> Self {
        Self {
            started_at: Instant::now(),
            state: Arc::new(RwLock::new(DaemonState::Idle)),
            config: Arc::new(RwLock::new(config)),
            shutdown: Arc::new(Notify::new()),
        }
    }

    pub fn shutdown_signal(&self) -> Arc<Notify> {
        self.shutdown.clone()
    }
}

#[async_trait]
impl RequestHandler for Orchestrator {
    async fn handle(&self, req: Request) -> Response {
        match req {
            Request::Status => {
                let state = *self.state.read().await;
                let cfg = self.config.read().await;
                Response::Status(StatusInfo {
                    state: state.as_str().into(),
                    backend: format!("{:?}", cfg.backend).to_lowercase(),
                    backend_in_use: "(not yet implemented)".into(),
                    uptime_secs: self.started_at.elapsed().as_secs(),
                    sessions_total: 0,
                    sessions_succeeded: 0,
                    sessions_failed: 0,
                    last_session_latency_ms: None,
                    last_first_partial_ms: None,
                    recent_errors: vec![],
                })
            }
            Request::DaemonShutdown => {
                info!("shutdown requested via IPC");
                self.shutdown.notify_one();
                Response::Ok
            }
            Request::ReloadConfig => {
                warn!("reload not yet implemented in Phase 1");
                Response::Error {
                    message: "reload_config: not yet implemented".into(),
                }
            }
            Request::RecordingStart | Request::RecordingStop => Response::Error {
                message: "recording: not yet implemented (Phase 3)".into(),
            },
        }
    }
}
