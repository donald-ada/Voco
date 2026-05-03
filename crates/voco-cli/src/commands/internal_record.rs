//! `voco _internal_record` — Phase 3 dev-only one-shot recording trigger.

use anyhow::{bail, Result};
use voco_daemon::default_socket_path;
use voco_ipc::client::IpcClient;
use voco_ipc::protocol::{Request, Response};

pub fn run(duration: String, show_partials: bool, debug_amp: bool) -> Result<()> {
    let _ = debug_amp;
    let secs = parse_duration_secs(&duration)?;
    let duration_ms = secs.saturating_mul(1_000);

    println!("recording for {secs}s ...");
    let mut client = IpcClient::connect(default_socket_path())?;
    let response = client.call(&Request::RecordingOnce {
        duration_ms,
        include_partials: show_partials,
    })?;

    println!("transcribing ...");
    match response {
        Response::RecordingResult {
            text,
            partials,
            logid,
            first_partial_ms,
            total_latency_ms,
            error_hint,
            ..
        } => {
            if show_partials {
                for (idx, partial) in partials.iter().enumerate() {
                    println!(
                        "partial[{}] (stable={}): \"{}\"",
                        idx + 1,
                        partial.stable_prefix_len,
                        partial.text
                    );
                }
            }
            println!("final: \"{text}\"");
            if let Some(logid) = logid {
                println!("logid: {logid}");
            }
            if let Some(hint) = error_hint {
                println!("warning: {hint}");
            }
            match first_partial_ms {
                Some(ms) => println!("timing: first partial {ms}ms, total {total_latency_ms}ms"),
                None => println!("timing: total {total_latency_ms}ms"),
            }
            Ok(())
        }
        Response::Error { message } => bail!("{message}"),
        other => bail!("unexpected response: {other:?}"),
    }
}

fn parse_duration_secs(raw: &str) -> Result<u32> {
    let trimmed = raw.trim();
    let number = trimmed.strip_suffix('s').unwrap_or(trimmed);
    let secs: u32 = number
        .parse()
        .map_err(|_| anyhow::anyhow!("duration must be seconds, got `{raw}`"))?;
    if secs == 0 {
        bail!("duration must be greater than 0");
    }
    Ok(secs)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_duration_accepts_plain_seconds_or_s_suffix() {
        assert_eq!(parse_duration_secs("3").unwrap(), 3);
        assert_eq!(parse_duration_secs("3s").unwrap(), 3);
    }

    #[test]
    fn parse_duration_rejects_zero() {
        assert!(parse_duration_secs("0").is_err());
    }
}
