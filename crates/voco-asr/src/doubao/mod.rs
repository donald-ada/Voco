//! Doubao (Volcengine) streaming ASR client. Phase 2 commit A delivers the
//! protocol layer (frame builders, gzip, response parser, auth headers).
//! Commit B wires `tokio_tungstenite` to actually drive a session.

pub mod auth;
pub mod codec;
pub mod protocol;
pub mod types;

use crate::{AsrBackend, AsrError, Final, Partial};
use async_trait::async_trait;
use voco_config::DoubaoCreds;

/// Default frame size — 200ms of 16kHz mono i16 = 3200 samples.
/// Volcengine doc recommends 100-200ms, with 200ms optimal for the
/// bidirectional-stream optimized variant.
pub const FRAME_SAMPLES: usize = 3200;

pub struct DoubaoBackend {
    creds: DoubaoCreds,
    /// Phase 2 commit A: this is the only state. Commit B adds the WS
    /// connection, send/recv tasks, and the partial-buffering channel.
    state: SessionState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SessionState {
    Idle,
    Connected,
    Closed,
}

impl DoubaoBackend {
    pub fn new(creds: DoubaoCreds) -> Self {
        Self {
            creds,
            state: SessionState::Idle,
        }
    }

    pub fn creds(&self) -> &DoubaoCreds {
        &self.creds
    }
}

#[async_trait]
impl AsrBackend for DoubaoBackend {
    async fn start(&mut self) -> Result<(), AsrError> {
        // Commit A: validate auth shape only — the real WS dial lands in
        // commit B. This already lets `doctor` skip cleanly when creds
        // are missing.
        let _ = auth::DoubaoAuth::from_creds(&self.creds)?;
        self.state = SessionState::Connected;
        Err(AsrError::NotImplemented(
            "DoubaoBackend transport layer lands in commit B",
        ))
    }

    async fn feed(&mut self, _pcm: &[i16]) -> Result<Option<Partial>, AsrError> {
        Err(AsrError::NotImplemented("DoubaoBackend.feed (commit B)"))
    }

    async fn stop(&mut self) -> Result<Final, AsrError> {
        self.state = SessionState::Closed;
        Err(AsrError::NotImplemented("DoubaoBackend.stop (commit B)"))
    }

    fn name(&self) -> &'static str {
        "doubao"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn creds() -> DoubaoCreds {
        DoubaoCreds {
            app_id: "APP-1".into(),
            access_token: "TOK".into(),
            ..Default::default()
        }
    }

    #[test]
    fn new_starts_idle() {
        let b = DoubaoBackend::new(creds());
        assert_eq!(b.state, SessionState::Idle);
        assert_eq!(b.name(), "doubao");
    }

    #[test]
    fn frame_samples_matches_200ms_at_16khz() {
        // 16000 Hz × 0.2 s = 3200 samples. If you change the rate, fix this too.
        assert_eq!(FRAME_SAMPLES, 3200);
    }
}
