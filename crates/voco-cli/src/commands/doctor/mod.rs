//! `voco doctor` — five groups of self-checks that report ✓ / ⚠ / ✗ / -.
//!
//! Each check is a pure function returning `CheckResult`. The driver
//! collects them, prints one section per group, and exits 0 unless any
//! check is `Fail`.

use anyhow::Result;

pub mod backend;
pub mod config;
pub mod daemon;
pub mod microphone;
pub mod permissions;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CheckResult {
    Ok(String),
    Warn { headline: String, hint: String },
    Fail { headline: String, fix: String },
    Skip(String),
}

pub struct Check {
    pub group: &'static str,
    pub name: &'static str,
    pub result: CheckResult,
}

pub fn run() -> Result<()> {
    let checks = collect_checks();
    print_report(&checks);
    let failed = checks
        .iter()
        .any(|c| matches!(c.result, CheckResult::Fail { .. }));
    if failed {
        std::process::exit(1);
    }
    Ok(())
}

fn collect_checks() -> Vec<Check> {
    let mut out = Vec::new();
    push(
        &mut out,
        "Permissions",
        "Microphone (TCC)",
        permissions::microphone_tcc(),
    );
    push(
        &mut out,
        "Permissions",
        "Accessibility",
        permissions::accessibility(),
    );
    push(
        &mut out,
        "Permissions",
        "Input Monitoring",
        permissions::input_monitoring(),
    );

    push(&mut out, "Config", "File present", config::file_present());
    push(&mut out, "Config", "Schema valid", config::schema_valid());
    push(
        &mut out,
        "Config",
        "Semantic valid",
        config::semantic_valid(),
    );

    push(
        &mut out,
        "Daemon",
        "Socket reachable",
        daemon::socket_reachable(),
    );
    push(
        &mut out,
        "Daemon",
        "Hotkey installed",
        daemon::hotkey_installed(),
    );

    push(
        &mut out,
        "Microphone",
        "Default input device",
        microphone::default_input_device(),
    );

    push(
        &mut out,
        "Backend",
        "Doubao credentials",
        backend::doubao_creds_present(),
    );
    push(
        &mut out,
        "Backend",
        "Doubao handshake",
        backend::doubao_handshake(),
    );
    push(&mut out, "Backend", "Sherpa", backend::sherpa());

    out
}

fn push(out: &mut Vec<Check>, group: &'static str, name: &'static str, result: CheckResult) {
    out.push(Check {
        group,
        name,
        result,
    });
}

pub fn print_report(checks: &[Check]) {
    let mut last_group = "";
    for c in checks {
        if c.group != last_group {
            if !last_group.is_empty() {
                println!();
            }
            println!("{}", c.group);
            last_group = c.group;
        }
        match &c.result {
            CheckResult::Ok(detail) => {
                if detail.is_empty() {
                    println!("  ✓ {}", c.name);
                } else {
                    println!("  ✓ {} ({})", c.name, detail);
                }
            }
            CheckResult::Warn { headline, hint } => {
                println!("  ⚠ {}: {}", c.name, headline);
                if !hint.is_empty() {
                    println!("      → {}", hint);
                }
            }
            CheckResult::Fail { headline, fix } => {
                println!("  ✗ {}: {}", c.name, headline);
                if !fix.is_empty() {
                    println!("      → {}", fix);
                }
            }
            CheckResult::Skip(why) => {
                println!("  - {} ({})", c.name, why);
            }
        }
    }
    println!();
    let (ok, warn, fail, skip) = tally(checks);
    println!("Summary: {ok} ok / {warn} warn / {fail} fail / {skip} skip");
}

fn tally(checks: &[Check]) -> (usize, usize, usize, usize) {
    let mut o = 0;
    let mut w = 0;
    let mut f = 0;
    let mut s = 0;
    for c in checks {
        match c.result {
            CheckResult::Ok(_) => o += 1,
            CheckResult::Warn { .. } => w += 1,
            CheckResult::Fail { .. } => f += 1,
            CheckResult::Skip(_) => s += 1,
        }
    }
    (o, w, f, s)
}

/// On CI, TCC + audio probes can't run (no GUI, no audio device). Skip them.
pub fn skip_on_ci(why: &str) -> Option<CheckResult> {
    if std::env::var_os("CI").is_some() {
        Some(CheckResult::Skip(why.to_string()))
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::OsString;
    use std::sync::Mutex;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    struct EnvGuard {
        key: &'static str,
        previous: Option<OsString>,
    }

    impl EnvGuard {
        fn set(key: &'static str, value: &str) -> Self {
            let previous = std::env::var_os(key);
            std::env::set_var(key, value);
            Self { key, previous }
        }

        fn unset(key: &'static str) -> Self {
            let previous = std::env::var_os(key);
            std::env::remove_var(key);
            Self { key, previous }
        }
    }

    impl Drop for EnvGuard {
        fn drop(&mut self) {
            match &self.previous {
                Some(value) => std::env::set_var(self.key, value),
                None => std::env::remove_var(self.key),
            }
        }
    }

    fn mk(group: &'static str, name: &'static str, result: CheckResult) -> Check {
        Check {
            group,
            name,
            result,
        }
    }

    #[test]
    fn tally_counts_each_variant() {
        let checks = vec![
            mk("A", "1", CheckResult::Ok("".into())),
            mk(
                "A",
                "2",
                CheckResult::Warn {
                    headline: "x".into(),
                    hint: "".into(),
                },
            ),
            mk(
                "A",
                "3",
                CheckResult::Fail {
                    headline: "x".into(),
                    fix: "".into(),
                },
            ),
            mk("A", "4", CheckResult::Skip("x".into())),
            mk("A", "5", CheckResult::Ok("y".into())),
        ];
        assert_eq!(tally(&checks), (2, 1, 1, 1));
    }

    #[test]
    fn skip_on_ci_when_set() {
        let _lock = ENV_LOCK.lock().unwrap();
        let _guard = EnvGuard::set("CI", "1");
        assert!(matches!(skip_on_ci("test"), Some(CheckResult::Skip(_))));
    }

    #[test]
    fn skip_on_ci_returns_none_when_unset() {
        let _lock = ENV_LOCK.lock().unwrap();
        let _guard = EnvGuard::unset("CI");
        assert!(skip_on_ci("test").is_none());
    }
}
