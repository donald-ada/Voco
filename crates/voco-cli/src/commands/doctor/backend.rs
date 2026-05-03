//! Backend reachability. Phase 2 ships only the creds-present check;
//! Task 7 lands the real handshake (start()->stop()) once voco-asr is in.

use super::CheckResult;
use std::future::Future;
use std::time::{Duration, Instant};
use tokio;
use voco_config::{BackendChoice, ConfigIo};

const DOUBAO_PROBE_TIMEOUT: Duration = Duration::from_secs(10);

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
    let api_key_present = d.api_key.as_ref().is_some_and(|s| !s.is_empty());
    let old_console_present = !d.app_id.is_empty() && !d.access_token.is_empty();
    let mut missing = Vec::new();
    if !api_key_present && d.app_id.is_empty() {
        missing.push("app_id");
    }
    if !api_key_present && d.access_token.is_empty() {
        missing.push("access_token");
    }
    if d.endpoint.is_empty() {
        missing.push("endpoint");
    }
    if d.model_id.is_empty() {
        missing.push("model_id");
    }
    if missing.is_empty() {
        let auth = if api_key_present {
            "api_key".to_string()
        } else if old_console_present {
            format!("app_id={}", d.app_id)
        } else {
            "unknown".to_string()
        };
        CheckResult::Ok(format!("auth={}, model={}", auth, d.model_id))
    } else {
        CheckResult::Fail {
            headline: format!("missing field(s): {}", missing.join(", ")),
            fix: "voco config (interactive wizard) fills these".into(),
        }
    }
}

pub fn doubao_handshake() -> CheckResult {
    use super::skip_on_ci;
    if let Some(s) = skip_on_ci("CI=true (skip live network)") {
        return s;
    }
    let cfg = match ConfigIo::load_from(&ConfigIo::default_path()) {
        Ok(c) => c,
        Err(_) => return CheckResult::Skip("config unparseable".into()),
    };
    if !matches!(cfg.backend, BackendChoice::Doubao) {
        return CheckResult::Skip("backend != doubao".into());
    }
    if cfg.doubao.is_none() {
        return CheckResult::Skip("doubao creds missing (see above)".into());
    }
    let mut be = match voco_asr::build_backend(&cfg) {
        Ok(b) => b,
        Err(e) => {
            return CheckResult::Fail {
                headline: format!("backend build failed: {e}"),
                fix: "voco config (interactive wizard) re-checks creds".into(),
            }
        }
    };

    let rt = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(e) => {
            return CheckResult::Fail {
                headline: format!("tokio runtime: {e}"),
                fix: "this should never happen — file a bug".into(),
            }
        }
    };
    rt.block_on(async {
        let t0 = Instant::now();
        probe_with_timeout(DOUBAO_PROBE_TIMEOUT, async {
            if let Err(e) = be.start().await {
                return ProbeOutcome::StartFailed(e);
            }
            match be.stop().await {
                Err(voco_asr::AsrError::EmptyAudio) => ProbeOutcome::EmptyAudioOk,
                Err(e) => ProbeOutcome::Rejected(e),
                Ok(_) => ProbeOutcome::UnexpectedFinal,
            }
        })
        .await
        .with_elapsed(t0.elapsed())
    })
}

enum ProbeOutcome {
    EmptyAudioOk,
    StartFailed(voco_asr::AsrError),
    Rejected(voco_asr::AsrError),
    UnexpectedFinal,
    TimedOut,
}

impl ProbeOutcome {
    fn with_elapsed(self, elapsed: Duration) -> CheckResult {
        match self {
            Self::EmptyAudioOk => CheckResult::Ok(format!(
                "handshake ok ({}ms)",
                elapsed.as_millis()
            )),
            Self::StartFailed(e) => CheckResult::Fail {
                headline: format!("ws handshake failed: {e}"),
                fix: "verify endpoint/auth via `voco config show`; check network".into(),
            },
            Self::Rejected(e) => CheckResult::Fail {
                headline: format!("server rejected probe: {e}"),
                fix: "check resource_id, model_id, and that creds match the expected console flavor"
                    .into(),
            },
            Self::UnexpectedFinal => CheckResult::Ok(format!(
                "handshake ok ({}ms, empty final)",
                elapsed.as_millis()
            )),
            Self::TimedOut => CheckResult::Fail {
                headline: "Doubao handshake timed out".into(),
                fix: "check endpoint/network, or switch doubao.endpoint to the non-async bigmodel endpoint for the empty-audio doctor probe".into(),
            },
        }
    }
}

async fn probe_with_timeout<F>(timeout: Duration, probe: F) -> ProbeOutcome
where
    F: Future<Output = ProbeOutcome>,
{
    match tokio::time::timeout(timeout, probe).await {
        Ok(outcome) => outcome,
        Err(_) => ProbeOutcome::TimedOut,
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[tokio::test]
    async fn probe_timeout_returns_fail_instead_of_hanging() {
        let result = probe_with_timeout(Duration::from_millis(1), async {
            std::future::pending::<ProbeOutcome>().await
        })
        .await
        .with_elapsed(Duration::from_millis(1));

        assert!(matches!(
            result,
            CheckResult::Fail { headline, .. } if headline.contains("timed out")
        ));
    }

    #[test]
    fn empty_final_probe_result_counts_as_ok() {
        let result = ProbeOutcome::UnexpectedFinal.with_elapsed(Duration::from_millis(42));

        assert!(matches!(
            result,
            CheckResult::Ok(message) if message.contains("handshake ok")
        ));
    }
}
