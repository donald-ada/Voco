//! Validate that a `Config` is internally consistent and all referenced
//! resources (creds, model dirs) are usable.

use crate::schema::*;

#[derive(Debug, Clone)]
pub struct ValidationError {
    pub kind: ValidationKind,
    pub message: String,
}

#[derive(Debug, Clone)]
pub enum ValidationKind {
    DoubaoCredsMissing,
    DoubaoCredsEmpty(&'static str),
    SherpaPathsMissing,
    SherpaModelDirMissing,
    SherpaThreadsOutOfRange,
    RecordingMaxDurationOutOfRange,
    HotkeyKeycodeUnset,
}

impl Config {
    /// Returns all validation errors. Empty Vec means OK.
    pub fn validate(&self) -> Vec<ValidationError> {
        let mut errors = Vec::new();

        match self.backend {
            BackendChoice::Doubao => match &self.doubao {
                None => errors.push(ValidationError {
                    kind: ValidationKind::DoubaoCredsMissing,
                    message: "backend=doubao requires [doubao] section".into(),
                }),
                Some(c) => {
                    if c.app_id.is_empty() {
                        errors.push(ValidationError {
                            kind: ValidationKind::DoubaoCredsEmpty("app_id"),
                            message: "doubao.app_id must not be empty".into(),
                        });
                    }
                    if c.access_token.is_empty() {
                        errors.push(ValidationError {
                            kind: ValidationKind::DoubaoCredsEmpty("access_token"),
                            message: "doubao.access_token must not be empty".into(),
                        });
                    }
                    if c.endpoint.is_empty() {
                        errors.push(ValidationError {
                            kind: ValidationKind::DoubaoCredsEmpty("endpoint"),
                            message: "doubao.endpoint must not be empty".into(),
                        });
                    }
                }
            },
            BackendChoice::Sherpa => match &self.sherpa {
                None => errors.push(ValidationError {
                    kind: ValidationKind::SherpaPathsMissing,
                    message:
                        "backend=sherpa requires [sherpa] section (note: not implemented in MVP)"
                            .into(),
                }),
                Some(s) => {
                    if !s.model_dir.is_dir() {
                        errors.push(ValidationError {
                            kind: ValidationKind::SherpaModelDirMissing,
                            message: format!(
                                "sherpa.model_dir does not exist: {}",
                                s.model_dir.display()
                            ),
                        });
                    }
                    if s.num_threads == 0 || s.num_threads > 32 {
                        errors.push(ValidationError {
                            kind: ValidationKind::SherpaThreadsOutOfRange,
                            message: format!(
                                "sherpa.num_threads must be in 1..=32, got {}",
                                s.num_threads
                            ),
                        });
                    }
                }
            },
        }

        if self.recording_max_duration_secs == 0 || self.recording_max_duration_secs > 600 {
            errors.push(ValidationError {
                kind: ValidationKind::RecordingMaxDurationOutOfRange,
                message: format!(
                    "recording_max_duration_secs must be in 1..=600, got {}",
                    self.recording_max_duration_secs
                ),
            });
        }

        if self.hotkey.keycode == 0 {
            errors.push(ValidationError {
                kind: ValidationKind::HotkeyKeycodeUnset,
                message: "hotkey.keycode 0 is reserved (kVK_ANSI_A) — pick a real key".into(),
            });
        }

        errors
    }
}
