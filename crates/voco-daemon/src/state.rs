//! Daemon state machine. Phase 1 only uses `Idle`; later phases add the rest.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum DaemonState {
    Idle,
    Recording,
    Transcribing,
    Injecting,
    Error,
}

impl DaemonState {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Recording => "recording",
            Self::Transcribing => "transcribing",
            Self::Injecting => "injecting",
            Self::Error => "error",
        }
    }
}
