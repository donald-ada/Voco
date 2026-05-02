//! Config-file checks: existence, schema parse, semantic validate.

use super::CheckResult;
use voco_config::ConfigIo;

pub fn file_present() -> CheckResult {
    let p = ConfigIo::default_path();
    if p.exists() {
        CheckResult::Ok(p.display().to_string())
    } else {
        CheckResult::Warn {
            headline: format!("{} missing — running on defaults", p.display()),
            hint: "run `voco config` to create one".into(),
        }
    }
}

pub fn schema_valid() -> CheckResult {
    let p = ConfigIo::default_path();
    match ConfigIo::load_from(&p) {
        Ok(_) => CheckResult::Ok(String::new()),
        Err(e) => CheckResult::Fail {
            headline: format!("{} unparseable: {e}", p.display()),
            fix: "fix the TOML by hand or run `voco config reset --yes`".into(),
        },
    }
}

pub fn semantic_valid() -> CheckResult {
    let p = ConfigIo::default_path();
    let cfg = match ConfigIo::load_from(&p) {
        Ok(c) => c,
        Err(_) => {
            return CheckResult::Skip("schema invalid (see above)".into());
        }
    };
    let errs = cfg.validate();
    if errs.is_empty() {
        CheckResult::Ok(String::new())
    } else {
        let headline = format!("{} issue(s)", errs.len());
        let fix = errs
            .iter()
            .map(|e| e.to_string())
            .collect::<Vec<_>>()
            .join("; ");
        CheckResult::Fail { headline, fix }
    }
}
