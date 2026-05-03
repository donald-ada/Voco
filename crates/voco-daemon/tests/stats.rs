use voco_daemon::session::RecordingPayload;
use voco_daemon::stats::Stats;
use voco_daemon::DaemonState;
use voco_ipc::protocol::Segment;

fn payload(
    total_latency_ms: u64,
    first_partial_ms: Option<u64>,
    logid: Option<&str>,
) -> RecordingPayload {
    RecordingPayload {
        text: "final".into(),
        segments: vec![Segment {
            text: "final".into(),
            start_ms: 0,
            end_ms: 300,
            definite: true,
        }],
        partials: vec![],
        logid: logid.map(str::to_string),
        first_partial_ms,
        total_latency_ms,
        error_hint: None,
    }
}

#[test]
fn new_stats_render_zero_session_status() {
    let stats = Stats::new("doubao");

    let status = stats.to_status_info(DaemonState::Idle, "doubao", 42);

    assert_eq!(status.state, "idle");
    assert_eq!(status.backend, "doubao");
    assert_eq!(status.backend_in_use, "doubao");
    assert_eq!(status.uptime_secs, 42);
    assert_eq!(status.sessions_total, 0);
    assert_eq!(status.sessions_succeeded, 0);
    assert_eq!(status.sessions_failed, 0);
    assert_eq!(status.last_session_latency_ms, None);
    assert_eq!(status.last_first_partial_ms, None);
    assert_eq!(status.last_session_logid, None);
    assert!(status.recent_errors.is_empty());
}

#[test]
fn record_success_updates_counters_latency_and_logid() {
    let mut stats = Stats::new("doubao");

    stats.record_success(&payload(640, Some(120), Some("log-1")));

    let status = stats.to_status_info(DaemonState::Idle, "doubao", 1);
    assert_eq!(status.sessions_total, 1);
    assert_eq!(status.sessions_succeeded, 1);
    assert_eq!(status.sessions_failed, 0);
    assert_eq!(status.last_session_latency_ms, Some(640));
    assert_eq!(status.last_first_partial_ms, Some(120));
    assert_eq!(status.last_session_logid.as_deref(), Some("log-1"));
    assert_eq!(status.backend_in_use, "doubao (logid=log-1)");
}

#[test]
fn record_failure_bumps_failed_and_bounds_recent_errors_to_ten() {
    let mut stats = Stats::new("doubao");

    for i in 0..12 {
        stats.record_failure(format!("error-{i}"), 1_700_000_000 + i);
    }

    let status = stats.to_status_info(DaemonState::Error, "doubao", 1);
    assert_eq!(status.sessions_total, 12);
    assert_eq!(status.sessions_succeeded, 0);
    assert_eq!(status.sessions_failed, 12);
    assert_eq!(status.recent_errors.len(), 10);
    assert_eq!(status.recent_errors[0].message, "error-2");
    assert_eq!(status.recent_errors[9].message, "error-11");
}
