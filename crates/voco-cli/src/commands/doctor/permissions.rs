//! TCC + IOKit permission introspection. Read-only — never prompts.
//! Phase 4's daemon startup will own the Accessibility prompt.

use super::{skip_on_ci, CheckResult};

#[cfg(target_os = "macos")]
#[link(name = "ApplicationServices", kind = "framework")]
extern "C" {
    fn AXIsProcessTrusted() -> bool;
}

#[cfg(target_os = "macos")]
#[link(name = "IOKit", kind = "framework")]
extern "C" {
    fn IOHIDCheckAccess(request: u32) -> u32;
}

#[cfg(target_os = "macos")]
const KIO_HID_REQUEST_TYPE_LISTEN_EVENT: u32 = 1;

#[cfg(target_os = "macos")]
const KIO_HID_ACCESS_TYPE_GRANTED: u32 = 0;

pub fn microphone_tcc() -> CheckResult {
    if let Some(s) = skip_on_ci("CI=true") {
        return s;
    }
    // Phase 2 stops at "device enumerable" — see microphone::default_input_device.
    // True TCC introspection (AVCaptureDevice.authorizationStatus) needs objc2
    // and is deferred until we genuinely need to differentiate
    // "no mic plugged in" vs "TCC denied".
    CheckResult::Skip("requires AVCaptureDevice probe (deferred)".into())
}

pub fn accessibility() -> CheckResult {
    if let Some(s) = skip_on_ci("CI=true") {
        return s;
    }
    #[cfg(target_os = "macos")]
    unsafe {
        if AXIsProcessTrusted() {
            CheckResult::Ok(String::new())
        } else {
            CheckResult::Fail {
                headline: "not granted".into(),
                fix: "System Settings → Privacy & Security → Accessibility → enable Voco".into(),
            }
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        CheckResult::Skip("macOS only".into())
    }
}

pub fn input_monitoring() -> CheckResult {
    if let Some(s) = skip_on_ci("CI=true") {
        return s;
    }
    #[cfg(target_os = "macos")]
    unsafe {
        let r = IOHIDCheckAccess(KIO_HID_REQUEST_TYPE_LISTEN_EVENT);
        if r == KIO_HID_ACCESS_TYPE_GRANTED {
            CheckResult::Ok(String::new())
        } else {
            CheckResult::Fail {
                headline: "not granted".into(),
                fix: "System Settings → Privacy & Security → Input Monitoring → enable Voco".into(),
            }
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        CheckResult::Skip("macOS only".into())
    }
}
