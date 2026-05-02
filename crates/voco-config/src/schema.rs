//! Configuration schema. Pure data — no IO, no validation here.
//! IO lives in `io.rs`, validation lives in `validate.rs`.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Config {
    pub backend: BackendChoice,
    pub hotkey: HotkeyConfig,
    pub output: OutputConfig,
    pub hud: HudConfig,
    pub doubao: Option<DoubaoCreds>,
    pub sherpa: Option<SherpaPaths>,
    pub log_level: LogLevel,
    pub recording_max_duration_secs: u32,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum BackendChoice {
    Doubao,
    Sherpa,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HotkeyConfig {
    pub keycode: u16,
    pub modifiers: u32,
    pub display_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OutputConfig {
    pub mode: OutputMode,
    pub trim_trailing_punct: bool,
    pub auto_capitalize: bool,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OutputMode {
    InjectThenClipboard,
    ClipboardOnly,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HudConfig {
    pub style: HudStyle,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum HudStyle {
    Capsule,
    Minimal,
    Disabled,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DoubaoCreds {
    pub app_id: String,
    pub access_token: String,
    pub endpoint: String,
    pub model_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SherpaPaths {
    pub model_dir: PathBuf,
    pub num_threads: usize,
    pub provider: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

impl Config {
    /// Return a clone with secrets replaced by `"********"`. Used by
    /// `voco config show`. Length is masked too — never reveal token length.
    pub fn redacted_clone(&self) -> Self {
        let mut c = self.clone();
        if let Some(d) = c.doubao.as_mut() {
            if !d.access_token.is_empty() {
                d.access_token = "********".to_string();
            }
        }
        c
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            backend: BackendChoice::Doubao,
            hotkey: HotkeyConfig {
                // Right Command. CGKeyCode 54 = kVK_RightCommand.
                keycode: 54,
                modifiers: 0,
                display_name: "Right Command".to_string(),
            },
            output: OutputConfig {
                mode: OutputMode::InjectThenClipboard,
                trim_trailing_punct: false,
                auto_capitalize: false,
            },
            hud: HudConfig {
                style: HudStyle::Capsule,
            },
            doubao: None,
            sherpa: None,
            log_level: LogLevel::Info,
            recording_max_duration_secs: 60,
        }
    }
}
