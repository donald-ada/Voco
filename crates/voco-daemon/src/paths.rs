//! Filesystem paths used by the daemon. Single source of truth so cli + tests
//! agree on where the socket and log live.

use directories::BaseDirs;
use std::path::PathBuf;

pub fn application_support_dir() -> PathBuf {
    BaseDirs::new()
        .map(|b| b.data_dir().join("voco"))
        .unwrap_or_else(|| PathBuf::from("./voco-data"))
}

pub fn logs_dir() -> PathBuf {
    BaseDirs::new()
        .map(|b| b.home_dir().join("Library").join("Logs").join("voco"))
        .unwrap_or_else(|| PathBuf::from("./voco-logs"))
}

pub fn default_socket_path() -> PathBuf {
    application_support_dir().join("voco.sock")
}

pub fn default_log_file() -> PathBuf {
    logs_dir().join("voco.log")
}
