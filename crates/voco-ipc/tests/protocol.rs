use voco_ipc::protocol::*;

#[test]
fn protocol_version_is_three() {
    assert_eq!(PROTOCOL_VERSION, 3);
}

#[test]
fn recording_once_serializes_with_snake_case_fields() {
    let req = Request::RecordingOnce {
        duration_ms: 3_000,
        include_partials: true,
    };

    let value = serde_json::to_value(&req).unwrap();

    assert_eq!(
        value,
        serde_json::json!({
            "method": "recording_once",
            "duration_ms": 3000,
            "include_partials": true
        })
    );
    assert_eq!(serde_json::from_value::<Request>(value).unwrap(), req);
}

#[test]
fn recording_result_roundtrips_segments_partials_and_timings() {
    let resp = Response::RecordingResult {
        text: "你好".into(),
        segments: vec![Segment {
            text: "你好".into(),
            start_ms: 0,
            end_ms: 320,
            definite: true,
        }],
        partials: vec![PartialSnapshot {
            at_ms: 120,
            text: "你".into(),
            stable_prefix_len: 1,
        }],
        logid: Some("log-1".into()),
        first_partial_ms: Some(120),
        total_latency_ms: 640,
        error_hint: None,
    };

    let value = serde_json::to_value(&resp).unwrap();
    let decoded: Response = serde_json::from_value(value).unwrap();

    assert_eq!(decoded, resp);
}
