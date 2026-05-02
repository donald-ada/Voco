//! Filesystem paths used by the daemon. Single source of truth so cli + tests
//! agree on where the socket and log live.
//!
//! When `$VOCO_HOME` is set, *all* of `application_support_dir`, `logs_dir`,
//! and `ConfigIo::default_path()` resolve under it. Tests + dev set this to a
//! tempdir; production users never set it.

use directories::BaseDirs;
use std::path::PathBuf;

/// Read $VOCO_HOME on each call (not memoized) — tests change env between cases.
fn voco_home_root() -> Option<PathBuf> {
    std::env::var_os("VOCO_HOME").map(PathBuf::from)
}

pub fn application_support_dir() -> PathBuf {
    if let Some(root) = voco_home_root() {
        return root.join("data");
    }
    BaseDirs::new()
        .map(|b| b.data_dir().join("voco"))
        .unwrap_or_else(|| PathBuf::from("./voco-data"))
}

pub fn logs_dir() -> PathBuf {
    if let Some(root) = voco_home_root() {
        return root.join("logs");
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    // env mutation is process-global; serialize so tests don't race each other.
    static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    fn with_voco_home<F: FnOnce(&std::path::Path)>(f: F) {
        let _g = LOCK.lock().unwrap();
        let tmp = tempfile::tempdir().unwrap();
        std::env::set_var("VOCO_HOME", tmp.path());
        f(tmp.path());
        std::env::remove_var("VOCO_HOME");
    }

    #[test]
    fn voco_home_overrides_all_paths() {
        with_voco_home(|root| {
            assert_eq!(application_support_dir(), root.join("data"));
            assert_eq!(logs_dir(), root.join("logs"));
            assert_eq!(default_socket_path(), root.join("data").join("voco.sock"));
            assert_eq!(default_log_file(), root.join("logs").join("voco.log"));
        });
    }

    #[test]
    fn unset_voco_home_falls_back_to_base_dirs() {
        let _g = LOCK.lock().unwrap();
        std::env::remove_var("VOCO_HOME");
        // Just assert the paths don't contain "VOCO_HOME" literally — the exact
        // BaseDirs answer depends on the host.
        let p = application_support_dir();
        assert!(!p.to_string_lossy().contains("VOCO_HOME"));
        assert!(p.ends_with("voco"));
    }
}
