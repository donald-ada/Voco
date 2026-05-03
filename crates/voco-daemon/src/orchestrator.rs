//! Orchestrator. Phase 2 wires `ReloadConfig` and `DumpConfig`; the rest
//! (recording state machine) lands in later phases.

use async_trait::async_trait;
use std::sync::Arc;
use std::time::{Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::{oneshot, Mutex, Notify, RwLock};
use tracing::{info, warn};
use voco_config::{Config, ConfigIo, OutputConfig};
use voco_injector::{InjectionError, InjectionOutcome, Injector};
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
    text_injector: Arc<dyn TextInjector>,
    active_recording: Arc<Mutex<Option<ActiveRecording>>>,
    hud: crate::hud::SharedHudSink,
}

impl Orchestrator {
    pub fn new(config: Config) -> Self {
        Self::with_runner(config, default_recording_runner())
    }

    pub fn new_with_hud(config: Config, hud: crate::hud::SharedHudSink) -> Self {
        Self::with_parts(
            config,
            default_recording_runner(),
            default_text_injector(),
            hud,
        )
    }

    fn with_runner(config: Config, recording_runner: Arc<dyn RecordingRunner>) -> Self {
        Self::with_parts(
            config,
            recording_runner,
            default_text_injector(),
            crate::hud::noop_hud_sink(),
        )
    }

    fn with_parts(
        config: Config,
        recording_runner: Arc<dyn RecordingRunner>,
        text_injector: Arc<dyn TextInjector>,
        hud: crate::hud::SharedHudSink,
    ) -> Self {
        let backend = backend_label(&config);
        Self {
            started_at: Instant::now(),
            state: Arc::new(RwLock::new(DaemonState::Idle)),
            config: Arc::new(RwLock::new(config)),
            stats: Arc::new(RwLock::new(Stats::new(backend))),
            shutdown: Arc::new(Notify::new()),
            recording_runner,
            text_injector,
            active_recording: Arc::new(Mutex::new(None)),
            hud,
        }
    }

    #[cfg(test)]
    fn with_recording_runner(config: Config, recording_runner: Arc<dyn RecordingRunner>) -> Self {
        Self::with_runner(config, recording_runner)
    }

    #[cfg(test)]
    fn with_runner_and_injector(
        config: Config,
        recording_runner: Arc<dyn RecordingRunner>,
        text_injector: Arc<dyn TextInjector>,
    ) -> Self {
        Self::with_parts(
            config,
            recording_runner,
            text_injector,
            crate::hud::noop_hud_sink(),
        )
    }

    #[cfg(test)]
    fn with_runner_injector_and_hud(
        config: Config,
        recording_runner: Arc<dyn RecordingRunner>,
        text_injector: Arc<dyn TextInjector>,
        hud: crate::hud::SharedHudSink,
    ) -> Self {
        Self::with_parts(config, recording_runner, text_injector, hud)
    }

    pub fn shutdown_signal(&self) -> Arc<Notify> {
        self.shutdown.clone()
    }

    pub async fn handle_hotkey_toggle(&self) -> Response {
        let state = *self.state.read().await;
        match state {
            DaemonState::Idle => self.handle_recording_start().await,
            DaemonState::Recording => self.handle_hotkey_recording_stop().await,
            state => {
                warn!(?state, "hotkey toggle ignored while daemon is busy");
                Response::Ok
            }
        }
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
            .run_once(cfg, duration_ms, include_partials, stop_rx, None)
            .await;

        match result {
            Ok(payload) => {
                finalize_recording_result(
                    Ok(payload),
                    self.state.clone(),
                    self.stats.clone(),
                    self.config.clone(),
                    self.text_injector.clone(),
                    false,
                    crate::hud::noop_hud_sink(),
                    false,
                )
                .await
            }
            Err(err) => {
                finalize_recording_result(
                    Err(err),
                    self.state.clone(),
                    self.stats.clone(),
                    self.config.clone(),
                    self.text_injector.clone(),
                    false,
                    crate::hud::noop_hud_sink(),
                    false,
                )
                .await
            }
        }
    }

    async fn handle_recording_start(&self) -> Response {
        {
            let mut state = self.state.write().await;
            if *state != DaemonState::Idle {
                return Response::Error {
                    message: format!("busy: state={state:?}"),
                };
            }
            *state = DaemonState::Recording;
        }
        let _ = self
            .hud
            .send(crate::hud::HudEvent::state(crate::hud::HudState::Recording));

        let cfg = self.config.read().await.clone();
        let duration_ms = cfg.recording_max_duration_secs.saturating_mul(1_000);
        let (stop_tx, stop_rx) = oneshot::channel();
        let (response_tx, response_rx) = oneshot::channel();
        let runner = self.recording_runner.clone();
        let state = self.state.clone();
        let stats = self.stats.clone();
        let config = self.config.clone();
        let injector = self.text_injector.clone();
        let active_slot = self.active_recording.clone();
        let hud = self.hud.clone();
        let recording_hud = Some(hud.clone());

        tokio::spawn(async move {
            let result = runner
                .run_once(cfg, duration_ms, false, stop_rx, recording_hud)
                .await;
            let response =
                finalize_recording_result(result, state, stats, config, injector, true, hud, true)
                    .await;
            let mut active = active_slot.lock().await;
            active.take();
            drop(active);
            let _ = response_tx.send(response);
        });

        *self.active_recording.lock().await = Some(ActiveRecording {
            stop_tx: Some(stop_tx),
            response_rx,
        });
        Response::Ok
    }

    async fn take_active_recording(&self) -> Result<ActiveRecording, Response> {
        let Some(mut active) = self.active_recording.lock().await.take() else {
            return Err(Response::Error {
                message: "not recording".into(),
            });
        };
        if let Some(stop_tx) = active.stop_tx.take() {
            let _ = stop_tx.send(());
        }
        *self.state.write().await = DaemonState::Transcribing;
        let _ = self.hud.send(crate::hud::HudEvent::state(
            crate::hud::HudState::Transcribing,
        ));
        Ok(active)
    }

    async fn handle_hotkey_recording_stop(&self) -> Response {
        let active = match self.take_active_recording().await {
            Ok(active) => active,
            Err(err) => return err,
        };
        let state = self.state.clone();
        let stats = self.stats.clone();
        let hud = self.hud.clone();
        tokio::spawn(async move {
            match active.response_rx.await {
                Ok(Response::Error { message }) => {
                    warn!(error = %message, "hotkey recording stop finalized with error");
                }
                Ok(_) => {}
                Err(_) => {
                    *state.write().await = DaemonState::Error;
                    stats
                        .write()
                        .await
                        .record_failure("recording task stopped", now_unix_secs());
                    *state.write().await = DaemonState::Idle;
                    let _ = hud.send(crate::hud::HudEvent::error("recording task stopped"));
                    spawn_delayed_hud_hide(hud.clone());
                }
            }
        });
        Response::Ok
    }

    async fn handle_recording_stop(&self) -> Response {
        let active = match self.take_active_recording().await {
            Ok(active) => active,
            Err(err) => return err,
        };
        match active.response_rx.await {
            Ok(response) => response,
            Err(_) => {
                *self.state.write().await = DaemonState::Error;
                self.stats
                    .write()
                    .await
                    .record_failure("recording task stopped", now_unix_secs());
                *self.state.write().await = DaemonState::Idle;
                let _ = self
                    .hud
                    .send(crate::hud::HudEvent::error("recording task stopped"));
                spawn_delayed_hud_hide(self.hud.clone());
                Response::Error {
                    message: "recording task stopped".into(),
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
        hud: Option<crate::hud::SharedHudSink>,
    ) -> Result<RecordingPayload, SessionError>;
}

trait TextInjector: Send + Sync {
    fn insert(&self, text: &str, output: &OutputConfig)
        -> Result<InjectionOutcome, InjectionError>;
}

struct RealTextInjector;

impl TextInjector for RealTextInjector {
    fn insert(
        &self,
        text: &str,
        output: &OutputConfig,
    ) -> Result<InjectionOutcome, InjectionError> {
        Injector::insert(text, output)
    }
}

fn default_text_injector() -> Arc<dyn TextInjector> {
    #[cfg(debug_assertions)]
    {
        if std::env::var("VOCO_FORCE_MOCK_INJECTOR").ok().as_deref() == Some("1") {
            warn!("VOCO_FORCE_MOCK_INJECTOR=1 active; using debug mock text injector");
            return Arc::new(DebugMockTextInjector);
        }
    }
    Arc::new(RealTextInjector)
}

#[cfg(debug_assertions)]
struct DebugMockTextInjector;

#[cfg(debug_assertions)]
impl TextInjector for DebugMockTextInjector {
    fn insert(
        &self,
        text: &str,
        _output: &OutputConfig,
    ) -> Result<InjectionOutcome, InjectionError> {
        info!(
            chars = text.chars().count(),
            "debug mock text injection completed"
        );
        Ok(InjectionOutcome::Injected)
    }
}

struct ActiveRecording {
    stop_tx: Option<oneshot::Sender<()>>,
    response_rx: oneshot::Receiver<Response>,
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
        hud: Option<crate::hud::SharedHudSink>,
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
                            .run_with_hud(duration_ms, include_partials, stop_rx, hud)
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
        _hud: Option<crate::hud::SharedHudSink>,
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

#[allow(clippy::too_many_arguments)]
async fn finalize_recording_result(
    result: Result<RecordingPayload, SessionError>,
    state: Arc<RwLock<DaemonState>>,
    stats: Arc<RwLock<Stats>>,
    config: Arc<RwLock<Config>>,
    injector: Arc<dyn TextInjector>,
    inject: bool,
    hud: crate::hud::SharedHudSink,
    show_hud: bool,
) -> Response {
    match result {
        Ok(payload) => {
            *state.write().await = DaemonState::Transcribing;
            if inject {
                *state.write().await = DaemonState::Injecting;
                let output = config.read().await.output.clone();
                match injector.insert(&payload.text, &output) {
                    Ok(outcome) => {
                        info!(
                            outcome = ?outcome,
                            chars = payload.text.chars().count(),
                            "text injection completed"
                        );
                    }
                    Err(err) => {
                        *state.write().await = DaemonState::Error;
                        stats
                            .write()
                            .await
                            .record_failure(format!("injection: {err}"), now_unix_secs());
                        *state.write().await = DaemonState::Idle;
                        if show_hud {
                            let _ =
                                hud.send(crate::hud::HudEvent::error(format!("injection: {err}")));
                            spawn_delayed_hud_hide(hud.clone());
                        }
                        return Response::Error {
                            message: format!("injection: {err}"),
                        };
                    }
                }
            }
            stats.write().await.record_success(&payload);
            *state.write().await = DaemonState::Idle;
            if show_hud {
                let _ = hud.send(crate::hud::HudEvent::state(crate::hud::HudState::Hidden));
            }
            payload_to_response(payload)
        }
        Err(err) => {
            *state.write().await = DaemonState::Error;
            stats
                .write()
                .await
                .record_failure(err.to_string(), now_unix_secs());
            *state.write().await = DaemonState::Idle;
            if show_hud {
                let _ = hud.send(crate::hud::HudEvent::error(err.to_string()));
                spawn_delayed_hud_hide(hud.clone());
            }
            Response::Error {
                message: format!("recording: {err}"),
            }
        }
    }
}

fn spawn_delayed_hud_hide(hud: crate::hud::SharedHudSink) {
    tokio::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        let _ = hud.send(crate::hud::HudEvent::state(crate::hud::HudState::Hidden));
    });
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
            Request::RecordingStart => self.handle_recording_start().await,
            Request::RecordingStop => self.handle_recording_stop().await,
        }
    }
}

#[cfg(test)]
mod recording_tests {
    use super::*;
    use async_trait::async_trait;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Mutex as StdMutex;
    use tokio::sync::{oneshot, Mutex};
    use voco_config::OutputConfig;
    use voco_injector::{InjectionError, InjectionOutcome};
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
            _hud: Option<crate::hud::SharedHudSink>,
        ) -> Result<RecordingPayload, SessionError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            self.durations.lock().await.push(duration_ms);
            tokio::time::sleep(self.delay).await;
            Ok(self.payload.clone())
        }
    }

    struct StopAwareRunner {
        payload: RecordingPayload,
        calls: AtomicUsize,
        delay_after_stop: std::time::Duration,
    }

    impl StopAwareRunner {
        fn new() -> Self {
            Self {
                payload: RecordingPayload {
                    text: "toggle final".into(),
                    segments: vec![],
                    partials: vec![],
                    logid: Some("toggle-log".into()),
                    first_partial_ms: Some(90),
                    total_latency_ms: 510,
                    error_hint: None,
                },
                calls: AtomicUsize::new(0),
                delay_after_stop: std::time::Duration::ZERO,
            }
        }

        fn with_delay(delay_after_stop: std::time::Duration) -> Self {
            Self {
                delay_after_stop,
                ..Self::new()
            }
        }
    }

    #[async_trait]
    impl RecordingRunner for StopAwareRunner {
        async fn run_once(
            &self,
            _config: Config,
            _duration_ms: u32,
            _include_partials: bool,
            stop_rx: oneshot::Receiver<()>,
            _hud: Option<crate::hud::SharedHudSink>,
        ) -> Result<RecordingPayload, SessionError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            let _ = stop_rx.await;
            if !self.delay_after_stop.is_zero() {
                tokio::time::sleep(self.delay_after_stop).await;
            }
            Ok(self.payload.clone())
        }
    }

    struct DurationCapturingRunner {
        payload: RecordingPayload,
        durations: Mutex<Vec<u32>>,
        calls: AtomicUsize,
    }

    impl DurationCapturingRunner {
        fn new() -> Self {
            Self {
                payload: RecordingPayload {
                    text: "duration final".into(),
                    segments: vec![],
                    partials: vec![],
                    logid: Some("duration-log".into()),
                    first_partial_ms: Some(90),
                    total_latency_ms: 510,
                    error_hint: None,
                },
                durations: Mutex::new(Vec::new()),
                calls: AtomicUsize::new(0),
            }
        }
    }

    #[async_trait]
    impl RecordingRunner for DurationCapturingRunner {
        async fn run_once(
            &self,
            _config: Config,
            duration_ms: u32,
            _include_partials: bool,
            stop_rx: oneshot::Receiver<()>,
            _hud: Option<crate::hud::SharedHudSink>,
        ) -> Result<RecordingPayload, SessionError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            self.durations.lock().await.push(duration_ms);
            let _ = stop_rx.await;
            Ok(self.payload.clone())
        }
    }

    struct PanicAfterStopRunner;

    #[async_trait]
    impl RecordingRunner for PanicAfterStopRunner {
        async fn run_once(
            &self,
            _config: Config,
            _duration_ms: u32,
            _include_partials: bool,
            stop_rx: oneshot::Receiver<()>,
            _hud: Option<crate::hud::SharedHudSink>,
        ) -> Result<RecordingPayload, SessionError> {
            let _ = stop_rx.await;
            panic!("recording task panic after stop");
        }
    }

    #[derive(Default)]
    struct FakeInjector {
        inserted: StdMutex<Vec<String>>,
    }

    impl TextInjector for FakeInjector {
        fn insert(
            &self,
            text: &str,
            _output: &OutputConfig,
        ) -> Result<InjectionOutcome, InjectionError> {
            self.inserted.lock().unwrap().push(text.to_string());
            Ok(InjectionOutcome::Injected)
        }
    }

    #[derive(Default)]
    struct FakeHudSink {
        events: StdMutex<Vec<crate::hud::HudEvent>>,
    }

    impl crate::hud::HudSink for FakeHudSink {
        fn send(&self, event: crate::hud::HudEvent) -> Result<(), crate::hud::HudError> {
            self.events.lock().unwrap().push(event);
            Ok(())
        }
    }

    #[tokio::test]
    async fn recording_start_stop_sends_hud_state_sequence() {
        let runner = Arc::new(StopAwareRunner::new());
        let injector = Arc::new(FakeInjector::default());
        let hud = Arc::new(FakeHudSink::default());
        let orch = Orchestrator::with_runner_injector_and_hud(
            Config::default(),
            runner,
            injector,
            hud.clone(),
        );

        assert_eq!(orch.handle(Request::RecordingStart).await, Response::Ok);
        let _ = orch.handle(Request::RecordingStop).await;

        assert_eq!(
            *hud.events.lock().unwrap(),
            vec![
                crate::hud::HudEvent::state(crate::hud::HudState::Recording),
                crate::hud::HudEvent::state(crate::hud::HudState::Transcribing),
                crate::hud::HudEvent::state(crate::hud::HudState::Hidden),
            ]
        );
    }

    #[tokio::test]
    async fn recording_start_uses_long_default_and_hud_stays_visible_until_stop() {
        let runner = Arc::new(DurationCapturingRunner::new());
        let injector = Arc::new(FakeInjector::default());
        let hud = Arc::new(FakeHudSink::default());
        let orch = Orchestrator::with_runner_injector_and_hud(
            Config::default(),
            runner.clone(),
            injector,
            hud.clone(),
        );

        assert_eq!(orch.handle(Request::RecordingStart).await, Response::Ok);

        for _ in 0..10 {
            if !runner.durations.lock().await.is_empty() {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }

        assert_eq!(*runner.durations.lock().await, vec![300_000]);
        match orch.handle(Request::Status).await {
            Response::Status(status) => assert_eq!(status.state, "recording"),
            other => panic!("expected recording Status, got {other:?}"),
        }
        assert_eq!(
            *hud.events.lock().unwrap(),
            vec![crate::hud::HudEvent::state(crate::hud::HudState::Recording)]
        );

        match orch.handle(Request::RecordingStop).await {
            Response::RecordingResult { text, logid, .. } => {
                assert_eq!(text, "duration final");
                assert_eq!(logid.as_deref(), Some("duration-log"));
            }
            other => panic!("expected RecordingResult, got {other:?}"),
        }

        assert_eq!(
            *hud.events.lock().unwrap(),
            vec![
                crate::hud::HudEvent::state(crate::hud::HudState::Recording),
                crate::hud::HudEvent::state(crate::hud::HudState::Transcribing),
                crate::hud::HudEvent::state(crate::hud::HudState::Hidden),
            ]
        );
        assert_eq!(runner.calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn recording_stop_task_drop_sends_hud_error_after_transcribing() {
        let runner = Arc::new(PanicAfterStopRunner);
        let injector = Arc::new(FakeInjector::default());
        let hud = Arc::new(FakeHudSink::default());
        let orch = Orchestrator::with_runner_injector_and_hud(
            Config::default(),
            runner,
            injector,
            hud.clone(),
        );

        assert_eq!(orch.handle(Request::RecordingStart).await, Response::Ok);
        match orch.handle(Request::RecordingStop).await {
            Response::Error { message } => assert_eq!(message, "recording task stopped"),
            other => panic!("expected stopped Error, got {other:?}"),
        }

        assert_eq!(
            *hud.events.lock().unwrap(),
            vec![
                crate::hud::HudEvent::state(crate::hud::HudState::Recording),
                crate::hud::HudEvent::state(crate::hud::HudState::Transcribing),
                crate::hud::HudEvent::error("recording task stopped"),
            ]
        );
    }

    #[tokio::test]
    async fn recording_once_does_not_show_hud() {
        let runner = Arc::new(FakeRecordingRunner::new(std::time::Duration::ZERO));
        let injector = Arc::new(FakeInjector::default());
        let hud = Arc::new(FakeHudSink::default());
        let orch = Orchestrator::with_runner_injector_and_hud(
            Config::default(),
            runner,
            injector,
            hud.clone(),
        );

        let _ = orch
            .handle(Request::RecordingOnce {
                duration_ms: 100,
                include_partials: false,
            })
            .await;
        assert!(hud.events.lock().unwrap().is_empty());
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

    #[tokio::test]
    async fn recording_start_then_stop_returns_result_and_injects_text() {
        let runner = Arc::new(StopAwareRunner::new());
        let injector = Arc::new(FakeInjector::default());
        let orch = Orchestrator::with_runner_and_injector(
            Config::default(),
            runner.clone(),
            injector.clone(),
        );

        assert_eq!(orch.handle(Request::RecordingStart).await, Response::Ok);
        match orch.handle(Request::Status).await {
            Response::Status(status) => assert_eq!(status.state, "recording"),
            other => panic!("expected Status, got {other:?}"),
        }

        let stopped = orch.handle(Request::RecordingStop).await;
        match stopped {
            Response::RecordingResult { text, logid, .. } => {
                assert_eq!(text, "toggle final");
                assert_eq!(logid.as_deref(), Some("toggle-log"));
            }
            other => panic!("expected RecordingResult, got {other:?}"),
        }

        assert_eq!(*injector.inserted.lock().unwrap(), vec!["toggle final"]);
        assert_eq!(runner.calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn recording_start_rejects_when_already_recording() {
        let runner = Arc::new(StopAwareRunner::new());
        let injector = Arc::new(FakeInjector::default());
        let orch = Orchestrator::with_runner_and_injector(Config::default(), runner, injector);

        assert_eq!(orch.handle(Request::RecordingStart).await, Response::Ok);
        match orch.handle(Request::RecordingStart).await {
            Response::Error { message } => assert!(message.contains("busy: state=Recording")),
            other => panic!("expected busy Error, got {other:?}"),
        }
        let _ = orch.handle(Request::RecordingStop).await;
    }

    #[tokio::test]
    async fn recording_stop_requires_active_recording() {
        let runner = Arc::new(StopAwareRunner::new());
        let injector = Arc::new(FakeInjector::default());
        let orch = Orchestrator::with_runner_and_injector(Config::default(), runner, injector);

        match orch.handle(Request::RecordingStop).await {
            Response::Error { message } => assert!(message.contains("not recording")),
            other => panic!("expected not-recording Error, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn hotkey_stop_does_not_wait_for_finalization_and_ignores_pending_toggle() {
        let runner = Arc::new(StopAwareRunner::with_delay(
            std::time::Duration::from_millis(100),
        ));
        let injector = Arc::new(FakeInjector::default());
        let orch = Orchestrator::with_runner_and_injector(
            Config::default(),
            runner.clone(),
            injector.clone(),
        );

        assert_eq!(orch.handle_hotkey_toggle().await, Response::Ok);
        let started = std::time::Instant::now();
        assert_eq!(orch.handle_hotkey_toggle().await, Response::Ok);
        assert!(started.elapsed() < std::time::Duration::from_millis(50));
        match orch.handle(Request::Status).await {
            Response::Status(status) => assert_eq!(status.state, "transcribing"),
            other => panic!("expected Status, got {other:?}"),
        }

        assert_eq!(orch.handle_hotkey_toggle().await, Response::Ok);
        tokio::time::sleep(std::time::Duration::from_millis(150)).await;

        match orch.handle(Request::Status).await {
            Response::Status(status) => assert_eq!(status.state, "idle"),
            other => panic!("expected Status, got {other:?}"),
        }
        assert_eq!(runner.calls.load(Ordering::SeqCst), 1);
        assert_eq!(*injector.inserted.lock().unwrap(), vec!["toggle final"]);
    }
}
