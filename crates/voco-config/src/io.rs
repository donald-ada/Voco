//! Atomic load/save for `Config`.

use crate::schema::Config;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("TOML deserialize error: {0}")]
    Deserialize(#[from] toml::de::Error),
    #[error("TOML serialize error: {0}")]
    Serialize(#[from] toml::ser::Error),
    #[error("validation failed: {0}")]
    Validation(String),
}

pub struct ConfigIo;

impl ConfigIo {
    /// Default path: `~/.config/voco/config.toml`.
    pub fn default_path() -> PathBuf {
        directories::BaseDirs::new()
            .map(|b| {
                b.home_dir()
                    .join(".config")
                    .join("voco")
                    .join("config.toml")
            })
            .unwrap_or_else(|| PathBuf::from("./voco-config.toml"))
    }

    /// Load from `default_path()`. Returns `Config::default()` if file is absent.
    pub fn load() -> Result<Config, ConfigError> {
        Self::load_from(&Self::default_path())
    }

    pub fn load_from(path: &Path) -> Result<Config, ConfigError> {
        match fs::read_to_string(path) {
            Ok(s) => Ok(toml::from_str(&s)?),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Config::default()),
            Err(e) => Err(e.into()),
        }
    }

    /// Atomic write: write to `<path>.tmp` then rename.
    pub fn save(cfg: &Config) -> Result<(), ConfigError> {
        Self::save_to(&Self::default_path(), cfg)
    }

    pub fn save_to(path: &Path, cfg: &Config) -> Result<(), ConfigError> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }

        let content = toml::to_string_pretty(cfg)?;

        let tmp = path.with_extension(
            path.extension()
                .map(|e| format!("{}.tmp", e.to_string_lossy()))
                .unwrap_or_else(|| "tmp".to_string()),
        );

        {
            let mut f = fs::OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .open(&tmp)?;
            f.write_all(content.as_bytes())?;
            f.sync_all()?;
        }

        // chmod 600 to protect plaintext access_token (spec §3.1).
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600))?;
        }

        fs::rename(&tmp, path)?;
        Ok(())
    }
}
