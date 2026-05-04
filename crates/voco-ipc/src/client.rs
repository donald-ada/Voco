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

    pub fn set_timeouts(
        &self,
        read: Option<Duration>,
        write: Option<Duration>,
    ) -> Result<(), ProtocolError> {
        self.stream.set_read_timeout(read)?;
        self.stream.set_write_timeout(write)?;
        Ok(())
    }

    pub fn call(&mut self, req: &Request) -> Result<Response, ProtocolError> {
        let env = Envelope::new_request(req)?;
        write_envelope_blocking(&mut self.stream, &env)?;
        let resp_env = read_envelope_blocking(&mut self.stream)?;
        resp_env.decode_response()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn set_timeouts_updates_socket_timeouts() {
        let (stream, _peer) = UnixStream::pair().unwrap();
        let client = IpcClient { stream };

        client
            .set_timeouts(Some(Duration::from_secs(40)), Some(Duration::from_secs(5)))
            .unwrap();

        assert_eq!(
            client.stream.read_timeout().unwrap(),
            Some(Duration::from_secs(40))
        );
        assert_eq!(
            client.stream.write_timeout().unwrap(),
            Some(Duration::from_secs(5))
        );
    }
}
