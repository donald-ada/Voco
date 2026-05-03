//! Daemon-side checks: socket reachable + hotkey installed.

use super::{skip_on_ci, CheckResult};
use std::os::unix::net::UnixStream;
use voco_config::ConfigIo;
use voco_daemon::default_socket_path;
use voco_hotkey::HotkeyManager;

pub fn socket_reachable() -> CheckResult {
    let p = default_socket_path();
    match UnixStream::connect(&p) {
        Ok(_) => CheckResult::Ok(p.display().to_string()),
        Err(_) => CheckResult::Warn {
            headline: format!("daemon not running ({})", p.display()),
            hint: "voco daemon start".into(),
        },
    }
}

pub fn hotkey_installed() -> CheckResult {
    if let Some(s) = skip_on_ci("CI=true") {
        return s;
    }

    let cfg = match ConfigIo::load() {
        Ok(cfg) => cfg.hotkey,
        Err(err) => {
            return CheckResult::Fail {
                headline: "config unavailable for hotkey probe".into(),
                fix: format!("fix config.toml first ({err})"),
            };
        }
    };
    let (tx, _rx) = tokio::sync::mpsc::channel(1);
    match HotkeyManager::install(&cfg, tx) {
        Ok(manager) => {
            let installed = manager.is_installed();
            drop(manager);
            if installed {
                CheckResult::Ok(format!("event tap installed ({})", cfg.display_name))
            } else {
                CheckResult::Fail {
                    headline: "event tap not active".into(),
                    fix: "restart voco doctor after granting Accessibility/Input Monitoring".into(),
                }
            }
        }
        Err(err) => CheckResult::Fail {
            headline: "event tap install failed".into(),
            fix: format!(
                "{err}; System Settings → Privacy & Security → Accessibility/Input Monitoring → enable the responsible terminal/app"
            ),
        },
    }
}
