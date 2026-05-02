//! End-to-end test against a tokio_tungstenite mock server. Uses ws://
//! (no TLS) so the tempdir-bound localhost listener works without certs.

#![allow(clippy::result_large_err)] // tungstenite's ErrorResponse is large; test only

use futures_util::{SinkExt, StreamExt};
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::Notify;
use tokio_tungstenite::tungstenite::Message;
use voco_asr::{
    doubao::{
        codec,
        protocol::{self, MsgFlags},
        DoubaoBackend,
    },
    AsrBackend, AsrError,
};
use voco_config::DoubaoCreds;

/// What our mock asserts and replies. One scenario per test.
async fn mock_handshake_then_final(
    listener: TcpListener,
    asserts: Arc<Notify>,
) -> Result<Vec<String>, String> {
    let (sock, _) = listener.accept().await.map_err(|e| e.to_string())?;
    let mut received_headers = Vec::new();
    let cb = |req: &tokio_tungstenite::tungstenite::handshake::server::Request,
              mut resp: tokio_tungstenite::tungstenite::handshake::server::Response|
     -> Result<
        tokio_tungstenite::tungstenite::handshake::server::Response,
        tokio_tungstenite::tungstenite::handshake::server::ErrorResponse,
    > {
        for (k, v) in req.headers() {
            received_headers.push(format!("{}={}", k, v.to_str().unwrap_or("?")));
        }
        // Echo a logid back so the client surfaces it.
        resp.headers_mut()
            .insert("x-tt-logid", "20260502TEST123".parse().unwrap());
        Ok(resp)
    };
    let mut ws = tokio_tungstenite::accept_hdr_async(
        TcpStream::from_std(sock.into_std().unwrap()).unwrap(),
        cb,
    )
    .await
    .map_err(|e| format!("accept: {e}"))?;

    // Expect: FullClientRequest frame.
    let msg = ws
        .next()
        .await
        .ok_or("no FullClientRequest")?
        .map_err(|e| e.to_string())?;
    let bytes = match msg {
        Message::Binary(b) => b,
        other => return Err(format!("expected binary, got {other:?}")),
    };
    let header = protocol::Header::decode(&bytes).map_err(|e| e.to_string())?;
    if header.message_type != protocol::MessageType::FullClientRequest {
        return Err(format!(
            "expected FullClientRequest, got {:?}",
            header.message_type
        ));
    }

    // Drain audio frames; once we see a last-packet, send a Final response.
    loop {
        let msg = ws
            .next()
            .await
            .ok_or("client closed before last-packet")?
            .map_err(|e| e.to_string())?;
        let Message::Binary(b) = msg else { continue };
        let h = protocol::Header::decode(&b).map_err(|e| e.to_string())?;
        if h.message_type != protocol::MessageType::AudioOnlyRequest {
            return Err(format!("unexpected client frame: {:?}", h.message_type));
        }
        if h.flags.is_last() {
            break;
        }
    }

    // Send a final response: utterance "hello world" definite.
    let payload = br#"{"result":{"text":"hello world","utterances":[
        {"text":"hello world","start_time":0,"end_time":1000,"definite":true}
    ]}}"#;
    let gz = codec::gzip(payload).map_err(|e| e.to_string())?;
    let header = protocol::Header {
        message_type: protocol::MessageType::FullServerResponse,
        flags: MsgFlags::LastWithSequence,
        serialization: protocol::Serialization::Json,
        compression: protocol::Compression::Gzip,
    };
    let mut frame = Vec::new();
    frame.extend_from_slice(&header.encode());
    frame.extend_from_slice(&(-1i32).to_be_bytes());
    frame.extend_from_slice(&(gz.len() as u32).to_be_bytes());
    frame.extend_from_slice(&gz);
    ws.send(Message::Binary(frame))
        .await
        .map_err(|e| e.to_string())?;
    asserts.notify_waiters();
    Ok(received_headers)
}

#[tokio::test]
async fn handshake_audio_final_roundtrip() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let endpoint = format!("ws://127.0.0.1:{port}/api/v3/sauc/bigmodel_async");

    let asserts = Arc::new(Notify::new());
    let server_asserts = asserts.clone();
    let server =
        tokio::spawn(async move { mock_handshake_then_final(listener, server_asserts).await });

    let mut backend = DoubaoBackend::new(DoubaoCreds {
        app_id: "APP".into(),
        access_token: "TOK".into(),
        endpoint: endpoint.clone(),
        ..Default::default()
    });
    backend.start().await.unwrap();
    // Feed some PCM (under 200ms — will buffer until stop flushes).
    let pcm = vec![0i16; 100];
    let _ = backend.feed(&pcm).await;
    let final_ = backend.stop().await.unwrap();
    assert_eq!(final_.text, "hello world");
    assert_eq!(final_.logid.as_deref(), Some("20260502TEST123"));

    let headers = server.await.unwrap().unwrap();
    assert!(
        headers.iter().any(|h| h == "x-api-app-key=APP"),
        "missing x-api-app-key in headers: {headers:?}"
    );
    assert!(
        headers.iter().any(|h| h == "x-api-access-key=TOK"),
        "missing x-api-access-key: {headers:?}"
    );
    assert!(
        headers
            .iter()
            .any(|h| h.starts_with("x-api-resource-id=volc.bigasr.sauc.duration")),
        "missing resource-id: {headers:?}"
    );
}

#[tokio::test]
async fn server_error_45000002_maps_to_empty_audio() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let endpoint = format!("ws://127.0.0.1:{port}/api/v3/sauc/bigmodel_async");

    tokio::spawn(async move {
        let (sock, _) = listener.accept().await.unwrap();
        let mut ws =
            tokio_tungstenite::accept_async(TcpStream::from_std(sock.into_std().unwrap()).unwrap())
                .await
                .unwrap();
        // Read FullClientRequest, then immediately send 45000002.
        let _ = ws.next().await;
        let header = protocol::Header {
            message_type: protocol::MessageType::ServerError,
            flags: MsgFlags::NoSequence,
            serialization: protocol::Serialization::Json,
            compression: protocol::Compression::None,
        };
        let msg = b"empty audio";
        let mut frame = Vec::new();
        frame.extend_from_slice(&header.encode());
        frame.extend_from_slice(&45000002u32.to_be_bytes());
        frame.extend_from_slice(&(msg.len() as u32).to_be_bytes());
        frame.extend_from_slice(msg);
        let _ = ws.send(Message::Binary(frame)).await;
    });

    let mut backend = DoubaoBackend::new(DoubaoCreds {
        app_id: "APP".into(),
        access_token: "TOK".into(),
        endpoint,
        ..Default::default()
    });
    backend.start().await.unwrap();
    let r = backend.stop().await;
    assert!(matches!(r, Err(AsrError::EmptyAudio)), "got {r:?}");
}
