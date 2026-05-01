//! Sync length-prefixed framing for [`Envelope`].

use crate::protocol::{Envelope, ProtocolError, MAX_FRAME_BYTES};
use std::io::{Read, Write};

pub fn write_envelope_blocking<W: Write>(w: &mut W, env: &Envelope) -> Result<(), ProtocolError> {
    let body = serde_json::to_vec(env)?;
    let len: u32 = body
        .len()
        .try_into()
        .map_err(|_| ProtocolError::FrameTooLarge(u32::MAX, MAX_FRAME_BYTES))?;
    if len > MAX_FRAME_BYTES {
        return Err(ProtocolError::FrameTooLarge(len, MAX_FRAME_BYTES));
    }
    w.write_all(&len.to_be_bytes())?;
    w.write_all(&body)?;
    w.flush()?;
    Ok(())
}

pub fn read_envelope_blocking<R: Read>(r: &mut R) -> Result<Envelope, ProtocolError> {
    let mut len_buf = [0u8; 4];
    r.read_exact(&mut len_buf)?;
    let len = u32::from_be_bytes(len_buf);
    if len > MAX_FRAME_BYTES {
        return Err(ProtocolError::FrameTooLarge(len, MAX_FRAME_BYTES));
    }
    let mut body = vec![0u8; len as usize];
    r.read_exact(&mut body)?;
    let env: Envelope = serde_json::from_slice(&body)?;
    Ok(env)
}
