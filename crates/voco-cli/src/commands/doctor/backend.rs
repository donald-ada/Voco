//! Backend reachability. Phase 2 ships only the creds-present check;
//! Task 7 lands the real handshake (start()->stop()) once voco-asr is in.

use super::CheckResult;
use voco_config::{BackendChoice, ConfigIo};

pub fn doubao_creds_present() -> CheckResult {
    let cfg = match ConfigIo::load_from(&ConfigIo::default_path()) {
        Ok(c) => c,
        Err(_) => return CheckResult::Skip("config unparseable".into()),
    };
    if !matches!(cfg.backend, BackendChoice::Doubao) {
        return CheckResult::Skip("backend != doubao".into());
    }
    let d = match cfg.doubao.as_ref() {
        None => {
            return CheckResult::Fail {
                headline: "[doubao] section missing".into(),
                fix: "voco config set doubao.app_id <your APP ID> (and access_token, endpoint, model_id)".into(),
            };
        }
        Some(d) => d,
    };
    let mut missing = Vec::new();
    if d.app_id.is_empty() {
        missing.push("app_id");
    }
    if d.access_token.is_empty() {
        missing.push("access_token");
    }
    if d.endpoint.is_empty() {
        missing.push("endpoint");
    }
    if d.model_id.is_empty() {
        missing.push("model_id");
    }
    if missing.is_empty() {
        CheckResult::Ok(format!("app_id={}, model={}", d.app_id, d.model_id))
    } else {
        CheckResult::Fail {
            headline: format!("missing field(s): {}", missing.join(", ")),
            fix: "voco config (interactive wizard) fills these".into(),
        }
    }
}

pub fn doubao_handshake() -> CheckResult {
    CheckResult::Skip("real handshake wired in Task 7 (voco-asr)".into())
}

pub fn sherpa() -> CheckResult {
    let cfg = match ConfigIo::load_from(&ConfigIo::default_path()) {
        Ok(c) => c,
        Err(_) => return CheckResult::Skip("config unparseable".into()),
    };
    if matches!(cfg.backend, BackendChoice::Sherpa) {
        CheckResult::Warn {
            headline: "sherpa selected but not implemented in MVP".into(),
            hint: "switch to doubao with `voco config set backend doubao`".into(),
        }
    } else {
        CheckResult::Skip("not selected".into())
    }
}
