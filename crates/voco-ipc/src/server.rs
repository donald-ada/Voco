//! Async Unix-domain-socket server for the daemon control channel.

use crate::codec;
use crate::protocol::{
    Envelope, EnvelopeKind, ProtocolError, Request, Response, MAX_FRAME_BYTES, PROTOCOL_VERSION,
};
use async_trait::async_trait;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{UnixListener, UnixStream};
use tracing::{debug, error, info, warn};

#[async_trait]
pub trait RequestHandler: Send + Sync + 'static {
    async fn handle(&self, req: Request) -> Response;
}

pub struct IpcServer {
    listener: UnixListener,
    socket_path: PathBuf,
}

impl IpcServer {
    /// Bind to `socket_path`. Refuses to bind if another live daemon is already
    /// listening; clears stale socket files left by crashed daemons.
    pub fn bind(socket_path: impl Into<PathBuf>) -> Result<Self, std::io::Error> {
        let socket_path = socket_path.into();
        if socket_path.exists() {
            // Probe: if we can connect, another daemon owns it.
            match std::os::unix::net::UnixStream::connect(&socket_path) {
                Ok(_) => {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::AddrInUse,
                        format!("daemon already running at {}", socket_path.display()),
                    ));
                }
                Err(e) => {
                    warn!(?socket_path, error = %e, "removing stale socket");
                    std::fs::remove_file(&socket_path)?;
                }
            }
        }
        if let Some(parent) = socket_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let listener = UnixListener::bind(&socket_path)?;
        info!(?socket_path, "ipc server bound");
        Ok(Self {
            listener,
            socket_path,
        })
    }

    pub fn socket_path(&self) -> &Path {
        &self.socket_path
    }

    /// Run forever. Each incoming connection is handled in its own task.
    pub async fn serve<H: RequestHandler>(&self, handler: Arc<H>) {
        loop {
            match self.listener.accept().await {
                Ok((stream, _addr)) => {
                    let h = handler.clone();
                    tokio::spawn(async move {
                        if let Err(e) = handle_connection(stream, h).await {
                            warn!(error = %e, "ipc connection error");
                        }
                    });
                }
                Err(e) => {
                    error!(error = %e, "accept failed");
                    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                }
            }
        }
    }
}

impl Drop for IpcServer {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.socket_path);
    }
}

async fn handle_connection<H: RequestHandler>(
    mut stream: UnixStream,
    handler: Arc<H>,
) -> Result<(), ProtocolError> {
    // Read length prefix
    let mut len_buf = [0u8; 4];
    stream.read_exact(&mut len_buf).await?;
    let len = u32::from_be_bytes(len_buf);
    if len > MAX_FRAME_BYTES {
        return Err(ProtocolError::FrameTooLarge(len, MAX_FRAME_BYTES));
    }
    let mut body = vec![0u8; len as usize];
    stream.read_exact(&mut body).await?;
    let env: Envelope = serde_json::from_slice(&body)?;

    // Version check.
    if env.protocol_version != PROTOCOL_VERSION {
        let resp = Response::Error {
            message: format!(
                "protocol version mismatch: client={}, server={}. Run `voco daemon restart`.",
                env.protocol_version, PROTOCOL_VERSION
            ),
        };
        let out = Envelope::new_response(env.id, &resp)?;
        write_async(&mut stream, &out).await?;
        return Ok(());
    }

    if env.kind != EnvelopeKind::Request {
        let resp = Response::Error {
            message: "expected request envelope".into(),
        };
        let out = Envelope::new_response(env.id, &resp)?;
        write_async(&mut stream, &out).await?;
        return Ok(());
    }

    let req: Request = serde_json::from_value(env.payload.clone())?;
    debug!(?req, "ipc request");
    let resp = handler.handle(req).await;
    let out = Envelope::new_response(env.id, &resp)?;
    write_async(&mut stream, &out).await?;
    Ok(())
}

async fn write_async(stream: &mut UnixStream, env: &Envelope) -> Result<(), ProtocolError> {
    let body = serde_json::to_vec(env)?;
    let len: u32 = body
        .len()
        .try_into()
        .map_err(|_| ProtocolError::FrameTooLarge(u32::MAX, MAX_FRAME_BYTES))?;
    if len > MAX_FRAME_BYTES {
        return Err(ProtocolError::FrameTooLarge(len, MAX_FRAME_BYTES));
    }
    stream.write_all(&len.to_be_bytes()).await?;
    stream.write_all(&body).await?;
    stream.flush().await?;
    Ok(())
}

// Re-export sync codec helpers so integration tests living next to the server
// can use either path.
pub use codec::{read_envelope_blocking, write_envelope_blocking};
