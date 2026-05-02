use std::io::Cursor;
use voco_ipc::codec::{read_envelope_blocking, write_envelope_blocking};
use voco_ipc::protocol::*;

#[test]
fn roundtrip_request() {
    let mut buf = Vec::new();
    let env = Envelope::new_request(&Request::Status).unwrap();
    write_envelope_blocking(&mut buf, &env).unwrap();

    let mut cur = Cursor::new(buf);
    let decoded = read_envelope_blocking(&mut cur).unwrap();
    assert_eq!(decoded, env);
}

#[test]
fn frame_too_large_rejected() {
    let mut buf = Vec::new();
    let too_big: u32 = MAX_FRAME_BYTES + 1;
    buf.extend_from_slice(&too_big.to_be_bytes());
    buf.extend(std::iter::repeat(0u8).take(4));

    let mut cur = Cursor::new(buf);
    let err = read_envelope_blocking(&mut cur).unwrap_err();
    assert!(matches!(err, ProtocolError::FrameTooLarge(_, _)));
}
