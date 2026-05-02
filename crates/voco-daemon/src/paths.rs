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

/// The daemon's tracing-appender writes daily-rotated files like
/// `voco.2026-05-02.log`. This returns the **most recent** one (or
/// `voco.log` if no dated file exists yet — that case lasts only until
/// the daemon emits its first event).
pub fn latest_log_file() -> Option<PathBuf> {
    let dir = logs_dir();
    let mut entries: Vec<_> = std::fs::read_dir(&dir)
        .ok()?
        .filter_map(|e| e.ok())
        .filter(|e| {
            let name = e.file_name();
            let s = name.to_string_lossy();
            s.starts_with("voco") && s.ends_with(".log")
        })
        .collect();
    entries.sort_by_key(|e| {
        e.metadata()
            .and_then(|m| m.modified())
            .unwrap_or(std::time::SystemTime::UNIX_EPOCH)
    });
    entries.pop().map(|e| e.path())
}

/// Phase 1's "the log lives here" hint, used in `voco daemon start` output.
/// Returns the directory; the latest file is resolved at read time via
/// `latest_log_file`.
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
    fn latest_log_file_picks_newest_dated() {
        with_voco_home(|root| {
            let logs = root.join("logs");
            std::fs::create_dir_all(&logs).unwrap();
            // Write three files, then bump mtime on the middle one.
            for name in [
                "voco.2026-04-30.log",
                "voco.2026-05-01.log",
                "voco.2026-05-02.log",
            ] {
                std::fs::write(logs.join(name), b"x").unwrap();
            }
            // Now touch the last one to ensure mtime ordering.
            let target = logs.join("voco.2026-05-02.log");
            let ts = std::time::SystemTime::now();
            filetime::set_file_mtime(&target, filetime::FileTime::from_system_time(ts)).unwrap();
            // Older files predate this by however many ms it takes — sleep
            // to guarantee strict ordering on filesystems with coarse mtime.
            std::thread::sleep(std::time::Duration::from_millis(20));
            for name in ["voco.2026-04-30.log", "voco.2026-05-01.log"] {
                let p = logs.join(name);
                let earlier = ts - std::time::Duration::from_secs(86400);
                filetime::set_file_mtime(&p, filetime::FileTime::from_system_time(earlier))
                    .unwrap();
            }
            let picked = latest_log_file().unwrap();
            assert_eq!(picked.file_name().unwrap(), "voco.2026-05-02.log");
        });
    }

    #[test]
    fn latest_log_file_returns_none_when_dir_missing() {
        with_voco_home(|_root| {
            // logs/ does not exist yet
            assert!(latest_log_file().is_none());
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
