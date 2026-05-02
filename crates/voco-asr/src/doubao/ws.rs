//! Tokio-tungstenite glue: dial the Volcengine endpoint with auth headers,
//! capture the X-Tt-Logid response header, expose send/recv halves.

use crate::doubao::auth::DoubaoAuth;
use crate::AsrError;
use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::{
    client::IntoClientRequest,
    handshake::client::generate_key,
    http::{HeaderName, HeaderValue, Request as HttpRequest},
    Message,
};
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

pub type WsStream = WebSocketStream<MaybeTlsStream<TcpStream>>;

/// Open a WS connection to `endpoint`, attach auth headers, return the
/// stream + the server's `X-Tt-Logid` (if present).
pub async fn connect(
    endpoint: &str,
    auth: &DoubaoAuth,
) -> Result<(WsStream, Option<String>), AsrError> {
    let url = url::Url::parse(endpoint)
        .map_err(|e| AsrError::Transport(format!("bad endpoint `{endpoint}`: {e}")))?;
    let host = url
        .host_str()
        .ok_or_else(|| AsrError::Transport(format!("endpoint has no host: {endpoint}")))?;

    // Hand-build the HTTP upgrade request so we can inject Doubao's headers.
    // tungstenite's `IntoClientRequest` from a URL doesn't let us set arbitrary
    // headers cleanly; constructing a Request<()> ourselves does.
    let mut req: HttpRequest<()> = endpoint
        .into_client_request()
        .map_err(|e| AsrError::Transport(format!("upgrade-request: {e}")))?;

    // Default IntoClientRequest already sets Host / Upgrade / Connection /
    // Sec-WebSocket-Key / Sec-WebSocket-Version, but be defensive.
    let headers = req.headers_mut();
    headers
        .entry(HeaderName::from_static("host"))
        .or_insert_with(|| HeaderValue::from_str(host).unwrap());
    headers
        .entry(HeaderName::from_static("sec-websocket-key"))
        .or_insert_with(|| HeaderValue::from_str(&generate_key()).unwrap());

    for (k, v) in &auth.headers {
        let name = HeaderName::from_bytes(k.as_bytes())
            .map_err(|e| AsrError::Transport(format!("bad header name `{k}`: {e}")))?;
        let value = HeaderValue::from_str(v)
            .map_err(|e| AsrError::Transport(format!("bad header value: {e}")))?;
        headers.insert(name, value);
    }

    let (stream, response) = tokio_tungstenite::connect_async(req)
        .await
        .map_err(|e| AsrError::Transport(format!("ws connect to {endpoint}: {e}")))?;

    let logid = response
        .headers()
        .get("x-tt-logid")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    Ok((stream, logid))
}

pub async fn send_binary(stream: &mut WsStream, bytes: Vec<u8>) -> Result<(), AsrError> {
    stream
        .send(Message::Binary(bytes))
        .await
        .map_err(|e| AsrError::Transport(format!("ws send: {e}")))
}

/// Receive the next binary frame. Skips Ping/Pong/Text frames.
pub async fn recv_binary(stream: &mut WsStream) -> Result<Option<Vec<u8>>, AsrError> {
    while let Some(msg) = stream.next().await {
        match msg.map_err(|e| AsrError::Transport(format!("ws recv: {e}")))? {
            Message::Binary(b) => return Ok(Some(b.to_vec())),
            Message::Close(_) => return Ok(None),
            Message::Ping(_) | Message::Pong(_) | Message::Text(_) | Message::Frame(_) => continue,
        }
    }
    Ok(None)
}

pub async fn close(mut stream: WsStream) {
    let _ = stream.close(None).await;
}
