//! Synchronous Unix-socket client. CLI uses this — no tokio runtime needed,
//! which keeps `voco status` cold-start under 50ms.

use crate::codec::{read_envelope_blocking, write_envelope_blocking};
use crate::protocol::{Envelope, ProtocolError, Request, Response};
use std::os::unix::net::UnixStream;
use std::path::Path;
use std::time::Duration;

pub struct IpcClient {
    stream: UnixStream,
}

impl IpcClient {
    pub fn connect(socket_path: impl AsRef<Path>) -> Result<Self, ProtocolError> {
        let stream = UnixStream::connect(socket_path)?;
        stream.set_read_timeout(Some(Duration::from_secs(5)))?;
        stream.set_write_timeout(Some(Duration::from_secs(5)))?;
        Ok(Self { stream })
    }

    pub fn call(&mut self, req: &Request) -> Result<Response, ProtocolError> {
        let env = Envelope::new_request(req)?;
        write_envelope_blocking(&mut self.stream, &env)?;
        let resp_env = read_envelope_blocking(&mut self.stream)?;
        resp_env.decode_response()
    }
}
