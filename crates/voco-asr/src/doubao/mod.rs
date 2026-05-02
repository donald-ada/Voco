//! Doubao (Volcengine) streaming ASR client. Handles the full lifecycle:
//! WS handshake (with auth), full client request, audio frame stream,
//! last-packet, server response parsing, final stitching.

pub mod auth;
pub mod codec;
pub mod protocol;
pub mod types;
pub mod ws;

use crate::{AsrBackend, AsrError, Final, Partial, Segment};
use async_trait::async_trait;
use protocol::{MsgFlags, ServerFrame};
use std::collections::HashMap;
use tracing::debug;
use voco_config::DoubaoCreds;

/// Default frame size — 200ms of 16kHz mono i16 = 3200 samples.
/// Volcengine doc recommends 100-200ms, with 200ms optimal for the
/// bidirectional-stream optimized variant.
pub const FRAME_SAMPLES: usize = 3200;

pub struct DoubaoBackend {
    creds: DoubaoCreds,
    stream: Option<ws::WsStream>,
    /// Re-emitted on `Final.logid`. Useful for support tickets.
    logid: Option<String>,
    /// PCM samples accumulated across `feed()` calls; flushed in 200ms chunks.
    pcm_buffer: Vec<i16>,
    /// Definite utterances received so far. Keyed by start_time so a
    /// re-issued partial replaces the prior one cleanly.
    utterances: HashMap<u32, Segment>,
    /// Latest non-definite text (the cursor). Reset whenever a new
    /// definite chunk arrives.
    pending_text: String,
    last_partial: String,
}

impl DoubaoBackend {
    pub fn new(creds: DoubaoCreds) -> Self {
        Self {
            creds,
            stream: None,
            logid: None,
            pcm_buffer: Vec::with_capacity(FRAME_SAMPLES * 2),
            utterances: HashMap::new(),
            pending_text: String::new(),
            last_partial: String::new(),
        }
    }

    pub fn creds(&self) -> &DoubaoCreds {
        &self.creds
    }

    pub fn logid(&self) -> Option<&str> {
        self.logid.as_deref()
    }

    fn assemble_text(&self) -> String {
        let mut segs: Vec<&Segment> = self.utterances.values().collect();
        segs.sort_by_key(|s| s.start_ms);
        let mut out = String::new();
        for s in segs {
            out.push_str(&s.text);
        }
        out.push_str(&self.pending_text);
        out
    }

    fn ingest_response(&mut self, payload: &[u8]) -> Result<Option<Partial>, AsrError> {
        let resp: types::ServerResponse = serde_json::from_slice(payload)
            .map_err(|e| AsrError::Decode(format!("server json: {e}")))?;

        let result = match resp.result {
            None => return Ok(None),
            Some(r) => r,
        };

        // Reset pending text; we'll rebuild it from non-definite utterances.
        self.pending_text.clear();

        for u in result.utterances {
            let seg = Segment {
                text: u.text.clone(),
                start_ms: u.start_time,
                end_ms: u.end_time,
                definite: u.definite,
            };
            if u.definite {
                self.utterances.insert(u.start_time, seg);
            } else {
                self.pending_text.push_str(&u.text);
            }
        }

        let new_text = self.assemble_text();
        if new_text == self.last_partial {
            return Ok(None);
        }
        let stable_prefix_len = common_prefix_len(&self.last_partial, &new_text);
        self.last_partial = new_text.clone();
        Ok(Some(Partial {
            text: new_text,
            stable_prefix_len,
        }))
    }

    /// Send buffered PCM as audio frames (gzipped). Each chunk is FRAME_SAMPLES
    /// = 200ms. `force` flushes any short tail.
    async fn flush_audio(&mut self, force_tail: bool, last: bool) -> Result<(), AsrError> {
        let Some(stream) = self.stream.as_mut() else {
            return Err(AsrError::Transport("session not started".into()));
        };

        let chunk_size = FRAME_SAMPLES;
        while self.pcm_buffer.len() >= chunk_size {
            let chunk: Vec<i16> = self.pcm_buffer.drain(..chunk_size).collect();
            let bytes = pcm_to_bytes(&chunk);
            let gz = codec::gzip(&bytes)?;
            let frame = protocol::build_audio_frame(&gz, false);
            ws::send_binary(stream, frame).await?;
        }

        if (force_tail && !self.pcm_buffer.is_empty()) || (last && !self.pcm_buffer.is_empty()) {
            let tail: Vec<i16> = std::mem::take(&mut self.pcm_buffer);
            let bytes = pcm_to_bytes(&tail);
            let gz = codec::gzip(&bytes)?;
            let frame = protocol::build_audio_frame(&gz, last);
            ws::send_binary(stream, frame).await?;
            return Ok(());
        }

        if last {
            // No tail data → still need to signal end-of-stream.
            let gz = codec::gzip(&[])?;
            let frame = protocol::build_audio_frame(&gz, true);
            ws::send_binary(stream, frame).await?;
        }
        Ok(())
    }

    /// Drain server messages until the last-packet flag arrives or the
    /// stream closes. Returns the last partial seen (if any).
    async fn drain_until_final(&mut self) -> Result<Option<Partial>, AsrError> {
        let mut last_partial = None;
        while let Some(stream) = self.stream.as_mut() {
            let raw = ws::recv_binary(stream).await?;
            let Some(raw) = raw else { break };
            match protocol::parse_server_frame(&raw)? {
                ServerFrame::Error { code, message } => {
                    return Err(AsrError::from_server_code(code, message));
                }
                ServerFrame::Response { flags, payload, .. } => {
                    if let Some(p) = self.ingest_response(&payload)? {
                        last_partial = Some(p);
                    }
                    if flags.is_last() || matches!(flags, MsgFlags::LastWithSequence) {
                        break;
                    }
                }
            }
        }
        Ok(last_partial)
    }
}

#[async_trait]
impl AsrBackend for DoubaoBackend {
    async fn start(&mut self) -> Result<(), AsrError> {
        let auth = auth::DoubaoAuth::from_creds(&self.creds)?;
        let (mut stream, logid) = ws::connect(&self.creds.endpoint, &auth).await?;
        debug!(?logid, "doubao ws upgraded");
        self.logid = logid;

        // Send the FullClientRequest right after connect.
        let payload = types::FullClientRequest::voco_defaults();
        let json = serde_json::to_vec(&payload)
            .map_err(|e| AsrError::Decode(format!("encode FullClientRequest: {e}")))?;
        let gz = codec::gzip(&json)?;
        let frame = protocol::build_full_client_request_frame(&gz);
        ws::send_binary(&mut stream, frame).await?;

        // Volcengine acknowledges the FullClientRequest with one server frame
        // (often empty). Read it to surface auth/format errors fast — if
        // nothing comes within the WS read budget, fall through; the next
        // poll will pick it up alongside the audio frames.
        self.stream = Some(stream);
        Ok(())
    }

    async fn feed(&mut self, pcm: &[i16]) -> Result<Option<Partial>, AsrError> {
        if self.stream.is_none() {
            return Err(AsrError::Transport("feed before start".into()));
        }
        self.pcm_buffer.extend_from_slice(pcm);
        self.flush_audio(false, false).await?;

        // Non-blocking peek: 1ms timeout — if a server frame is queued we
        // ingest it and return the new partial, otherwise yield None.
        let stream = self.stream.as_mut().unwrap();
        match tokio::time::timeout(std::time::Duration::from_millis(1), ws::recv_binary(stream))
            .await
        {
            Err(_) => Ok(None), // no frame within the budget
            Ok(Ok(None)) => Ok(None),
            Ok(Err(e)) => Err(e),
            Ok(Ok(Some(raw))) => match protocol::parse_server_frame(&raw)? {
                ServerFrame::Response { payload, .. } => self.ingest_response(&payload),
                ServerFrame::Error { code, message } => {
                    Err(AsrError::from_server_code(code, message))
                }
            },
        }
    }

    async fn stop(&mut self) -> Result<Final, AsrError> {
        if self.stream.is_none() {
            return Err(AsrError::Transport("stop before start".into()));
        }
        // Flush pending audio + send last packet.
        self.flush_audio(true, true).await?;
        // Drain server messages until last-packet or close.
        let _ = self.drain_until_final().await?;

        // Hand the stream off to a graceful close in the background.
        if let Some(stream) = self.stream.take() {
            ws::close(stream).await;
        }

        let mut segs: Vec<Segment> = self.utterances.drain().map(|(_, s)| s).collect();
        segs.sort_by_key(|s| s.start_ms);
        let text = segs.iter().map(|s| s.text.clone()).collect::<String>();
        let logid = self.logid.clone();

        // Reset session state so start() works again.
        self.pending_text.clear();
        self.last_partial.clear();
        self.pcm_buffer.clear();

        Ok(Final {
            text,
            segments: segs,
            logid,
        })
    }

    fn name(&self) -> &'static str {
        "doubao"
    }
}

fn pcm_to_bytes(samples: &[i16]) -> Vec<u8> {
    let mut out = Vec::with_capacity(samples.len() * 2);
    for s in samples {
        out.extend_from_slice(&s.to_le_bytes());
    }
    out
}

fn common_prefix_len(a: &str, b: &str) -> usize {
    let mut n = 0;
    for (ca, cb) in a.chars().zip(b.chars()) {
        if ca == cb {
            n += ca.len_utf8();
        } else {
            break;
        }
    }
    n
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
        assert!(b.stream.is_none());
        assert_eq!(b.name(), "doubao");
    }

    #[test]
    fn frame_samples_matches_200ms_at_16khz() {
        assert_eq!(FRAME_SAMPLES, 3200);
    }

    #[test]
    fn pcm_to_bytes_is_le() {
        let samples: &[i16] = &[1, 0x100, -1];
        let b = pcm_to_bytes(samples);
        assert_eq!(b, vec![0x01, 0x00, 0x00, 0x01, 0xFF, 0xFF]);
    }

    #[test]
    fn common_prefix_handles_unicode() {
        assert_eq!(common_prefix_len("你好世界", "你好朋友"), 6); // "你好" = 6 bytes
        assert_eq!(common_prefix_len("abc", "abd"), 2);
        assert_eq!(common_prefix_len("", "x"), 0);
    }

    #[test]
    fn ingest_definite_then_partial_returns_partial() {
        let mut b = DoubaoBackend::new(creds());
        let r1 = r#"{"result":{"text":"","utterances":[
            {"text":"你好","start_time":0,"end_time":500,"definite":true}
        ]}}"#;
        let p1 = b.ingest_response(r1.as_bytes()).unwrap().unwrap();
        assert_eq!(p1.text, "你好");

        let r2 = r#"{"result":{"text":"","utterances":[
            {"text":"你好","start_time":0,"end_time":500,"definite":true},
            {"text":"世","start_time":500,"end_time":700,"definite":false}
        ]}}"#;
        let p2 = b.ingest_response(r2.as_bytes()).unwrap().unwrap();
        assert_eq!(p2.text, "你好世");
        // "你好" is 6 bytes — that's the stable prefix.
        assert_eq!(p2.stable_prefix_len, 6);
    }

    #[test]
    fn ingest_same_text_returns_none() {
        let mut b = DoubaoBackend::new(creds());
        let r = r#"{"result":{"text":"","utterances":[
            {"text":"hi","start_time":0,"end_time":100,"definite":true}
        ]}}"#;
        let _ = b.ingest_response(r.as_bytes()).unwrap();
        // Re-ingesting the same payload should not emit a fresh partial.
        assert!(b.ingest_response(r.as_bytes()).unwrap().is_none());
    }

    #[test]
    fn ingest_partial_replaced_by_definite() {
        let mut b = DoubaoBackend::new(creds());
        // First: a non-definite utterance.
        let r1 = r#"{"result":{"text":"","utterances":[
            {"text":"hello","start_time":0,"end_time":500,"definite":false}
        ]}}"#;
        let p1 = b.ingest_response(r1.as_bytes()).unwrap().unwrap();
        assert_eq!(p1.text, "hello");
        // Second: same range now definite.
        let r2 = r#"{"result":{"text":"","utterances":[
            {"text":"hello, world","start_time":0,"end_time":500,"definite":true}
        ]}}"#;
        let p2 = b.ingest_response(r2.as_bytes()).unwrap().unwrap();
        assert_eq!(p2.text, "hello, world");
    }
}
