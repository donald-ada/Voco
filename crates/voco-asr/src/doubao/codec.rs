//! Gzip wrappers around `flate2`. Used for both client request bodies
//! (full client request payload + audio frames) and server response
//! payloads.

use crate::AsrError;
use flate2::read::GzDecoder;
use flate2::write::GzEncoder;
use flate2::Compression;
use std::io::{Read, Write};

pub fn gzip(input: &[u8]) -> Result<Vec<u8>, AsrError> {
    let mut e = GzEncoder::new(Vec::with_capacity(input.len()), Compression::default());
    e.write_all(input)
        .map_err(|err| AsrError::Decode(format!("gzip write: {err}")))?;
    e.finish()
        .map_err(|err| AsrError::Decode(format!("gzip finish: {err}")))
}

pub fn gunzip(input: &[u8]) -> Result<Vec<u8>, AsrError> {
    let mut d = GzDecoder::new(input);
    let mut out = Vec::with_capacity(input.len() * 4);
    d.read_to_end(&mut out)
        .map_err(|err| AsrError::Decode(format!("gunzip: {err}")))?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_short() {
        let input = b"hello, world!";
        assert_eq!(gunzip(&gzip(input).unwrap()).unwrap(), input);
    }

    #[test]
    fn roundtrip_empty() {
        assert_eq!(gunzip(&gzip(b"").unwrap()).unwrap(), b"");
    }

    #[test]
    fn roundtrip_binary() {
        let input: Vec<u8> = (0u8..=255).cycle().take(8192).collect();
        assert_eq!(gunzip(&gzip(&input).unwrap()).unwrap(), input);
    }

    #[test]
    fn rejects_garbage() {
        assert!(gunzip(b"this is not gzip").is_err());
    }
}
