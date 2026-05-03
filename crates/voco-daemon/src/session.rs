use std::time::{Duration, Instant};

use tokio::sync::{mpsc, oneshot};
use voco_asr::{AsrBackend, AsrError};
use voco_config::Config;
use voco_ipc::protocol::{PartialSnapshot, Segment};

#[derive(Debug, Clone)]
pub struct RecordingPayload {
    pub text: String,
    pub segments: Vec<Segment>,
    pub partials: Vec<PartialSnapshot>,
    pub logid: Option<String>,
    pub first_partial_ms: Option<u64>,
    pub total_latency_ms: u64,
    pub error_hint: Option<String>,
}

pub struct RecordingSession {
    pcm: PcmSource,
    backend: Box<dyn AsrBackend>,
    started_at: Instant,
    first_partial_at: Option<Instant>,
    last_partial_text: Option<String>,
    partials: Vec<PartialSnapshot>,
}

enum PcmSource {
    Audio(voco_audio::Session),
    Receiver(mpsc::Receiver<Vec<i16>>),
}

impl PcmSource {
    async fn recv(&mut self) -> Option<Vec<i16>> {
        match self {
            PcmSource::Audio(session) => session.pcm_rx.recv().await,
            PcmSource::Receiver(rx) => rx.recv().await,
        }
    }
}

impl RecordingSession {
    pub fn start_from_config(config: &Config) -> Result<Self, SessionError> {
        let audio_session = voco_audio::AudioCapture::start()?;
        let backend = voco_asr::build_backend(config)?;
        Ok(Self {
            pcm: PcmSource::Audio(audio_session),
            backend,
            started_at: Instant::now(),
            first_partial_at: None,
            last_partial_text: None,
            partials: Vec::new(),
        })
    }

    pub fn from_parts(pcm_rx: mpsc::Receiver<Vec<i16>>, backend: Box<dyn AsrBackend>) -> Self {
        Self {
            pcm: PcmSource::Receiver(pcm_rx),
            backend,
            started_at: Instant::now(),
            first_partial_at: None,
            last_partial_text: None,
            partials: Vec::new(),
        }
    }

    pub async fn run(
        mut self,
        duration_ms: u32,
        include_partials: bool,
        mut stop_rx: oneshot::Receiver<()>,
    ) -> Result<RecordingPayload, SessionError> {
        self.backend.start().await?;
        let timeout = tokio::time::sleep(Duration::from_millis(duration_ms as u64));
        tokio::pin!(timeout);
        let terminal = loop {
            tokio::select! {
                frame = self.pcm.recv() => {
                    let Some(frame) = frame else {
                        break TerminalReason::AudioEnded;
                    };
                    match self.backend.feed(&frame).await {
                        Ok(Some(partial)) => self.record_partial(partial, include_partials),
                        Ok(None) => {}
                        Err(err) => {
                            break TerminalReason::BackendError(err.to_string());
                        }
                    }
                }
                _ = &mut stop_rx => {
                    return Err(SessionError::Aborted);
                }
                _ = &mut timeout => {
                    break TerminalReason::Timeout;
                }
            }
        };

        if let TerminalReason::BackendError(message) = &terminal {
            return Ok(self.partial_payload(Some(message.clone())));
        }

        let final_result = match self.backend.stop().await {
            Ok(final_result) => final_result,
            Err(err) => {
                return Ok(self.partial_payload(Some(err.to_string())));
            }
        };
        let finished_at = Instant::now();
        Ok(RecordingPayload {
            text: final_result.text,
            segments: final_result
                .segments
                .into_iter()
                .map(|segment| Segment {
                    text: segment.text,
                    start_ms: segment.start_ms,
                    end_ms: segment.end_ms,
                    definite: segment.definite,
                })
                .collect(),
            partials: self.partials,
            logid: final_result.logid,
            first_partial_ms: self
                .first_partial_at
                .map(|at| elapsed_ms(self.started_at, at)),
            total_latency_ms: elapsed_ms(self.started_at, finished_at),
            error_hint: terminal.error_hint(),
        })
    }

    fn record_partial(&mut self, partial: voco_asr::Partial, include_partials: bool) {
        let at = Instant::now();
        if self.first_partial_at.is_none() {
            self.first_partial_at = Some(at);
        }
        self.last_partial_text = Some(partial.text.clone());
        if include_partials {
            self.partials.push(PartialSnapshot {
                at_ms: elapsed_ms(self.started_at, at),
                text: partial.text,
                stable_prefix_len: partial.stable_prefix_len,
            });
        }
    }

    fn partial_payload(self, error_hint: Option<String>) -> RecordingPayload {
        let finished_at = Instant::now();
        let text = self.last_partial_text.clone().unwrap_or_default();
        let end_ms = elapsed_ms(self.started_at, finished_at) as u32;
        let segments = if text.is_empty() {
            vec![]
        } else {
            vec![Segment {
                text: text.clone(),
                start_ms: 0,
                end_ms,
                definite: false,
            }]
        };
        RecordingPayload {
            text,
            segments,
            partials: self.partials,
            logid: None,
            first_partial_ms: self
                .first_partial_at
                .map(|at| elapsed_ms(self.started_at, at)),
            total_latency_ms: elapsed_ms(self.started_at, finished_at),
            error_hint,
        }
    }
}

enum TerminalReason {
    Timeout,
    AudioEnded,
    BackendError(String),
}

impl TerminalReason {
    fn error_hint(self) -> Option<String> {
        match self {
            Self::Timeout => Some("max duration reached".into()),
            Self::AudioEnded => Some("audio input ended".into()),
            Self::BackendError(message) => Some(message),
        }
    }
}

fn elapsed_ms(start: Instant, end: Instant) -> u64 {
    end.saturating_duration_since(start).as_millis() as u64
}

#[derive(Debug, thiserror::Error)]
pub enum SessionError {
    #[error("backend: {0}")]
    Backend(#[from] AsrError),

    #[error("audio: {0}")]
    Audio(#[from] voco_audio::AudioError),

    #[error("recording runtime: {0}")]
    Runtime(String),

    #[error("recording worker stopped before returning a result")]
    WorkerStopped,

    #[error("recording aborted")]
    Aborted,
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use voco_asr::{Final, Partial, Segment as AsrSegment};

    #[derive(Debug, Clone, Copy)]
    enum MockFailure {
        None,
        FeedOnCall(usize),
    }

    struct MockBackend {
        feed_calls: usize,
        failure: MockFailure,
    }

    #[async_trait]
    impl AsrBackend for MockBackend {
        async fn start(&mut self) -> Result<(), AsrError> {
            Ok(())
        }

        async fn feed(&mut self, _pcm: &[i16]) -> Result<Option<Partial>, AsrError> {
            self.feed_calls += 1;
            if matches!(self.failure, MockFailure::FeedOnCall(n) if n == self.feed_calls) {
                return Err(AsrError::Transport("mock feed disconnected".into()));
            }
            Ok(Some(Partial {
                text: format!("partial-{}", self.feed_calls),
                stable_prefix_len: self.feed_calls,
            }))
        }

        async fn stop(&mut self) -> Result<Final, AsrError> {
            Ok(Final {
                text: "final text".into(),
                segments: vec![AsrSegment {
                    text: "final text".into(),
                    start_ms: 0,
                    end_ms: 420,
                    definite: true,
                }],
                logid: Some("log-123".into()),
            })
        }

        fn name(&self) -> &'static str {
            "mock"
        }
    }

    #[tokio::test]
    async fn run_feeds_pcm_collects_partials_and_final() {
        let (pcm_tx, pcm_rx) = mpsc::channel(4);
        pcm_tx.send(vec![1, 2, 3]).await.unwrap();
        pcm_tx.send(vec![4, 5, 6]).await.unwrap();
        drop(pcm_tx);
        let (_stop_tx, stop_rx) = oneshot::channel();
        let session = RecordingSession::from_parts(
            pcm_rx,
            Box::new(MockBackend {
                feed_calls: 0,
                failure: MockFailure::None,
            }),
        );

        let payload = session
            .run(1_000, true, stop_rx)
            .await
            .expect("session succeeds");

        assert_eq!(payload.text, "final text");
        assert_eq!(payload.logid.as_deref(), Some("log-123"));
        assert_eq!(payload.segments.len(), 1);
        assert_eq!(payload.segments[0].text, "final text");
        assert_eq!(payload.partials.len(), 2);
        assert_eq!(payload.partials[0].text, "partial-1");
        assert_eq!(payload.partials[1].stable_prefix_len, 2);
        assert!(payload.first_partial_ms.is_some());
        assert!(payload.total_latency_ms < 1_000);
        assert_eq!(payload.error_hint.as_deref(), Some("audio input ended"));
    }

    #[tokio::test]
    async fn run_omits_partials_when_not_requested() {
        let (pcm_tx, pcm_rx) = mpsc::channel(4);
        pcm_tx.send(vec![1, 2, 3]).await.unwrap();
        drop(pcm_tx);
        let (_stop_tx, stop_rx) = oneshot::channel();
        let session = RecordingSession::from_parts(
            pcm_rx,
            Box::new(MockBackend {
                feed_calls: 0,
                failure: MockFailure::None,
            }),
        );

        let payload = session.run(1_000, false, stop_rx).await.unwrap();

        assert!(payload.partials.is_empty());
        assert!(payload.first_partial_ms.is_some());
    }

    #[tokio::test]
    async fn timeout_fires_returns_final_with_partials_so_far() {
        let (pcm_tx, pcm_rx) = mpsc::channel(4);
        pcm_tx.send(vec![1, 2, 3]).await.unwrap();
        let (_stop_tx, stop_rx) = oneshot::channel();
        let session = RecordingSession::from_parts(
            pcm_rx,
            Box::new(MockBackend {
                feed_calls: 0,
                failure: MockFailure::None,
            }),
        );

        let payload = session.run(1, true, stop_rx).await.unwrap();

        assert_eq!(payload.text, "final text");
        assert_eq!(payload.partials.len(), 1);
        assert_eq!(payload.error_hint.as_deref(), Some("max duration reached"));
    }

    #[tokio::test]
    async fn pcm_channel_close_treats_as_eof() {
        let (pcm_tx, pcm_rx) = mpsc::channel(4);
        drop(pcm_tx);
        let (_stop_tx, stop_rx) = oneshot::channel();
        let session = RecordingSession::from_parts(
            pcm_rx,
            Box::new(MockBackend {
                feed_calls: 0,
                failure: MockFailure::None,
            }),
        );

        let payload = session.run(1_000, true, stop_rx).await.unwrap();

        assert_eq!(payload.text, "final text");
        assert!(payload.partials.is_empty());
        assert_eq!(payload.error_hint.as_deref(), Some("audio input ended"));
    }

    #[tokio::test]
    async fn backend_error_propagates_with_partials_stitched() {
        let (pcm_tx, pcm_rx) = mpsc::channel(4);
        pcm_tx.send(vec![1, 2, 3]).await.unwrap();
        pcm_tx.send(vec![4, 5, 6]).await.unwrap();
        let (_stop_tx, stop_rx) = oneshot::channel();
        let session = RecordingSession::from_parts(
            pcm_rx,
            Box::new(MockBackend {
                feed_calls: 0,
                failure: MockFailure::FeedOnCall(2),
            }),
        );

        let payload = session.run(1_000, true, stop_rx).await.unwrap();

        assert_eq!(payload.text, "partial-1");
        assert_eq!(payload.partials.len(), 1);
        assert!(payload
            .error_hint
            .as_deref()
            .unwrap()
            .contains("mock feed disconnected"));
    }

    #[tokio::test]
    async fn daemon_shutdown_aborts_session() {
        let (pcm_tx, pcm_rx) = mpsc::channel(4);
        pcm_tx.send(vec![1, 2, 3]).await.unwrap();
        let (stop_tx, stop_rx) = oneshot::channel();
        let session = RecordingSession::from_parts(
            pcm_rx,
            Box::new(MockBackend {
                feed_calls: 0,
                failure: MockFailure::None,
            }),
        );

        stop_tx.send(()).unwrap();
        let err = session.run(1_000, true, stop_rx).await.unwrap_err();

        assert!(matches!(err, SessionError::Aborted));
    }
}
