use std::io::Write;
use std::process::{Command, Stdio};

use thiserror::Error;
use voco_config::{OutputConfig, OutputMode};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InjectionOutcome {
    Injected,
    ClipboardFallback { reason: String },
    ClipboardOnly,
}

#[derive(Debug, Clone, Error, PartialEq, Eq)]
pub enum InjectionError {
    #[error("event post: {0}")]
    EventPost(String),
    #[error("clipboard: {0}")]
    Clipboard(String),
    #[error("paste fallback: {0}")]
    Paste(String),
    #[error("unsupported platform")]
    Unsupported,
}

pub struct Injector;

impl Injector {
    pub fn insert(text: &str, output: &OutputConfig) -> Result<InjectionOutcome, InjectionError> {
        let mut sink = SystemSink;
        InjectionEngine::new(&mut sink).insert(text, output)
    }
}

struct InjectionEngine<'a, S> {
    sink: &'a mut S,
}

impl<'a, S> InjectionEngine<'a, S>
where
    S: TextSink,
{
    fn new(sink: &'a mut S) -> Self {
        Self { sink }
    }

    fn insert(
        &mut self,
        text: &str,
        output: &OutputConfig,
    ) -> Result<InjectionOutcome, InjectionError> {
        let normalized = normalize_text(text, output);
        match output.mode {
            OutputMode::ClipboardOnly => {
                self.sink.write_clipboard(&normalized)?;
                Ok(InjectionOutcome::ClipboardOnly)
            }
            OutputMode::InjectThenClipboard => match self.sink.insert_unicode(&normalized) {
                Ok(()) => Ok(InjectionOutcome::Injected),
                Err(err) => {
                    let reason = err.to_string();
                    self.sink.write_clipboard(&normalized)?;
                    if let Err(paste_err) = self.sink.paste_clipboard() {
                        return Ok(InjectionOutcome::ClipboardFallback {
                            reason: format!("{reason}; paste fallback failed: {paste_err}"),
                        });
                    }
                    Ok(InjectionOutcome::ClipboardFallback { reason })
                }
            },
        }
    }
}

trait TextSink {
    fn insert_unicode(&mut self, text: &str) -> Result<(), InjectionError>;
    fn write_clipboard(&mut self, text: &str) -> Result<(), InjectionError>;
    fn paste_clipboard(&mut self) -> Result<(), InjectionError>;
}

struct SystemSink;

impl TextSink for SystemSink {
    fn insert_unicode(&mut self, text: &str) -> Result<(), InjectionError> {
        platform::post_unicode(text)
    }

    fn write_clipboard(&mut self, text: &str) -> Result<(), InjectionError> {
        let mut child = Command::new("pbcopy")
            .stdin(Stdio::piped())
            .spawn()
            .map_err(|err| InjectionError::Clipboard(err.to_string()))?;
        let stdin = child
            .stdin
            .as_mut()
            .ok_or_else(|| InjectionError::Clipboard("pbcopy stdin unavailable".into()))?;
        stdin
            .write_all(text.as_bytes())
            .map_err(|err| InjectionError::Clipboard(err.to_string()))?;
        let status = child
            .wait()
            .map_err(|err| InjectionError::Clipboard(err.to_string()))?;
        if status.success() {
            Ok(())
        } else {
            Err(InjectionError::Clipboard(format!(
                "pbcopy exited with {status}"
            )))
        }
    }

    fn paste_clipboard(&mut self) -> Result<(), InjectionError> {
        platform::post_cmd_v()
    }
}

fn normalize_text(text: &str, output: &OutputConfig) -> String {
    let mut out = text.trim().to_string();
    if output.trim_trailing_punct {
        out = out
            .trim_end_matches(|c: char| {
                matches!(
                    c,
                    '.' | ',' | ';' | ':' | '!' | '?' | '。' | '，' | '；' | '：' | '！' | '？'
                )
            })
            .trim_end()
            .to_string();
    }
    if output.auto_capitalize {
        let mut chars = out.chars();
        if let Some(first) = chars.next() {
            out = first.to_uppercase().collect::<String>() + chars.as_str();
        }
    }
    out
}

#[cfg(target_os = "macos")]
mod platform {
    use super::InjectionError;
    use std::ffi::c_void;

    type CGEventRef = *mut c_void;
    type CGEventSourceRef = *mut c_void;

    const K_CG_HID_EVENT_TAP: u32 = 0;
    const K_CG_EVENT_FLAG_MASK_COMMAND: u64 = 1 << 20;
    const KEYCODE_V: u16 = 9;

    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        fn CGEventCreateKeyboardEvent(
            source: CGEventSourceRef,
            virtual_key: u16,
            key_down: bool,
        ) -> CGEventRef;
        fn CGEventKeyboardSetUnicodeString(event: CGEventRef, length: usize, string: *const u16);
        fn CGEventSetFlags(event: CGEventRef, flags: u64);
        fn CGEventPost(tap: u32, event: CGEventRef);
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        fn CFRelease(cf: *const c_void);
    }

    pub fn post_unicode(text: &str) -> Result<(), InjectionError> {
        let utf16: Vec<u16> = text.encode_utf16().collect();
        unsafe {
            let down = CGEventCreateKeyboardEvent(std::ptr::null_mut(), 0, true);
            if down.is_null() {
                return Err(InjectionError::EventPost(
                    "CGEventCreateKeyboardEvent returned null".into(),
                ));
            }
            CGEventKeyboardSetUnicodeString(down, utf16.len(), utf16.as_ptr());
            CGEventPost(K_CG_HID_EVENT_TAP, down);
            CFRelease(down as *const c_void);
        }
        Ok(())
    }

    pub fn post_cmd_v() -> Result<(), InjectionError> {
        unsafe {
            let down = CGEventCreateKeyboardEvent(std::ptr::null_mut(), KEYCODE_V, true);
            let up = CGEventCreateKeyboardEvent(std::ptr::null_mut(), KEYCODE_V, false);
            if down.is_null() || up.is_null() {
                if !down.is_null() {
                    CFRelease(down as *const c_void);
                }
                if !up.is_null() {
                    CFRelease(up as *const c_void);
                }
                return Err(InjectionError::Paste(
                    "CGEventCreateKeyboardEvent returned null".into(),
                ));
            }
            CGEventSetFlags(down, K_CG_EVENT_FLAG_MASK_COMMAND);
            CGEventSetFlags(up, K_CG_EVENT_FLAG_MASK_COMMAND);
            CGEventPost(K_CG_HID_EVENT_TAP, down);
            CGEventPost(K_CG_HID_EVENT_TAP, up);
            CFRelease(down as *const c_void);
            CFRelease(up as *const c_void);
        }
        Ok(())
    }
}

#[cfg(not(target_os = "macos"))]
mod platform {
    use super::InjectionError;

    pub fn post_unicode(_text: &str) -> Result<(), InjectionError> {
        Err(InjectionError::Unsupported)
    }

    pub fn post_cmd_v() -> Result<(), InjectionError> {
        Err(InjectionError::Unsupported)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use voco_config::{OutputConfig, OutputMode};

    fn output(mode: OutputMode) -> OutputConfig {
        OutputConfig {
            mode,
            trim_trailing_punct: false,
            auto_capitalize: false,
        }
    }

    #[test]
    fn normalizes_text_before_delivery() {
        let mut cfg = output(OutputMode::ClipboardOnly);
        cfg.trim_trailing_punct = true;
        cfg.auto_capitalize = true;

        assert_eq!(normalize_text(" hello。 ", &cfg), "Hello");
    }

    #[test]
    fn clipboard_only_writes_clipboard_without_injecting() {
        let mut sink = MockSink::default();
        let outcome = InjectionEngine::new(&mut sink)
            .insert("hello", &output(OutputMode::ClipboardOnly))
            .unwrap();

        assert_eq!(outcome, InjectionOutcome::ClipboardOnly);
        assert_eq!(sink.clipboard, Some("hello".into()));
        assert_eq!(sink.unicode_attempts, 0);
        assert_eq!(sink.paste_attempts, 0);
    }

    #[test]
    fn inject_then_clipboard_uses_unicode_when_available() {
        let mut sink = MockSink::default();
        let outcome = InjectionEngine::new(&mut sink)
            .insert("hello", &output(OutputMode::InjectThenClipboard))
            .unwrap();

        assert_eq!(outcome, InjectionOutcome::Injected);
        assert_eq!(sink.unicode_attempts, 1);
        assert_eq!(sink.clipboard, None);
    }

    #[test]
    fn inject_failure_falls_back_to_clipboard_paste() {
        let mut sink = MockSink {
            unicode_result: Err(InjectionError::EventPost("secure input".into())),
            ..Default::default()
        };
        let outcome = InjectionEngine::new(&mut sink)
            .insert("hello", &output(OutputMode::InjectThenClipboard))
            .unwrap();

        assert_eq!(
            outcome,
            InjectionOutcome::ClipboardFallback {
                reason: "event post: secure input".into()
            }
        );
        assert_eq!(sink.clipboard, Some("hello".into()));
        assert_eq!(sink.paste_attempts, 1);
    }

    #[derive(Debug, Clone)]
    struct MockSink {
        clipboard: Option<String>,
        unicode_attempts: usize,
        paste_attempts: usize,
        unicode_result: Result<(), InjectionError>,
        clipboard_result: Result<(), InjectionError>,
        paste_result: Result<(), InjectionError>,
    }

    impl Default for MockSink {
        fn default() -> Self {
            Self {
                clipboard: None,
                unicode_attempts: 0,
                paste_attempts: 0,
                unicode_result: Ok(()),
                clipboard_result: Ok(()),
                paste_result: Ok(()),
            }
        }
    }

    impl TextSink for MockSink {
        fn insert_unicode(&mut self, _text: &str) -> Result<(), InjectionError> {
            self.unicode_attempts += 1;
            self.unicode_result.clone()
        }

        fn write_clipboard(&mut self, text: &str) -> Result<(), InjectionError> {
            self.clipboard = Some(text.to_string());
            self.clipboard_result.clone()
        }

        fn paste_clipboard(&mut self) -> Result<(), InjectionError> {
            self.paste_attempts += 1;
            self.paste_result.clone()
        }
    }
}
