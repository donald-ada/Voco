use serde::{Deserialize, Serialize};
use std::io::Write;
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Arc, Mutex};
use thiserror::Error;
use tracing::warn;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum HudEvent {
    State {
        state: HudState,
        #[serde(skip_serializing_if = "Option::is_none")]
        message: Option<String>,
    },
    Amplitude {
        value: f32,
    },
}

impl HudEvent {
    pub fn state(state: HudState) -> Self {
        Self::State {
            state,
            message: None,
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self::State {
            state: HudState::Error,
            message: Some(message.into()),
        }
    }

    pub fn amplitude(value: f32) -> Self {
        Self::Amplitude {
            value: clamp_amplitude(value),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HudState {
    Hidden,
    Recording,
    Transcribing,
    Error,
}

#[derive(Debug, Error)]
pub enum HudError {
    #[error("serialize HUD event: {0}")]
    Serialize(#[from] serde_json::Error),
    #[error("spawn HUD helper: {0}")]
    Spawn(std::io::Error),
    #[error("write HUD event: {0}")]
    Write(std::io::Error),
    #[error("HUD helper missing")]
    MissingHelper,
}

pub trait HudSink: Send + Sync {
    fn send(&self, event: HudEvent) -> Result<(), HudError>;
}

pub type SharedHudSink = Arc<dyn HudSink>;

#[derive(Debug, Default)]
pub struct NoopHudSink;

impl HudSink for NoopHudSink {
    fn send(&self, _event: HudEvent) -> Result<(), HudError> {
        Ok(())
    }
}

pub fn noop_hud_sink() -> SharedHudSink {
    Arc::new(NoopHudSink)
}

#[cfg(test)]
pub struct TestWriterHudSink {
    output: Arc<Mutex<Vec<u8>>>,
}

#[cfg(test)]
impl TestWriterHudSink {
    pub fn new(output: Arc<Mutex<Vec<u8>>>) -> Self {
        Self { output }
    }
}

#[cfg(test)]
impl HudSink for TestWriterHudSink {
    fn send(&self, event: HudEvent) -> Result<(), HudError> {
        let line = event_to_json_line(&event)?;
        self.output
            .lock()
            .unwrap()
            .extend_from_slice(line.as_bytes());
        Ok(())
    }
}

pub struct HudProcess {
    inner: Mutex<HudProcessInner>,
}

struct HudProcessInner {
    child: Child,
    stdin: Option<ChildStdin>,
    enabled: bool,
    warned: bool,
}

impl HudProcess {
    pub fn spawn_default() -> Result<Self, HudError> {
        let Some(path) = locate_hud_binary() else {
            return Err(HudError::MissingHelper);
        };
        let mut child = Command::new(&path)
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(HudError::Spawn)?;
        let stdin = child.stdin.take();
        let process = Self {
            inner: Mutex::new(HudProcessInner {
                child,
                stdin,
                enabled: true,
                warned: false,
            }),
        };
        process.send(HudEvent::state(HudState::Hidden))?;
        Ok(process)
    }
}

impl HudSink for HudProcess {
    fn send(&self, event: HudEvent) -> Result<(), HudError> {
        let line = event_to_json_line(&event)?;
        let mut inner = self.inner.lock().unwrap();
        if !inner.enabled {
            return Ok(());
        }
        let Some(stdin) = inner.stdin.as_mut() else {
            inner.enabled = false;
            return Ok(());
        };
        if let Err(err) = stdin.write_all(line.as_bytes()).and_then(|_| stdin.flush()) {
            inner.enabled = false;
            if !inner.warned {
                inner.warned = true;
                warn!(error = %err, "HUD helper write failed; disabling HUD");
            }
            return Err(HudError::Write(err));
        }
        Ok(())
    }
}

impl Drop for HudProcess {
    fn drop(&mut self) {
        let mut inner = self.inner.lock().unwrap();
        let _ = inner.stdin.take();
        let deadline = std::time::Instant::now() + std::time::Duration::from_millis(300);
        while std::time::Instant::now() < deadline {
            if matches!(inner.child.try_wait(), Ok(Some(_))) {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
        let _ = inner.child.kill();
        let _ = inner.child.wait();
    }
}

pub fn default_hud_sink() -> SharedHudSink {
    match HudProcess::spawn_default() {
        Ok(process) => Arc::new(process),
        Err(err) => {
            warn!(error = %err, "HUD helper unavailable; continuing without HUD");
            noop_hud_sink()
        }
    }
}

fn locate_hud_binary() -> Option<PathBuf> {
    let current_exe = std::env::current_exe().ok();
    let exe_dir = current_exe.as_deref().and_then(std::path::Path::parent);
    let current_dir = std::env::current_dir().ok()?;
    let path = std::env::var_os("PATH");
    locate_hud_binary_from(exe_dir, &current_dir, path.as_deref())
}

fn locate_hud_binary_from(
    exe_dir: Option<&std::path::Path>,
    current_dir: &std::path::Path,
    path: Option<&std::ffi::OsStr>,
) -> Option<PathBuf> {
    if let Some(dir) = exe_dir {
        let candidate = dir.join("voco-hud");
        if candidate.exists() {
            return Some(candidate);
        }
    }
    let dev = current_dir.join("hud/.build/debug/voco-hud");
    if dev.exists() {
        return Some(dev);
    }
    let path = path?;
    for dir in std::env::split_paths(path) {
        let candidate = dir.join("voco-hud");
        if candidate.exists() {
            return Some(candidate);
        }
    }
    None
}

pub fn event_to_json_line(event: &HudEvent) -> Result<String, HudError> {
    let mut line = serde_json::to_string(event)?;
    line.push('\n');
    Ok(line)
}

pub fn clamp_amplitude(value: f32) -> f32 {
    value.clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn state_event_serializes_as_swift_jsonl_shape() {
        let line = event_to_json_line(&HudEvent::state(HudState::Recording)).unwrap();
        assert_eq!(line, "{\"type\":\"state\",\"state\":\"recording\"}\n");
    }

    #[test]
    fn error_event_includes_message() {
        let line = event_to_json_line(&HudEvent::error("microphone unavailable")).unwrap();
        assert_eq!(
            line,
            "{\"type\":\"state\",\"state\":\"error\",\"message\":\"microphone unavailable\"}\n"
        );
    }

    #[test]
    fn amplitude_event_is_clamped_before_serializing() {
        let line = event_to_json_line(&HudEvent::amplitude(1.4)).unwrap();
        assert_eq!(line, "{\"type\":\"amplitude\",\"value\":1.0}\n");
    }

    #[test]
    fn writer_sink_writes_newline_delimited_events() {
        let output = Arc::new(Mutex::new(Vec::<u8>::new()));
        let sink = TestWriterHudSink::new(output.clone());
        sink.send(HudEvent::state(HudState::Recording)).unwrap();
        sink.send(HudEvent::amplitude(0.25)).unwrap();

        let bytes = output.lock().unwrap().clone();
        assert_eq!(
            String::from_utf8(bytes).unwrap(),
            "{\"type\":\"state\",\"state\":\"recording\"}\n{\"type\":\"amplitude\",\"value\":0.25}\n"
        );
    }

    #[test]
    fn missing_helper_resolution_returns_none() {
        let temp = tempfile::tempdir().unwrap();
        assert_eq!(locate_hud_binary_from(None, temp.path(), None), None);
    }
}
