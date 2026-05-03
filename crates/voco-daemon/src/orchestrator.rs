//! Orchestrator. Phase 2 wires `ReloadConfig` and `DumpConfig`; the rest
//! (recording state machine) lands in later phases.

use async_trait::async_trait;
use std::sync::Arc;
use std::time::{Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::{oneshot, Notify, RwLock};
use tracing::{info, warn};
use voco_config::{Config, ConfigIo};
use voco_ipc::protocol::{Request, Response};
use voco_ipc::server::RequestHandler;

use crate::reload::{diff_for_restart, format_validation};
use crate::session::{RecordingPayload, RecordingSession, SessionError};
use crate::state::DaemonState;
use crate::stats::Stats;

pub struct Orchestrator {
    started_at: Instant,
    state: Arc<RwLock<DaemonState>>,
    config: Arc<RwLock<Config>>,
    stats: Arc<RwLock<Stats>>,
    shutdown: Arc<Notify>,
    recording_runner: Arc<dyn RecordingRunner>,
}

impl Orchestrator {
    pub fn new(config: Config) -> Self {
        Self::with_runner(config, default_recording_runner())
    }

    fn with_runner(config: Config, recording_runner: Arc<dyn RecordingRunner>) -> Self {
        let backend = backend_label(&config);
        Self {
            started_at: Instant::now(),
            state: Arc::new(RwLock::new(DaemonState::Idle)),
            config: Arc::new(RwLock::new(config)),
            stats: Arc::new(RwLock::new(Stats::new(backend))),
            shutdown: Arc::new(Notify::new()),
            recording_runner,
        }
    }

    #[cfg(test)]
    fn with_recording_runner(config: Config, recording_runner: Arc<dyn RecordingRunner>) -> Self {
        Self::with_runner(config, recording_runner)
    }

    pub fn shutdown_signal(&self) -> Arc<Notify> {
        self.shutdown.clone()
    }

    async fn handle_recording_once(&self, duration_ms: u32, include_partials: bool) -> Response {
        {
            let mut state = self.state.write().await;
            if *state != DaemonState::Idle {
                return Response::Error {
                    message: format!("busy: state={state:?}"),
                };
            }
            *state = DaemonState::Recording;
        }

        let cfg = self.config.read().await.clone();
        let duration_ms = duration_ms.min(cfg.recording_max_duration_secs.saturating_mul(1_000));
        let (_stop_tx, stop_rx) = oneshot::channel();
        let result = self
            .recording_runner
            .run_once(cfg, duration_ms, include_partials, stop_rx)
            .await;

        match result {
            Ok(payload) => {
                *self.state.write().await = DaemonState::Transcribing;
                *self.state.write().await = DaemonState::Injecting;
                self.stats.write().await.record_success(&payload);
                *self.state.write().await = DaemonState::Idle;
                payload_to_response(payload)
            }
            Err(err) => {
                *self.state.write().await = DaemonState::Error;
                self.stats
                    .write()
                    .await
                    .record_failure(err.to_string(), now_unix_secs());
                *self.state.write().await = DaemonState::Idle;
                Response::Error {
                    message: format!("recording: {err}"),
                }
            }
        }
    }
}

#[async_trait]
trait RecordingRunner: Send + Sync {
    async fn run_once(
        &self,
        config: Config,
        duration_ms: u32,
        include_partials: bool,
        stop_rx: oneshot::Receiver<()>,
    ) -> Result<RecordingPayload, SessionError>;
}

struct RealRecordingRunner;

fn default_recording_runner() -> Arc<dyn RecordingRunner> {
    #[cfg(debug_assertions)]
    {
        if std::env::var("VOCO_FORCE_MOCK_BACKEND").ok().as_deref() == Some("1") {
            warn!("VOCO_FORCE_MOCK_BACKEND=1 active; using debug mock recording runner");
            return Arc::new(DebugMockRecordingRunner);
        }
    }
    #[cfg(not(debug_assertions))]
    {
        if std::env::var("VOCO_FORCE_MOCK_BACKEND").is_ok() {
            warn!("VOCO_FORCE_MOCK_BACKEND is ignored in release builds");
        }
    }
    Arc::new(RealRecordingRunner)
}

#[async_trait]
impl RecordingRunner for RealRecordingRunner {
    async fn run_once(
        &self,
        config: Config,
        duration_ms: u32,
        include_partials: bool,
        stop_rx: oneshot::Receiver<()>,
    ) -> Result<RecordingPayload, SessionError> {
        let (result_tx, result_rx) = oneshot::channel();
        std::thread::spawn(move || {
            let result = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .map_err(|err| SessionError::Runtime(err.to_string()))
                .and_then(|runtime| {
                    runtime.block_on(async move {
                        RecordingSession::start_from_config(&config)?
                            .run(duration_ms, include_partials, stop_rx)
                            .await
                    })
                });
            let _ = result_tx.send(result);
        });
        result_rx.await.map_err(|_| SessionError::WorkerStopped)?
    }
}

#[cfg(debug_assertions)]
struct DebugMockRecordingRunner;

#[cfg(debug_assertions)]
#[async_trait]
impl RecordingRunner for DebugMockRecordingRunner {
    async fn run_once(
        &self,
        _config: Config,
        duration_ms: u32,
        include_partials: bool,
        _stop_rx: oneshot::Receiver<()>,
    ) -> Result<RecordingPayload, SessionError> {
        if let Some(delay) = mock_recording_delay() {
            tokio::time::sleep(delay).await;
        }
        let partials = if include_partials {
            vec![
                voco_ipc::protocol::PartialSnapshot {
                    at_ms: 120,
                    text: "mock".into(),
                    stable_prefix_len: 4,
                },
                voco_ipc::protocol::PartialSnapshot {
                    at_ms: 180,
                    text: "mock final".into(),
                    stable_prefix_len: 10,
                },
            ]
        } else {
            vec![]
        };
        Ok(RecordingPayload {
            text: "mock final".into(),
            segments: vec![voco_ipc::protocol::Segment {
                text: "mock final".into(),
                start_ms: 0,
                end_ms: duration_ms,
                definite: true,
            }],
            partials,
            logid: Some("mock-logid".into()),
            first_partial_ms: Some(120),
            total_latency_ms: duration_ms.into(),
            error_hint: None,
        })
    }
}

#[cfg(debug_assertions)]
fn mock_recording_delay() -> Option<std::time::Duration> {
    let delay_ms: u64 = std::env::var("VOCO_MOCK_RECORDING_DELAY_MS")
        .ok()?
        .parse()
        .ok()?;
    Some(std::time::Duration::from_millis(delay_ms))
}

fn payload_to_response(payload: RecordingPayload) -> Response {
    Response::RecordingResult {
        text: payload.text,
        segments: payload.segments,
        partials: payload.partials,
        logid: payload.logid,
        first_partial_ms: payload.first_partial_ms,
        total_latency_ms: payload.total_latency_ms,
        error_hint: payload.error_hint,
    }
}

fn backend_label(cfg: &Config) -> String {
    format!("{:?}", cfg.backend).to_lowercase()
}

fn now_unix_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default()
}

#[async_trait]
impl RequestHandler for Orchestrator {
    async fn handle(&self, req: Request) -> Response {
        match req {
            Request::Status => {
                let state = *self.state.read().await;
                let cfg = self.config.read().await;
                let stats = self.stats.read().await;
                Response::Status(stats.to_status_info(
                    state,
                    backend_label(&cfg),
                    self.started_at.elapsed().as_secs(),
                ))
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
            Request::RecordingOnce {
                duration_ms,
                include_partials,
            } => {
                self.handle_recording_once(duration_ms, include_partials)
                    .await
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

#[cfg(test)]
mod recording_tests {
    use super::*;
    use async_trait::async_trait;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tokio::sync::{oneshot, Mutex};
    use voco_ipc::protocol::{PartialSnapshot, Segment};

    use crate::session::{RecordingPayload, SessionError};

    struct FakeRecordingRunner {
        payload: RecordingPayload,
        delay: std::time::Duration,
        calls: AtomicUsize,
        durations: Mutex<Vec<u32>>,
    }

    impl FakeRecordingRunner {
        fn new(delay: std::time::Duration) -> Self {
            Self {
                payload: RecordingPayload {
                    text: "mock final".into(),
                    segments: vec![Segment {
                        text: "mock final".into(),
                        start_ms: 0,
                        end_ms: 420,
                        definite: true,
                    }],
                    partials: vec![PartialSnapshot {
                        at_ms: 120,
                        text: "mock".into(),
                        stable_prefix_len: 4,
                    }],
                    logid: Some("log-xyz".into()),
                    first_partial_ms: Some(120),
                    total_latency_ms: 640,
                    error_hint: None,
                },
                delay,
                calls: AtomicUsize::new(0),
                durations: Mutex::new(Vec::new()),
            }
        }
    }

    #[async_trait]
    impl RecordingRunner for FakeRecordingRunner {
        async fn run_once(
            &self,
            _config: Config,
            duration_ms: u32,
            _include_partials: bool,
            _stop_rx: oneshot::Receiver<()>,
        ) -> Result<RecordingPayload, SessionError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            self.durations.lock().await.push(duration_ms);
            tokio::time::sleep(self.delay).await;
            Ok(self.payload.clone())
        }
    }

    #[tokio::test]
    async fn recording_once_returns_result_and_updates_status_stats() {
        let runner = Arc::new(FakeRecordingRunner::new(std::time::Duration::ZERO));
        let orch = Orchestrator::with_recording_runner(Config::default(), runner.clone());

        let resp = orch
            .handle(Request::RecordingOnce {
                duration_ms: 1_000,
                include_partials: true,
            })
            .await;

        match resp {
            Response::RecordingResult {
                text,
                logid,
                first_partial_ms,
                total_latency_ms,
                partials,
                ..
            } => {
                assert_eq!(text, "mock final");
                assert_eq!(logid.as_deref(), Some("log-xyz"));
                assert_eq!(first_partial_ms, Some(120));
                assert_eq!(total_latency_ms, 640);
                assert_eq!(partials.len(), 1);
            }
            other => panic!("expected RecordingResult, got {other:?}"),
        }

        let status = orch.handle(Request::Status).await;
        match status {
            Response::Status(status) => {
                assert_eq!(status.state, "idle");
                assert_eq!(status.sessions_total, 1);
                assert_eq!(status.sessions_succeeded, 1);
                assert_eq!(status.last_session_logid.as_deref(), Some("log-xyz"));
                assert_eq!(status.backend_in_use, "doubao (logid=log-xyz)");
            }
            other => panic!("expected Status, got {other:?}"),
        }
        assert_eq!(runner.calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn recording_once_rejects_concurrent_request_as_busy() {
        let runner = Arc::new(FakeRecordingRunner::new(std::time::Duration::from_millis(
            80,
        )));
        let orch = Arc::new(Orchestrator::with_recording_runner(
            Config::default(),
            runner.clone(),
        ));

        let first = tokio::spawn({
            let orch = orch.clone();
            async move {
                orch.handle(Request::RecordingOnce {
                    duration_ms: 1_000,
                    include_partials: false,
                })
                .await
            }
        });
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;

        let second = orch
            .handle(Request::RecordingOnce {
                duration_ms: 1_000,
                include_partials: false,
            })
            .await;

        match second {
            Response::Error { message } => assert!(message.contains("busy: state=Recording")),
            other => panic!("expected busy Error, got {other:?}"),
        }
        let _ = first.await.unwrap();
        assert_eq!(runner.calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn recording_once_duration_is_capped_by_config_max() {
        let runner = Arc::new(FakeRecordingRunner::new(std::time::Duration::ZERO));
        let cfg = Config {
            recording_max_duration_secs: 2,
            ..Config::default()
        };
        let orch = Orchestrator::with_recording_runner(cfg, runner.clone());

        let _ = orch
            .handle(Request::RecordingOnce {
                duration_ms: 10_000,
                include_partials: false,
            })
            .await;

        assert_eq!(*runner.durations.lock().await, vec![2_000]);
    }
}
