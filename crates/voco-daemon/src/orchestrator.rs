//! Orchestrator. Phase 2 wires `ReloadConfig` and `DumpConfig`; the rest
//! (recording state machine) lands in later phases.

use async_trait::async_trait;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::{Notify, RwLock};
use tracing::{info, warn};
use voco_config::{Config, ConfigIo};
use voco_ipc::protocol::{Request, Response, StatusInfo};
use voco_ipc::server::RequestHandler;

use crate::reload::{diff_for_restart, format_validation};
use crate::state::DaemonState;

pub struct Orchestrator {
    started_at: Instant,
    state: Arc<RwLock<DaemonState>>,
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
            Request::ReloadConfig => match ConfigIo::load_from(&ConfigIo::default_path()) {
                Err(e) => Response::Error {
                    message: format!("reload: {e}"),
                },
                Ok(new) => {
                    let errs = new.validate();
                    if !errs.is_empty() {
                        return Response::Error {
                            message: format_validation(&errs),
                        };
                    }
                    let mut cfg = self.config.write().await;
                    let warnings = diff_for_restart(&cfg, &new);
                    *cfg = new;
                    info!(?warnings, "config reloaded");
                    if warnings.is_empty() {
                        Response::Ok
                    } else {
                        Response::OkWithWarnings { warnings }
                    }
                }
            },
            Request::DumpConfig => {
                let cfg = self.config.read().await;
                match serde_json::to_value(cfg.redacted_clone()) {
                    Ok(v) => Response::Config(v),
                    Err(e) => Response::Error {
                        message: format!("serialize config: {e}"),
                    },
                }
            }
            Request::RecordingStart | Request::RecordingStop => {
                warn!("recording requested before Phase 3 lands");
                Response::Error {
                    message: "recording: not yet implemented (Phase 3)".into(),
                }
            }
        }
    }
}
