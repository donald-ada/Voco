use serde::{Deserialize, Serialize};
use std::io::Write;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{sync_channel, SyncSender, TrySendError};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread::JoinHandle;
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
    Transcript {
        text: String,
        stable_prefix_len: usize,
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

    pub fn transcript(text: impl Into<String>, stable_prefix_len: usize) -> Self {
        Self::Transcript {
            text: text.into(),
            stable_prefix_len,
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
    helper_path: PathBuf,
    child: Option<Child>,
    tx: Option<SyncSender<String>>,
    writer: Option<JoinHandle<()>>,
    last_state: Option<HudEvent>,
    enabled: bool,
    warned: bool,
}

impl HudProcess {
    pub fn spawn_default() -> Result<Self, HudError> {
        let Some(path) = locate_hud_binary() else {
            return Err(HudError::MissingHelper);
        };
        Self::spawn_with_path(path)
    }

    #[cfg(test)]
    fn spawn_with_path_for_test(path: PathBuf) -> Result<Self, HudError> {
        Self::spawn_with_path(path)
    }

    fn spawn_with_path(path: PathBuf) -> Result<Self, HudError> {
        let (child, tx, writer) = spawn_helper(&path)?;
        let process = Self {
            inner: Mutex::new(HudProcessInner {
                helper_path: path,
                child: Some(child),
                tx: Some(tx),
                writer: Some(writer),
                last_state: None,
                enabled: true,
                warned: false,
            }),
        };
        process.send(HudEvent::state(HudState::Hidden))?;
        Ok(process)
    }
}

fn spawn_helper(path: &PathBuf) -> Result<(Child, SyncSender<String>, JoinHandle<()>), HudError> {
    let mut child = Command::new(path)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(HudError::Spawn)?;
    let Some(stdin) = child.stdin.take() else {
        let _ = child.kill();
        let _ = child.wait();
        return Err(HudError::Write(std::io::ErrorKind::BrokenPipe.into()));
    };
    let (tx, rx) = sync_channel::<String>(64);
    let writer = std::thread::spawn(move || {
        let mut stdin = stdin;
        for line in rx {
            if let Err(err) = stdin.write_all(line.as_bytes()).and_then(|_| stdin.flush()) {
                warn!(error = %err, "HUD helper pipe broke; waiting for respawn");
                return;
            }
        }
    });
    Ok((child, tx, writer))
}

impl HudSink for HudProcess {
    fn send(&self, event: HudEvent) -> Result<(), HudError> {
        let line = event_to_json_line(&event)?;
        let mut inner = self.lock_inner();
        if !inner.enabled {
            return Ok(());
        }
        if matches!(event, HudEvent::State { .. }) {
            inner.last_state = Some(event.clone());
        }
        if self.helper_exited_locked(&mut inner) {
            return self.respawn_and_retry(&mut inner, event, line);
        }
        let Some(tx) = inner.tx.as_ref().cloned() else {
            return self.respawn_and_retry(&mut inner, event, line);
        };

        match tx.try_send(line.clone()) {
            Ok(()) => Ok(()),
            Err(TrySendError::Full(_)) => {
                if !inner.warned {
                    inner.warned = true;
                    warn!("HUD helper queue full; dropping HUD event without disabling HUD");
                }
                Ok(())
            }
            Err(TrySendError::Disconnected(_)) => self.respawn_and_retry(&mut inner, event, line),
        }
    }
}

impl Drop for HudProcess {
    fn drop(&mut self) {
        let (mut child, writer) = {
            let mut inner = match self.inner.lock() {
                Ok(inner) => inner,
                Err(poisoned) => {
                    warn!("HUD process mutex poisoned during drop; continuing cleanup");
                    poisoned.into_inner()
                }
            };
            let _ = inner.tx.take();
            (inner.child.take(), inner.writer.take())
        };

        if let Some(child) = child.as_mut() {
            let deadline = std::time::Instant::now() + std::time::Duration::from_millis(300);
            while std::time::Instant::now() < deadline {
                if matches!(child.try_wait(), Ok(Some(_))) {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(25));
            }
            if matches!(child.try_wait(), Ok(None)) {
                let _ = child.kill();
            }
            let _ = child.wait();
        }

        if let Some(writer) = writer {
            let _ = writer.join();
        }
    }
}

impl HudProcess {
    fn lock_inner(&self) -> MutexGuard<'_, HudProcessInner> {
        match self.inner.lock() {
            Ok(inner) => inner,
            Err(poisoned) => {
                warn!("HUD process mutex poisoned; continuing with inner state");
                poisoned.into_inner()
            }
        }
    }

    fn respawn_and_retry(
        &self,
        inner: &mut HudProcessInner,
        event: HudEvent,
        line: String,
    ) -> Result<(), HudError> {
        self.stop_locked_helper(inner);
        let (child, tx, writer) = spawn_helper(&inner.helper_path)?;
        inner.child = Some(child);
        inner.tx = Some(tx);
        inner.writer = Some(writer);
        inner.warned = false;

        if let Some(state) = inner.last_state.clone() {
            let state_line = event_to_json_line(&state)?;
            self.send_line_locked(inner, state_line)?;
        }
        if inner.last_state.as_ref() != Some(&event) {
            self.send_line_locked(inner, line)?;
        }
        Ok(())
    }

    fn send_line_locked(&self, inner: &mut HudProcessInner, line: String) -> Result<(), HudError> {
        let Some(tx) = inner.tx.as_ref() else {
            return Err(HudError::Write(std::io::ErrorKind::BrokenPipe.into()));
        };
        tx.try_send(line).map_err(|err| match err {
            TrySendError::Full(_) => HudError::Write(std::io::ErrorKind::WouldBlock.into()),
            TrySendError::Disconnected(_) => HudError::Write(std::io::ErrorKind::BrokenPipe.into()),
        })
    }

    fn helper_exited_locked(&self, inner: &mut HudProcessInner) -> bool {
        inner
            .child
            .as_mut()
            .and_then(|child| child.try_wait().ok())
            .flatten()
            .is_some()
    }

    fn stop_locked_helper(&self, inner: &mut HudProcessInner) {
        let mut child = inner.child.take();
        let writer = inner.writer.take();
        let _ = inner.tx.take();

        if let Some(child) = child.as_mut() {
            let deadline = std::time::Instant::now() + std::time::Duration::from_millis(300);
            while std::time::Instant::now() < deadline {
                if matches!(child.try_wait(), Ok(Some(_))) {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(25));
            }
            if matches!(child.try_wait(), Ok(None)) {
                let _ = child.kill();
            }
            let _ = child.wait();
        }

        if let Some(writer) = writer {
            let _ = writer.join();
        }
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
    let current_dir = std::env::current_dir().ok();
    let path = std::env::var_os("PATH");
    locate_hud_binary_from(exe_dir, current_dir.as_deref(), path.as_deref())
}

fn locate_hud_binary_from(
    exe_dir: Option<&std::path::Path>,
    current_dir: Option<&std::path::Path>,
    path: Option<&std::ffi::OsStr>,
) -> Option<PathBuf> {
    if let Some(dir) = exe_dir {
        let candidate = dir.join("voco-hud");
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    if let Some(current_dir) = current_dir {
        let dev = current_dir.join("hud/.build/debug/voco-hud");
        if dev.is_file() {
            return Some(dev);
        }
    }
    let path = path?;
    for dir in std::env::split_paths(path) {
        let candidate = dir.join("voco-hud");
        if candidate.is_file() {
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
    if value.is_finite() {
        value.clamp(0.0, 1.0)
    } else {
        0.0
    }
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
    fn transcript_event_serializes_as_swift_jsonl_shape() {
        let line = event_to_json_line(&HudEvent::transcript("你好世界", 6)).unwrap();
        assert_eq!(
            line,
            "{\"type\":\"transcript\",\"text\":\"你好世界\",\"stable_prefix_len\":6}\n"
        );
    }

    #[test]
    fn transcript_event_preserves_empty_text() {
        let line = event_to_json_line(&HudEvent::transcript("", 0)).unwrap();
        assert_eq!(
            line,
            "{\"type\":\"transcript\",\"text\":\"\",\"stable_prefix_len\":0}\n"
        );
    }

    #[test]
    fn amplitude_clamp_rejects_non_finite_values() {
        assert_eq!(clamp_amplitude(f32::NAN), 0.0);
        assert_eq!(clamp_amplitude(f32::INFINITY), 0.0);
        assert_eq!(clamp_amplitude(f32::NEG_INFINITY), 0.0);
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
        assert_eq!(locate_hud_binary_from(None, Some(temp.path()), None), None);
    }

    #[test]
    fn helper_resolution_ignores_directory_candidates() {
        let temp = tempfile::tempdir().unwrap();
        std::fs::create_dir(temp.path().join("voco-hud")).unwrap();

        assert_eq!(
            locate_hud_binary_from(Some(temp.path()), Some(temp.path()), None),
            None
        );
    }

    #[test]
    fn helper_resolution_can_use_path_without_current_dir() {
        let temp = tempfile::tempdir().unwrap();
        let helper = temp.path().join("voco-hud");
        std::fs::write(&helper, b"#!/bin/sh\n").unwrap();
        let path = std::env::join_paths([temp.path()]).unwrap();

        assert_eq!(
            locate_hud_binary_from(None, None, Some(&path)),
            Some(helper)
        );
    }

    #[cfg(unix)]
    #[test]
    fn hud_process_respawns_after_helper_pipe_breaks() {
        use std::os::unix::fs::PermissionsExt;

        let temp = tempfile::tempdir().unwrap();
        let log = temp.path().join("hud-lines.log");
        let helper = temp.path().join("voco-hud");
        std::fs::write(
            &helper,
            format!(
                "#!/bin/sh\nprintf 'start\\n' >> '{}'\nif IFS= read -r line; then printf '%s\\n' \"$line\" >> '{}'; fi\nexit 0\n",
                log.display(),
                log.display()
            ),
        )
        .unwrap();
        let mut permissions = std::fs::metadata(&helper).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&helper, permissions).unwrap();

        let process = HudProcess::spawn_with_path_for_test(helper).unwrap();
        wait_until_log_contains(&log, "\"hidden\"");

        process.send(HudEvent::state(HudState::Recording)).unwrap();
        wait_until_log_contains(&log, "\"recording\"");

        let contents = std::fs::read_to_string(log).unwrap();
        assert!(contents.matches("start").count() >= 2, "{contents}");
    }

    #[cfg(unix)]
    fn wait_until_log_contains(path: &std::path::Path, needle: &str) {
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
        while std::time::Instant::now() < deadline {
            if std::fs::read_to_string(path)
                .map(|contents| contents.contains(needle))
                .unwrap_or(false)
            {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
        panic!("timed out waiting for {needle} in {}", path.display());
    }
}
