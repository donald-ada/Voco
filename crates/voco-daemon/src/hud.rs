use serde::{Deserialize, Serialize};
use std::sync::Arc;
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum HudEvent {
    State {
        state: HudState,
        #[serde(skip_serializing_if = "Option::is_none")]
        message: Option<String>,
    },
    Amplitude {
        value: f32,
    },
}

impl HudEvent {
    pub fn state(state: HudState) -> Self {
        Self::State {
            state,
            message: None,
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self::State {
            state: HudState::Error,
            message: Some(message.into()),
        }
    }

    pub fn amplitude(value: f32) -> Self {
        Self::Amplitude {
            value: clamp_amplitude(value),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HudState {
    Hidden,
    Recording,
    Transcribing,
    Error,
}

#[derive(Debug, Error)]
pub enum HudError {
    #[error("serialize HUD event: {0}")]
    Serialize(#[from] serde_json::Error),
    #[error("spawn HUD helper: {0}")]
    Spawn(std::io::Error),
    #[error("write HUD event: {0}")]
    Write(std::io::Error),
    #[error("HUD helper missing")]
    MissingHelper,
}

pub trait HudSink: Send + Sync {
    fn send(&self, event: HudEvent) -> Result<(), HudError>;
}

pub type SharedHudSink = Arc<dyn HudSink>;

#[derive(Debug, Default)]
pub struct NoopHudSink;

impl HudSink for NoopHudSink {
    fn send(&self, _event: HudEvent) -> Result<(), HudError> {
        Ok(())
    }
}

pub fn noop_hud_sink() -> SharedHudSink {
    Arc::new(NoopHudSink)
}

pub fn event_to_json_line(event: &HudEvent) -> Result<String, HudError> {
    let mut line = serde_json::to_string(event)?;
    line.push('\n');
    Ok(line)
}

pub fn clamp_amplitude(value: f32) -> f32 {
    value.clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn state_event_serializes_as_swift_jsonl_shape() {
        let line = event_to_json_line(&HudEvent::state(HudState::Recording)).unwrap();
        assert_eq!(line, "{\"type\":\"state\",\"state\":\"recording\"}\n");
    }

    #[test]
    fn error_event_includes_message() {
        let line = event_to_json_line(&HudEvent::error("microphone unavailable")).unwrap();
        assert_eq!(
            line,
            "{\"type\":\"state\",\"state\":\"error\",\"message\":\"microphone unavailable\"}\n"
        );
    }

    #[test]
    fn amplitude_event_is_clamped_before_serializing() {
        let line = event_to_json_line(&HudEvent::amplitude(1.4)).unwrap();
        assert_eq!(line, "{\"type\":\"amplitude\",\"value\":1.0}\n");
    }
}
