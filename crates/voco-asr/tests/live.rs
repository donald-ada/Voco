//! Live smoke against the real Volcengine endpoint. Gated on env vars
//! `VOCO_DOUBAO_APP_ID` and `VOCO_DOUBAO_ACCESS_TOKEN` (or `VOCO_DOUBAO_API_KEY`
//! for new console). When unset, the test returns Ok(()) so default
//! `cargo test -p voco-asr` is green.
//!
//! Run with: `cargo test -p voco-asr --test live -- --ignored`

use voco_asr::{doubao::DoubaoBackend, AsrBackend, AsrError};
use voco_config::DoubaoCreds;

fn creds_from_env() -> Option<DoubaoCreds> {
    let app_id = std::env::var("VOCO_DOUBAO_APP_ID").ok();
    let access_token = std::env::var("VOCO_DOUBAO_ACCESS_TOKEN").ok();
    let api_key = std::env::var("VOCO_DOUBAO_API_KEY").ok();
    if app_id.is_none() && api_key.is_none() {
        return None;
    }
    Some(DoubaoCreds {
        app_id: app_id.unwrap_or_default(),
        access_token: access_token.unwrap_or_default(),
        api_key,
        ..Default::default()
    })
}

#[tokio::test]
#[ignore = "needs VOCO_DOUBAO_* env vars + network"]
async fn handshake_returns_logid_and_empty_audio_error() {
    let creds = match creds_from_env() {
        None => return, // not a failure — silently skip
        Some(c) => c,
    };
    let mut backend = DoubaoBackend::new(creds);

    backend.start().await.expect("handshake should succeed");
    let logid_after_start = backend.logid().map(|s| s.to_string());
    assert!(
        logid_after_start.is_some(),
        "expected x-tt-logid response header"
    );

    // No audio sent — server should respond with 45000002 (empty audio).
    match backend.stop().await {
        Err(AsrError::EmptyAudio) => {}
        Err(other) => panic!("expected EmptyAudio, got {other:?}"),
        Ok(_) => panic!("expected EmptyAudio, got Ok(_)"),
    }
}
