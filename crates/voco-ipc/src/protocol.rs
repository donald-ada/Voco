//! Wire protocol for the Voco daemon control channel.
//!
//! Frame: `[length: u32 BE][JSON body]`. JSON body is an [`Envelope`].
//! Wraps either a [`Request`] or [`Response`] in `payload`.

use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

pub const PROTOCOL_VERSION: u32 = 2;
pub const MAX_FRAME_BYTES: u32 = 1024 * 1024; // 1 MiB; status payloads are tiny

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Envelope {
    pub protocol_version: u32,
    pub kind: EnvelopeKind,
    pub id: Uuid,
    pub payload: serde_json::Value,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum EnvelopeKind {
    Request,
    Response,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "method", rename_all = "snake_case")]
pub enum Request {
    Status,
    ReloadConfig,
    DaemonShutdown,
    RecordingStart,
    RecordingStop,
    /// Returns the daemon's current effective config as JSON. Phase 2:
    /// readers verify reload took effect; later phases can introspect.
    DumpConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Response {
    Ok,
    /// Phase 2 reload result: succeeded, but some changes only take effect
    /// after `voco daemon restart` (backend swap, hotkey, log path, etc.).
    OkWithWarnings {
        warnings: Vec<String>,
    },
    Status(StatusInfo),
    Config(serde_json::Value),
    Error {
        message: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct StatusInfo {
    pub state: String,
    pub backend: String,
    pub backend_in_use: String,
    pub uptime_secs: u64,
    pub sessions_total: u64,
    pub sessions_succeeded: u64,
    pub sessions_failed: u64,
    pub last_session_latency_ms: Option<u64>,
    pub last_first_partial_ms: Option<u64>,
    pub recent_errors: Vec<RecentError>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RecentError {
    pub timestamp_unix_secs: u64,
    pub message: String,
}

#[derive(Debug, Error)]
pub enum ProtocolError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("frame too large: {0} bytes (max {1})")]
    FrameTooLarge(u32, u32),
    #[error("json: {0}")]
    Json(#[from] serde_json::Error),
    #[error("protocol version mismatch: got {got}, expected {expected}")]
    VersionMismatch { got: u32, expected: u32 },
    #[error("kind mismatch: expected {expected}, got {got}")]
    KindMismatch {
        expected: &'static str,
        got: &'static str,
    },
}

impl Envelope {
    pub fn new_request(req: &Request) -> Result<Self, serde_json::Error> {
        Ok(Self {
            protocol_version: PROTOCOL_VERSION,
            kind: EnvelopeKind::Request,
            id: Uuid::new_v4(),
            payload: serde_json::to_value(req)?,
        })
    }

    pub fn new_response(in_reply_to: Uuid, resp: &Response) -> Result<Self, serde_json::Error> {
        Ok(Self {
            protocol_version: PROTOCOL_VERSION,
            kind: EnvelopeKind::Response,
            id: in_reply_to,
            payload: serde_json::to_value(resp)?,
        })
    }

    pub fn decode_request(&self) -> Result<Request, ProtocolError> {
        if self.kind != EnvelopeKind::Request {
            return Err(ProtocolError::KindMismatch {
                expected: "request",
                got: "response",
            });
        }
        Ok(serde_json::from_value(self.payload.clone())?)
    }

    pub fn decode_response(&self) -> Result<Response, ProtocolError> {
        if self.kind != EnvelopeKind::Response {
            return Err(ProtocolError::KindMismatch {
                expected: "response",
                got: "request",
            });
        }
        Ok(serde_json::from_value(self.payload.clone())?)
    }
}
