use thiserror::Error;

#[derive(Debug, Error)]
pub enum AudioError {
    #[error("no default input device")]
    NoInputDevice,

    #[error("input device name: {0}")]
    DeviceName(#[from] cpal::DeviceNameError),

    #[error("default input config: {0}")]
    DefaultInputConfig(#[from] cpal::DefaultStreamConfigError),

    #[error("unsupported input config: {0}")]
    UnsupportedInputConfig(String),

    #[error("build input stream: {0}")]
    BuildStream(#[from] cpal::BuildStreamError),

    #[error("play input stream: {0}")]
    PlayStream(#[from] cpal::PlayStreamError),
}
