use std::collections::VecDeque;

use voco_ipc::protocol::{RecentError, StatusInfo};

use crate::session::RecordingPayload;
use crate::DaemonState;

const MAX_RECENT_ERRORS: usize = 10;

pub struct Stats {
    pub sessions_total: u64,
    pub sessions_succeeded: u64,
    pub sessions_failed: u64,
    pub last_session_latency_ms: Option<u64>,
    pub last_first_partial_ms: Option<u64>,
    pub last_logid: Option<String>,
    pub recent_errors: VecDeque<RecentError>,
    pub backend_in_use: String,
    backend_name: String,
}

impl Stats {
    pub fn new(backend_in_use: impl Into<String>) -> Self {
        let backend_name = backend_in_use.into();
        Self {
            sessions_total: 0,
            sessions_succeeded: 0,
            sessions_failed: 0,
            last_session_latency_ms: None,
            last_first_partial_ms: None,
            last_logid: None,
            recent_errors: VecDeque::new(),
            backend_in_use: backend_name.clone(),
            backend_name,
        }
    }

    pub fn record_success(&mut self, payload: &RecordingPayload) {
        self.sessions_total += 1;
        self.sessions_succeeded += 1;
        self.last_session_latency_ms = Some(payload.total_latency_ms);
        self.last_first_partial_ms = payload.first_partial_ms;
        self.last_logid = payload.logid.clone();
        if let Some(logid) = &payload.logid {
            self.backend_in_use = format!("{} (logid={logid})", self.backend_name);
        }
    }

    pub fn record_failure(&mut self, message: impl Into<String>, timestamp_unix_secs: u64) {
        self.sessions_total += 1;
        self.sessions_failed += 1;
        self.recent_errors.push_back(RecentError {
            timestamp_unix_secs,
            message: message.into(),
        });
        while self.recent_errors.len() > MAX_RECENT_ERRORS {
            self.recent_errors.pop_front();
        }
    }

    pub fn to_status_info(
        &self,
        state: DaemonState,
        backend: impl Into<String>,
        uptime_secs: u64,
    ) -> StatusInfo {
        StatusInfo {
            state: state.as_str().into(),
            backend: backend.into(),
            backend_in_use: self.backend_in_use.clone(),
            uptime_secs,
            sessions_total: self.sessions_total,
            sessions_succeeded: self.sessions_succeeded,
            sessions_failed: self.sessions_failed,
            last_session_latency_ms: self.last_session_latency_ms,
            last_first_partial_ms: self.last_first_partial_ms,
            last_session_logid: self.last_logid.clone(),
            recent_errors: self.recent_errors.iter().cloned().collect(),
        }
    }
}
