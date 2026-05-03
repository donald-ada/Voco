use thiserror::Error;

#[derive(Debug, Error)]
pub enum AudioError {
    #[error("no default input device")]
    NoInputDevice,

    #[error("input device name: {0}")]
    DeviceName(#[from] cpal::DeviceNameError),

    #[error("input device supported configs: {0}")]
    SupportedConfigs(#[from] cpal::SupportedStreamConfigsError),

    #[error("unsupported input config: {0}")]
    UnsupportedInputConfig(String),

    #[error("build input stream: {0}")]
    BuildStream(#[from] cpal::BuildStreamError),

    #[error("play input stream: {0}")]
    PlayStream(#[from] cpal::PlayStreamError),
}
