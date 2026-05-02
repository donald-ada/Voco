//! Errors raised by `AsrBackend` implementations.
//!
//! Doubao-specific error codes from the Volcengine spec:
//! - 20000000 success (never wrapped here)
//! - 45000001 invalid request → `BadRequest`
//! - 45000002 empty audio → `EmptyAudio` (treated as ✓ by doctor probes)
//! - 45000081 timeout → `Timeout`
//! - 45000151 audio format → `AudioFormat`
//! - 550xxxxx server internal → `ServerInternal`
//! - 55000031 server busy → `ServerBusy`

use thiserror::Error;

#[derive(Debug, Error)]
pub enum AsrError {
    #[error("not implemented: {0}")]
    NotImplemented(&'static str),

    #[error("auth: {0}")]
    Auth(String),

    #[error("transport: {0}")]
    Transport(String),

    #[error("protocol decode: {0}")]
    Decode(String),

    #[error("server bad request (45000001): {0}")]
    BadRequest(String),

    #[error("empty audio (45000002)")]
    EmptyAudio,

    #[error("server timeout (45000081)")]
    Timeout,

    #[error("server audio-format error (45000151): {0}")]
    AudioFormat(String),

    #[error("server internal (550xxxxx, code={code}): {message}")]
    ServerInternal { code: u32, message: String },

    #[error("server busy (55000031)")]
    ServerBusy,

    #[error("server error (code={code}): {message}")]
    ServerOther { code: u32, message: String },
}

impl AsrError {
    /// Map a Volcengine numeric code + message to a typed variant.
    pub fn from_server_code(code: u32, message: String) -> Self {
        match code {
            45000001 => AsrError::BadRequest(message),
            45000002 => AsrError::EmptyAudio,
            45000081 => AsrError::Timeout,
            45000151 => AsrError::AudioFormat(message),
            55000031 => AsrError::ServerBusy,
            c if (55000000..56000000).contains(&c) => AsrError::ServerInternal { code: c, message },
            c => AsrError::ServerOther { code: c, message },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_known_codes() {
        assert!(matches!(
            AsrError::from_server_code(45000002, String::new()),
            AsrError::EmptyAudio
        ));
        assert!(matches!(
            AsrError::from_server_code(45000081, String::new()),
            AsrError::Timeout
        ));
        assert!(matches!(
            AsrError::from_server_code(55000031, String::new()),
            AsrError::ServerBusy
        ));
    }

    #[test]
    fn maps_5xx_range_to_internal() {
        match AsrError::from_server_code(55000099, "x".into()) {
            AsrError::ServerInternal { code, message } => {
                assert_eq!(code, 55000099);
                assert_eq!(message, "x");
            }
            other => panic!("got {other:?}"),
        }
    }

    #[test]
    fn unknown_code_falls_through_to_other() {
        match AsrError::from_server_code(99999999, "x".into()) {
            AsrError::ServerOther { code, .. } => assert_eq!(code, 99999999),
            other => panic!("got {other:?}"),
        }
    }
}
