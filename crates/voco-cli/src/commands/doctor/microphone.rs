//! Microphone enumeration via cpal. Detects "no input device available";
//! does NOT differentiate TCC-denied from no-device — that lands later when
//! the audio pipeline actually needs to open a stream.

use super::{skip_on_ci, CheckResult};
use cpal::traits::{DeviceTrait, HostTrait};

pub fn default_input_device() -> CheckResult {
    if let Some(s) = skip_on_ci("CI=true (no audio device)") {
        return s;
    }
    let host = cpal::default_host();
    let dev = match host.default_input_device() {
        Some(d) => d,
        None => {
            return CheckResult::Fail {
                headline: "no default input device".into(),
                fix: "plug in a microphone or check System Settings → Sound → Input".into(),
            };
        }
    };
    let name = dev
        .name()
        .unwrap_or_else(|_| "<unknown device>".to_string());

    // Verify at least one input config exists.
    match dev.supported_input_configs() {
        Ok(mut iter) => {
            if iter.next().is_some() {
                CheckResult::Ok(name)
            } else {
                CheckResult::Fail {
                    headline: format!("{name} reports no supported input configs"),
                    fix: "try a different input device".into(),
                }
            }
        }
        Err(e) => CheckResult::Fail {
            headline: format!("{name}: {e}"),
            fix: "check microphone permissions or restart the audio daemon".into(),
        },
    }
}
