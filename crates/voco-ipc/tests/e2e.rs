//! Spin up a real IpcServer in a tokio task and round-trip a Request through
//! the synchronous IpcClient.

use async_trait::async_trait;
use std::sync::Arc;
use voco_ipc::client::IpcClient;
use voco_ipc::protocol::*;
use voco_ipc::server::{IpcServer, RequestHandler};

struct EchoHandler;

#[async_trait]
impl RequestHandler for EchoHandler {
    async fn handle(&self, req: Request) -> Response {
        match req {
            Request::Status => Response::Status(StatusInfo {
                state: "idle".into(),
                backend: "doubao".into(),
                backend_in_use: "doubao".into(),
                uptime_secs: 0,
                sessions_total: 0,
                sessions_succeeded: 0,
                sessions_failed: 0,
                last_session_latency_ms: None,
                last_first_partial_ms: None,
                recent_errors: vec![],
            }),
            _ => Response::Ok,
        }
    }
}

#[tokio::test]
async fn status_request_roundtrips() {
    let dir = tempfile::tempdir().unwrap();
    let sock = dir.path().join("voco.sock");

    let server = IpcServer::bind(&sock).unwrap();
    let handler = Arc::new(EchoHandler);
    let serve_handle = tokio::spawn(async move {
        server.serve(handler).await;
    });

    tokio::time::sleep(std::time::Duration::from_millis(50)).await;

    let sock_clone = sock.clone();
    let resp = tokio::task::spawn_blocking(move || {
        let mut client = IpcClient::connect(&sock_clone).unwrap();
        client.call(&Request::Status).unwrap()
    })
    .await
    .unwrap();

    match resp {
        Response::Status(s) => {
            assert_eq!(s.state, "idle");
            assert_eq!(s.backend, "doubao");
        }
        other => panic!("expected Status, got {other:?}"),
    }

    serve_handle.abort();
}

#[tokio::test]
async fn version_mismatch_returns_error() {
    use std::io::{Read, Write};
    use std::os::unix::net::UnixStream as StdStream;

    let dir = tempfile::tempdir().unwrap();
    let sock = dir.path().join("voco.sock");

    let server = IpcServer::bind(&sock).unwrap();
    let handler = Arc::new(EchoHandler);
    let serve_handle = tokio::spawn(async move {
        server.serve(handler).await;
    });
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;

    let sock_clone = sock.clone();
    let resp_text = tokio::task::spawn_blocking(move || {
        let env = serde_json::json!({
            "protocol_version": 999,
            "kind": "request",
            "id": uuid::Uuid::new_v4(),
            "payload": { "method": "status" }
        });
        let body = serde_json::to_vec(&env).unwrap();
        let mut stream = StdStream::connect(&sock_clone).unwrap();
        stream
            .write_all(&(body.len() as u32).to_be_bytes())
            .unwrap();
        stream.write_all(&body).unwrap();

        let mut len_buf = [0u8; 4];
        stream.read_exact(&mut len_buf).unwrap();
        let len = u32::from_be_bytes(len_buf) as usize;
        let mut body = vec![0u8; len];
        stream.read_exact(&mut body).unwrap();
        String::from_utf8(body).unwrap()
    })
    .await
    .unwrap();

    assert!(resp_text.contains("protocol version mismatch"));
    serve_handle.abort();
}
