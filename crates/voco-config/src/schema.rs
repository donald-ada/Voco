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
    /// Old-console: pair `app_id` with `access_token`. New-console: leave
    /// these empty and set `api_key` instead.
    pub app_id: String,
    pub access_token: String,

    /// New-console single-key auth. When `Some`, `app_id`/`access_token`
    /// can be empty. Phase 2 supports either auth mode.
    #[serde(default)]
    pub api_key: Option<String>,

    pub endpoint: String,
    pub model_id: String,

    /// Volcengine resource ID — selects model SKU & billing tier. Default
    /// is Doubao 1.0 hourly. Override for 2.0 (`volc.seedasr.sauc.duration`)
    /// or concurrent tiers.
    #[serde(default = "default_resource_id")]
    pub resource_id: String,
}

fn default_resource_id() -> String {
    "volc.bigasr.sauc.duration".to_string()
}

impl Default for DoubaoCreds {
    fn default() -> Self {
        Self {
            app_id: String::new(),
            access_token: String::new(),
            api_key: None,
            endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel".to_string(),
            model_id: "bigmodel".to_string(),
            resource_id: default_resource_id(),
        }
    }
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
            if let Some(k) = d.api_key.as_mut() {
                if !k.is_empty() {
                    *k = "********".to_string();
                }
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
