//! Volcengine binary frame protocol. See `~/Downloads/volcengine-api.md`
//! sections "header 数据格式" and "请求流程".
//!
//! Frame layouts:
//! - **Client → Server (no sequence)** — `Header(4) | PayloadSize(4 BE) | Payload`
//!   - FullClientRequest: gzipped JSON
//!   - AudioOnlyRequest: gzipped raw PCM (s16le)
//! - **Server → Client (FullServerResponse)** — `Header(4) | Sequence(4 BE) | PayloadSize(4 BE) | Payload`
//! - **Server → Client (Error)** — `Header(4) | Code(4 BE) | Size(4 BE) | UTF-8 message`
//!
//! Voco's design choice (see Phase 2 plan §7.2): client never sends a
//! sequence field. Last audio packet uses `flags = 0b0010` (no seq +
//! last-packet bit). Server still sequences its responses.

use crate::AsrError;
use bytes::{Buf, BufMut, BytesMut};

const PROTOCOL_VERSION: u8 = 1;
const HEADER_SIZE_WORDS: u8 = 1; // header is 1 × 4 = 4 bytes

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum MessageType {
    FullClientRequest = 0b0001,
    AudioOnlyRequest = 0b0010,
    FullServerResponse = 0b1001,
    ServerError = 0b1111,
}

impl MessageType {
    fn from_nibble(n: u8) -> Option<Self> {
        match n {
            0b0001 => Some(MessageType::FullClientRequest),
            0b0010 => Some(MessageType::AudioOnlyRequest),
            0b1001 => Some(MessageType::FullServerResponse),
            0b1111 => Some(MessageType::ServerError),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum Serialization {
    None = 0b0000,
    Json = 0b0001,
}

impl Serialization {
    fn from_nibble(n: u8) -> Option<Self> {
        match n {
            0b0000 => Some(Serialization::None),
            0b0001 => Some(Serialization::Json),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum Compression {
    None = 0b0000,
    Gzip = 0b0001,
}

impl Compression {
    fn from_nibble(n: u8) -> Option<Self> {
        match n {
            0b0000 => Some(Compression::None),
            0b0001 => Some(Compression::Gzip),
            _ => None,
        }
    }
}

/// Message-type-specific flags. We encode the four documented combinations
/// rather than expose a raw nibble — fewer footguns, smaller test matrix.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MsgFlags {
    /// Client: no sequence; Server: no sequence (rare).
    NoSequence = 0b0000,
    /// Server: header followed by positive u32 sequence.
    PositiveSequence = 0b0001,
    /// Client last packet, no sequence.
    LastNoSequence = 0b0010,
    /// Server last packet, with sequence (typically negative).
    LastWithSequence = 0b0011,
}

impl MsgFlags {
    fn from_nibble(n: u8) -> Option<Self> {
        match n {
            0b0000 => Some(MsgFlags::NoSequence),
            0b0001 => Some(MsgFlags::PositiveSequence),
            0b0010 => Some(MsgFlags::LastNoSequence),
            0b0011 => Some(MsgFlags::LastWithSequence),
            _ => None,
        }
    }

    pub fn carries_sequence(self) -> bool {
        matches!(
            self,
            MsgFlags::PositiveSequence | MsgFlags::LastWithSequence
        )
    }

    pub fn is_last(self) -> bool {
        matches!(self, MsgFlags::LastNoSequence | MsgFlags::LastWithSequence)
    }
}

/// 4-byte header. Encodes/decodes the bit-packed wire format.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Header {
    pub message_type: MessageType,
    pub flags: MsgFlags,
    pub serialization: Serialization,
    pub compression: Compression,
}

impl Header {
    pub fn encode(&self) -> [u8; 4] {
        [
            (PROTOCOL_VERSION << 4) | HEADER_SIZE_WORDS,
            ((self.message_type as u8) << 4) | (self.flags as u8),
            ((self.serialization as u8) << 4) | (self.compression as u8),
            0x00,
        ]
    }

    pub fn decode(b: &[u8]) -> Result<Self, AsrError> {
        if b.len() < 4 {
            return Err(AsrError::Decode(format!(
                "header needs 4 bytes, got {}",
                b.len()
            )));
        }
        let proto = b[0] >> 4;
        let header_size = b[0] & 0x0F;
        if proto != PROTOCOL_VERSION {
            return Err(AsrError::Decode(format!(
                "unsupported protocol version {proto}"
            )));
        }
        if header_size != HEADER_SIZE_WORDS {
            return Err(AsrError::Decode(format!(
                "header_size={header_size} (expected {HEADER_SIZE_WORDS})"
            )));
        }
        let mt = MessageType::from_nibble(b[1] >> 4)
            .ok_or_else(|| AsrError::Decode(format!("unknown message type {}", b[1] >> 4)))?;
        let flags = MsgFlags::from_nibble(b[1] & 0x0F)
            .ok_or_else(|| AsrError::Decode(format!("unknown flags nibble {}", b[1] & 0x0F)))?;
        let ser = Serialization::from_nibble(b[2] >> 4)
            .ok_or_else(|| AsrError::Decode(format!("unknown serialization {}", b[2] >> 4)))?;
        let comp = Compression::from_nibble(b[2] & 0x0F)
            .ok_or_else(|| AsrError::Decode(format!("unknown compression {}", b[2] & 0x0F)))?;
        Ok(Self {
            message_type: mt,
            flags,
            serialization: ser,
            compression: comp,
        })
    }
}

/// Build a FullClientRequest frame: header + size + payload.
/// `payload` should be the gzipped JSON body.
pub fn build_full_client_request_frame(payload_gzipped: &[u8]) -> Vec<u8> {
    let header = Header {
        message_type: MessageType::FullClientRequest,
        flags: MsgFlags::NoSequence,
        serialization: Serialization::Json,
        compression: Compression::Gzip,
    };
    encode_size_prefixed(&header, payload_gzipped)
}

/// Build an audio frame. `last` decides flags 0b0000 vs 0b0010. Voco
/// never sends with-sequence audio frames (Phase 2 plan §7.2).
pub fn build_audio_frame(payload_gzipped: &[u8], last: bool) -> Vec<u8> {
    let header = Header {
        message_type: MessageType::AudioOnlyRequest,
        flags: if last {
            MsgFlags::LastNoSequence
        } else {
            MsgFlags::NoSequence
        },
        serialization: Serialization::None,
        compression: Compression::Gzip,
    };
    encode_size_prefixed(&header, payload_gzipped)
}

fn encode_size_prefixed(header: &Header, payload: &[u8]) -> Vec<u8> {
    let mut out = BytesMut::with_capacity(4 + 4 + payload.len());
    out.put_slice(&header.encode());
    out.put_u32(payload.len() as u32);
    out.put_slice(payload);
    out.to_vec()
}

/// Parsed server frame, post-decompression. Either a normal response
/// payload (JSON bytes ready to deserialize) or an error.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ServerFrame {
    Response {
        flags: MsgFlags,
        sequence: Option<i32>,
        payload: Vec<u8>,
    },
    Error {
        code: u32,
        message: String,
    },
}

/// Parse one server frame from raw WS message bytes. Handles gzip by
/// inspecting the header's compression nibble.
pub fn parse_server_frame(buf: &[u8]) -> Result<ServerFrame, AsrError> {
    let header = Header::decode(buf)?;
    let mut rest = &buf[4..];

    match header.message_type {
        MessageType::FullServerResponse => {
            let sequence = if header.flags.carries_sequence() {
                if rest.len() < 4 {
                    return Err(AsrError::Decode("missing sequence".into()));
                }
                let s = rest.get_i32();
                Some(s)
            } else {
                None
            };
            if rest.len() < 4 {
                return Err(AsrError::Decode("missing payload size".into()));
            }
            let size = rest.get_u32() as usize;
            if rest.len() < size {
                return Err(AsrError::Decode(format!(
                    "payload truncated: have {}, want {}",
                    rest.len(),
                    size
                )));
            }
            let payload = &rest[..size];
            let payload = match header.compression {
                Compression::Gzip => super::codec::gunzip(payload)?,
                Compression::None => payload.to_vec(),
            };
            Ok(ServerFrame::Response {
                flags: header.flags,
                sequence,
                payload,
            })
        }
        MessageType::ServerError => {
            if rest.len() < 8 {
                return Err(AsrError::Decode("error frame truncated".into()));
            }
            let code = rest.get_u32();
            let size = rest.get_u32() as usize;
            if rest.len() < size {
                return Err(AsrError::Decode("error message truncated".into()));
            }
            let raw = &rest[..size];
            let bytes = match header.compression {
                Compression::Gzip => super::codec::gunzip(raw)?,
                Compression::None => raw.to_vec(),
            };
            let message = String::from_utf8_lossy(&bytes).into_owned();
            Ok(ServerFrame::Error { code, message })
        }
        other => Err(AsrError::Decode(format!(
            "unexpected server message type {other:?}"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::super::codec;
    use super::*;

    #[test]
    fn header_roundtrip_full_client_request() {
        let h = Header {
            message_type: MessageType::FullClientRequest,
            flags: MsgFlags::NoSequence,
            serialization: Serialization::Json,
            compression: Compression::Gzip,
        };
        let bytes = h.encode();
        // First byte: protocol_version=1 (0x10) | header_size=1 (0x01) = 0x11
        assert_eq!(bytes[0], 0x11);
        // Second byte: type=0x1, flags=0x0 = 0x10
        assert_eq!(bytes[1], 0x10);
        // Third byte: ser=0x1 (JSON), comp=0x1 (Gzip) = 0x11
        assert_eq!(bytes[2], 0x11);
        assert_eq!(bytes[3], 0x00);
        assert_eq!(Header::decode(&bytes).unwrap(), h);
    }

    #[test]
    fn header_roundtrip_audio_last_packet() {
        let h = Header {
            message_type: MessageType::AudioOnlyRequest,
            flags: MsgFlags::LastNoSequence,
            serialization: Serialization::None,
            compression: Compression::Gzip,
        };
        let bytes = h.encode();
        assert_eq!(bytes[1], (0b0010 << 4) | 0b0010);
        assert_eq!(Header::decode(&bytes).unwrap(), h);
    }

    #[test]
    fn header_roundtrip_server_response_with_seq() {
        let h = Header {
            message_type: MessageType::FullServerResponse,
            flags: MsgFlags::PositiveSequence,
            serialization: Serialization::Json,
            compression: Compression::Gzip,
        };
        assert_eq!(Header::decode(&h.encode()).unwrap(), h);
    }

    #[test]
    fn header_rejects_wrong_protocol() {
        let mut bytes = Header {
            message_type: MessageType::AudioOnlyRequest,
            flags: MsgFlags::NoSequence,
            serialization: Serialization::None,
            compression: Compression::None,
        }
        .encode();
        bytes[0] = 0x21; // protocol_version=2
        assert!(Header::decode(&bytes).is_err());
    }

    #[test]
    fn header_rejects_unknown_message_type() {
        let bytes = [0x11, 0x70, 0x00, 0x00];
        assert!(Header::decode(&bytes).is_err());
    }

    #[test]
    fn full_client_request_frame_layout() {
        let payload = b"hello".as_slice();
        let frame = build_full_client_request_frame(payload);
        assert_eq!(frame.len(), 4 + 4 + payload.len());
        // Header
        assert_eq!(&frame[0..4], &[0x11, 0x10, 0x11, 0x00]);
        // Size big-endian
        assert_eq!(&frame[4..8], &(payload.len() as u32).to_be_bytes());
        assert_eq!(&frame[8..], payload);
    }

    #[test]
    fn audio_frame_last_packet_flag() {
        let f = build_audio_frame(b"abc", true);
        assert_eq!(f[1] & 0x0F, 0b0010);
    }

    #[test]
    fn audio_frame_normal_no_flag() {
        let f = build_audio_frame(b"abc", false);
        assert_eq!(f[1] & 0x0F, 0b0000);
    }

    /// Server response with seq + gzipped JSON payload (the realistic case).
    #[test]
    fn parses_response_with_seq_and_gzip() {
        let json = br#"{"result":{"text":"hi","utterances":[]}}"#.as_slice();
        let payload = codec::gzip(json).unwrap();
        let header = Header {
            message_type: MessageType::FullServerResponse,
            flags: MsgFlags::PositiveSequence,
            serialization: Serialization::Json,
            compression: Compression::Gzip,
        };
        let mut frame = Vec::new();
        frame.extend_from_slice(&header.encode());
        frame.extend_from_slice(&7i32.to_be_bytes()); // seq=7
        frame.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        frame.extend_from_slice(&payload);

        match parse_server_frame(&frame).unwrap() {
            ServerFrame::Response {
                flags,
                sequence,
                payload,
            } => {
                assert_eq!(flags, MsgFlags::PositiveSequence);
                assert_eq!(sequence, Some(7));
                assert_eq!(payload, json);
            }
            other => panic!("got {other:?}"),
        }
    }

    #[test]
    fn parses_server_error_frame() {
        let header = Header {
            message_type: MessageType::ServerError,
            flags: MsgFlags::NoSequence,
            serialization: Serialization::Json,
            compression: Compression::None,
        };
        let msg = b"empty audio";
        let mut frame = Vec::new();
        frame.extend_from_slice(&header.encode());
        frame.extend_from_slice(&45000002u32.to_be_bytes());
        frame.extend_from_slice(&(msg.len() as u32).to_be_bytes());
        frame.extend_from_slice(msg);

        match parse_server_frame(&frame).unwrap() {
            ServerFrame::Error { code, message } => {
                assert_eq!(code, 45000002);
                assert_eq!(message, "empty audio");
            }
            other => panic!("got {other:?}"),
        }
    }

    #[test]
    fn parses_last_packet_response() {
        // Simulate the doc's "last server response" example: flags=0b0011,
        // seq is negative.
        let json = br#"{}"#.as_slice();
        let payload = codec::gzip(json).unwrap();
        let header = Header {
            message_type: MessageType::FullServerResponse,
            flags: MsgFlags::LastWithSequence,
            serialization: Serialization::Json,
            compression: Compression::Gzip,
        };
        let mut frame = Vec::new();
        frame.extend_from_slice(&header.encode());
        frame.extend_from_slice(&(-3i32).to_be_bytes());
        frame.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        frame.extend_from_slice(&payload);

        match parse_server_frame(&frame).unwrap() {
            ServerFrame::Response {
                flags, sequence, ..
            } => {
                assert!(flags.is_last());
                assert_eq!(sequence, Some(-3));
            }
            other => panic!("got {other:?}"),
        }
    }

    #[test]
    fn rejects_truncated_payload() {
        let header = Header {
            message_type: MessageType::FullServerResponse,
            flags: MsgFlags::NoSequence,
            serialization: Serialization::Json,
            compression: Compression::None,
        };
        let mut frame = Vec::new();
        frame.extend_from_slice(&header.encode());
        frame.extend_from_slice(&100u32.to_be_bytes());
        frame.extend_from_slice(b"only-3-bytes-of-payload");
        assert!(parse_server_frame(&frame).is_err());
    }
}
