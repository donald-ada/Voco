//! Voco ASR — `AsrBackend` trait + Doubao (Volcengine) implementation.
//!
//! Phase 2 ships the protocol layer + sherpa stub. The actual end-to-end
//! recording session lands in Phase 3 once `voco-audio` is wired up; this
//! crate just delivers a self-contained backend driver.

pub mod doubao;
pub mod error;
pub mod sherpa;

pub use error::AsrError;

use async_trait::async_trait;
use voco_config::Config;

/// Streaming ASR backend. The orchestrator drives `start → feed* → stop`.
#[async_trait]
pub trait AsrBackend: Send + Sync {
    /// Establish/refresh the connection (open WS, load model). Must be safe
    /// to call multiple times — `stop` returns the backend to the same state.
    async fn start(&mut self) -> Result<(), AsrError>;

    /// Push 16kHz mono PCM s16le audio. Returns `Some(Partial)` when a new
    /// partial recognition delta is available, else `None`. Must not block
    /// longer than the audio frame duration to keep the pipeline real-time.
    async fn feed(&mut self, pcm: &[i16]) -> Result<Option<Partial>, AsrError>;

    /// Drain the stream and return the final transcription. The backend is
    /// ready to `start()` again afterwards.
    async fn stop(&mut self) -> Result<Final, AsrError>;

    fn name(&self) -> &'static str;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Partial {
    pub text: String,
    /// Number of leading characters guaranteed not to change in subsequent
    /// partials. Lets the orchestrator stream stable text without flicker.
    pub stable_prefix_len: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Final {
    pub text: String,
    pub segments: Vec<Segment>,
    /// Volcengine X-Tt-Logid header from the WS handshake. Useful for
    /// support tickets — surfaced in `voco status` recent_errors.
    pub logid: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Segment {
    pub text: String,
    pub start_ms: u32,
    pub end_ms: u32,
    pub definite: bool,
}

/// Construct the configured backend. Phase 2: only Doubao implementation
/// builds; Sherpa returns `NotImplemented` from `start()`.
pub fn build_backend(cfg: &Config) -> Result<Box<dyn AsrBackend>, AsrError> {
    use voco_config::BackendChoice;
    match cfg.backend {
        BackendChoice::Doubao => {
            let creds = cfg
                .doubao
                .as_ref()
                .ok_or_else(|| AsrError::Auth("[doubao] section missing".into()))?;
            Ok(Box::new(doubao::DoubaoBackend::new(creds.clone())))
        }
        BackendChoice::Sherpa => Ok(Box::new(sherpa::SherpaBackend::new())),
    }
}
