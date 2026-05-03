//! Microphone capture for Voco recording sessions.

mod error;

use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::BuildStreamError;
use tokio::sync::{mpsc, watch};
use tracing::{info, warn};

pub use error::AudioError;

const TARGET_SAMPLE_RATE: u32 = 16_000;

pub struct AudioCapture;

impl AudioCapture {
    pub fn start() -> Result<Session, AudioError> {
        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .ok_or(AudioError::NoInputDevice)?;
        let device_name = device.name()?;
        let supported = device.supported_input_configs()?.count();
        let config = cpal::StreamConfig {
            channels: 1,
            sample_rate: cpal::SampleRate(TARGET_SAMPLE_RATE),
            buffer_size: cpal::BufferSize::Default,
        };

        info!(
            device = %device_name,
            supported_input_configs = supported,
            channels = config.channels,
            sample_rate = config.sample_rate.0,
            "opening default input stream"
        );

        let (pcm_tx, pcm_rx) = mpsc::channel(64);
        let (amplitude_tx, amplitude_rx) = watch::channel(0.0_f32);
        let dropped_frames = Arc::new(AtomicU64::new(0));
        let stream = match build_i16_stream(
            &device,
            &config,
            pcm_tx.clone(),
            amplitude_tx.clone(),
            Arc::clone(&dropped_frames),
        ) {
            Ok(stream) => stream,
            Err(BuildStreamError::StreamConfigNotSupported) => {
                let fallback_config = fallback_f32_config(&device)?;
                warn!(
                    sample_rate = fallback_config.sample_rate.0,
                    "16kHz mono i16 input unsupported; falling back to f32 input with downsampling"
                );
                build_f32_stream(
                    &device,
                    &fallback_config,
                    pcm_tx,
                    amplitude_tx,
                    dropped_frames,
                )?
            }
            Err(err) => return Err(err.into()),
        };
        stream.play()?;

        Ok(Session {
            pcm_rx,
            amplitude_rx,
            _handle: StopHandle { _stream: stream },
        })
    }
}

pub struct Session {
    pub pcm_rx: mpsc::Receiver<Vec<i16>>,
    pub amplitude_rx: watch::Receiver<f32>,
    _handle: StopHandle,
}

impl Session {
    pub fn stop(self) {
        drop(self);
    }
}

struct StopHandle {
    _stream: cpal::Stream,
}

pub fn rms_i16(buf: &[i16]) -> f32 {
    if buf.is_empty() {
        return 0.0;
    }
    let sum_sq: f64 = buf.iter().map(|s| (*s as f64).powi(2)).sum();
    let mean = sum_sq / buf.len() as f64;
    (mean.sqrt() / i16::MAX as f64) as f32
}

fn build_i16_stream(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    pcm_tx: mpsc::Sender<Vec<i16>>,
    amplitude_tx: watch::Sender<f32>,
    dropped_frames: Arc<AtomicU64>,
) -> Result<cpal::Stream, BuildStreamError> {
    device.build_input_stream::<i16, _, _>(
        config,
        move |data: &[i16], _| push_pcm(data.to_vec(), &pcm_tx, &amplitude_tx, &dropped_frames),
        log_stream_error,
        None,
    )
}

fn build_f32_stream(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    pcm_tx: mpsc::Sender<Vec<i16>>,
    amplitude_tx: watch::Sender<f32>,
    dropped_frames: Arc<AtomicU64>,
) -> Result<cpal::Stream, BuildStreamError> {
    let input_sample_rate = config.sample_rate.0;
    let ratio = input_sample_rate / TARGET_SAMPLE_RATE;
    let mut pending = Vec::new();

    device.build_input_stream::<f32, _, _>(
        config,
        move |data: &[f32], _| {
            pending.extend(
                data.iter()
                    .map(|sample| (sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16),
            );
            let complete_len = pending.len() / ratio as usize * ratio as usize;
            if complete_len == 0 {
                return;
            }
            let pcm = downsample_integer_ratio_i16(&pending[..complete_len], ratio as usize);
            pending.drain(..complete_len);
            push_pcm(pcm, &pcm_tx, &amplitude_tx, &dropped_frames);
        },
        log_stream_error,
        None,
    )
}

fn fallback_f32_config(device: &cpal::Device) -> Result<cpal::StreamConfig, AudioError> {
    let preferred_rates = [
        TARGET_SAMPLE_RATE,
        TARGET_SAMPLE_RATE * 2,
        TARGET_SAMPLE_RATE * 3,
        TARGET_SAMPLE_RATE * 6,
    ];
    let configs: Vec<_> = device.supported_input_configs()?.collect();

    for rate in preferred_rates {
        for cfg in &configs {
            if cfg.channels() != 1 || cfg.sample_format() != cpal::SampleFormat::F32 {
                continue;
            }
            if cfg.min_sample_rate().0 <= rate && rate <= cfg.max_sample_rate().0 {
                return Ok(cpal::StreamConfig {
                    channels: 1,
                    sample_rate: cpal::SampleRate(rate),
                    buffer_size: cpal::BufferSize::Default,
                });
            }
        }
    }

    Err(AudioError::UnsupportedInputConfig(
        "need mono f32 input at 16kHz or an integer multiple of 16kHz".into(),
    ))
}

fn downsample_integer_ratio_i16(samples: &[i16], ratio: usize) -> Vec<i16> {
    debug_assert!(ratio > 0);
    samples
        .chunks_exact(ratio)
        .map(|chunk| {
            let sum: i32 = chunk.iter().map(|sample| *sample as i32).sum();
            (sum / ratio as i32) as i16
        })
        .collect()
}

fn push_pcm(
    pcm: Vec<i16>,
    pcm_tx: &mpsc::Sender<Vec<i16>>,
    amplitude_tx: &watch::Sender<f32>,
    dropped_frames: &AtomicU64,
) {
    let amp = rms_i16(&pcm);
    let _ = amplitude_tx.send(amp);

    match pcm_tx.try_send(pcm) {
        Ok(()) => {}
        Err(mpsc::error::TrySendError::Full(_)) => {
            let dropped = dropped_frames.fetch_add(1, Ordering::Relaxed) + 1;
            if dropped == 1 || dropped % 128 == 0 {
                warn!(
                    dropped_frames = dropped,
                    "audio PCM channel full; dropping newest frame"
                );
            }
        }
        Err(mpsc::error::TrySendError::Closed(_)) => {
            warn!("audio PCM receiver closed; dropping frame");
        }
    }
}

fn log_stream_error(err: cpal::StreamError) {
    warn!(error = %err, "input stream error");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn downsample_integer_ratio_averages_full_chunks() {
        let input = [3, 6, 9, 12, 15, 18];

        assert_eq!(downsample_integer_ratio_i16(&input, 3), vec![6, 15]);
    }

    #[test]
    fn downsample_integer_ratio_drops_partial_tail() {
        let input = [3, 6, 9, 99];

        assert_eq!(downsample_integer_ratio_i16(&input, 3), vec![6]);
    }
}
