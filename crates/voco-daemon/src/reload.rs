//! Pure functions used by `Orchestrator::handle(ReloadConfig)`. Kept out
//! of `orchestrator.rs` so they're directly unit-testable.

use voco_config::{Config, ValidationError};

/// Compare old vs new config; emit warning strings for fields that
/// **cannot** be hot-reloaded (require `voco daemon restart`).
pub fn diff_for_restart(old: &Config, new: &Config) -> Vec<String> {
    let mut out = Vec::new();
    if old.backend != new.backend {
        out.push(format!(
            "backend changed ({:?} → {:?}); restart daemon to swap ASR backend",
            old.backend, new.backend
        ));
    }
    if old.hotkey != new.hotkey {
        out.push(
            "hotkey changed; restart daemon (CGEventTap re-install lands in Phase 4)".to_string(),
        );
    }
    if old.log_level != new.log_level {
        out.push(format!(
            "log_level changed ({:?} → {:?}); EnvFilter is set at startup, restart to apply",
            old.log_level, new.log_level
        ));
    }
    out
}

pub fn format_validation(errs: &[ValidationError]) -> String {
    let parts: Vec<String> = errs.iter().map(|e| e.to_string()).collect();
    format!("validation failed: {}", parts.join("; "))
}

#[cfg(test)]
mod tests {
    use super::*;
    use voco_config::*;

    #[test]
    fn no_changes_means_no_warnings() {
        let c = Config::default();
        assert!(diff_for_restart(&c, &c).is_empty());
    }

    #[test]
    fn backend_swap_warns() {
        let a = Config {
            backend: BackendChoice::Doubao,
            ..Default::default()
        };
        let mut b = a.clone();
        b.backend = BackendChoice::Sherpa;
        let w = diff_for_restart(&a, &b);
        assert_eq!(w.len(), 1);
        assert!(w[0].contains("backend"));
    }

    #[test]
    fn hotkey_change_warns() {
        let a = Config::default();
        let mut b = a.clone();
        b.hotkey.keycode = 80;
        b.hotkey.display_name = "F19".into();
        let w = diff_for_restart(&a, &b);
        assert_eq!(w.len(), 1);
        assert!(w[0].contains("hotkey"));
    }

    #[test]
    fn output_change_does_not_warn() {
        // output.* IS hot-reloadable, so no warning
        let a = Config::default();
        let mut b = a.clone();
        b.output.mode = OutputMode::ClipboardOnly;
        b.output.trim_trailing_punct = true;
        assert!(diff_for_restart(&a, &b).is_empty());
    }

    #[test]
    fn doubao_creds_change_does_not_warn() {
        // Picked up on next backend.start() — no restart needed
        let a = Config::default();
        let mut b = a.clone();
        b.doubao = Some(DoubaoCreds {
            app_id: "X".into(),
            access_token: "Y".into(),
            endpoint: "Z".into(),
            model_id: "M".into(),
        });
        assert!(diff_for_restart(&a, &b).is_empty());
    }

    #[test]
    fn log_level_change_warns() {
        let a = Config::default();
        let mut b = a.clone();
        b.log_level = LogLevel::Debug;
        let w = diff_for_restart(&a, &b);
        assert_eq!(w.len(), 1);
        assert!(w[0].contains("log_level"));
    }

    #[test]
    fn multiple_changes_stack() {
        let a = Config {
            backend: BackendChoice::Doubao,
            ..Default::default()
        };
        let mut b = a.clone();
        b.backend = BackendChoice::Sherpa;
        b.hotkey.keycode = 80;
        b.hotkey.display_name = "F19".into();
        b.log_level = LogLevel::Trace;
        let w = diff_for_restart(&a, &b);
        assert_eq!(w.len(), 3);
    }
}
