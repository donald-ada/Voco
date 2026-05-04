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
        let (pcm_tx, pcm_rx) = mpsc::channel(64);
        let (amplitude_tx, amplitude_rx) = watch::channel(0.0_f32);
        let dropped_frames = Arc::new(AtomicU64::new(0));
        info!("resolving default input device");
        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .ok_or(AudioError::NoInputDevice)?;
        let device_name = device.name()?;
        let config = cpal::StreamConfig {
            channels: 1,
            sample_rate: cpal::SampleRate(TARGET_SAMPLE_RATE),
            buffer_size: cpal::BufferSize::Default,
        };

        info!(
            device = %device_name,
            channels = config.channels,
            sample_rate = config.sample_rate.0,
            "opening default input stream"
        );

        let stream = match build_i16_stream(
            &device,
            &config,
            pcm_tx.clone(),
            amplitude_tx.clone(),
            Arc::clone(&dropped_frames),
        ) {
            Ok(stream) => stream,
            Err(BuildStreamError::StreamConfigNotSupported) => {
                warn!("16kHz mono i16 input unsupported; using default f32 input fallback");
                build_fallback_f32_stream(&device, pcm_tx, amplitude_tx, dropped_frames)?
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
    let channels = config.channels.max(1) as usize;
    let mut resampler = F32ToI16Resampler::new(input_sample_rate, TARGET_SAMPLE_RATE);

    device.build_input_stream::<f32, _, _>(
        config,
        move |data: &[f32], _| {
            let mono;
            let samples = if channels == 1 {
                data
            } else {
                mono = downmix_interleaved_f32(data, channels);
                &mono
            };
            let pcm = resampler.push(samples);
            if pcm.is_empty() {
                return;
            }
            push_pcm(pcm, &pcm_tx, &amplitude_tx, &dropped_frames);
        },
        log_stream_error,
        None,
    )
}

fn build_fallback_f32_stream(
    device: &cpal::Device,
    pcm_tx: mpsc::Sender<Vec<i16>>,
    amplitude_tx: watch::Sender<f32>,
    dropped_frames: Arc<AtomicU64>,
) -> Result<cpal::Stream, AudioError> {
    info!("querying default input config");
    let default_config = device.default_input_config()?;
    if default_config.sample_format() != cpal::SampleFormat::F32 {
        return Err(AudioError::UnsupportedInputConfig(format!(
            "default input sample format must be f32 for fallback, got {:?}",
            default_config.sample_format()
        )));
    }

    let config = cpal::StreamConfig {
        channels: default_config.channels(),
        sample_rate: default_config.sample_rate(),
        buffer_size: cpal::BufferSize::Default,
    };
    warn!(
        channels = config.channels,
        sample_rate = config.sample_rate.0,
        "using default f32 input fallback with resampling"
    );

    build_f32_stream(device, &config, pcm_tx, amplitude_tx, dropped_frames).map_err(Into::into)
}

struct F32ToI16Resampler {
    step: f64,
    next_source_position: f64,
    pending: Vec<f32>,
}

impl F32ToI16Resampler {
    fn new(source_rate: u32, target_rate: u32) -> Self {
        debug_assert!(source_rate > 0);
        debug_assert!(target_rate > 0);
        Self {
            step: source_rate as f64 / target_rate as f64,
            next_source_position: 0.0,
            pending: Vec::new(),
        }
    }

    fn push(&mut self, samples: &[f32]) -> Vec<i16> {
        self.pending
            .extend(samples.iter().map(|sample| sample.clamp(-1.0, 1.0)));

        let mut pcm = Vec::with_capacity((samples.len() as f64 / self.step).ceil() as usize + 1);
        loop {
            let idx = self.next_source_position.floor() as usize;
            if idx >= self.pending.len() {
                break;
            }

            let frac = self.next_source_position - idx as f64;
            let sample = if frac <= f64::EPSILON {
                self.pending[idx]
            } else if let Some(next) = self.pending.get(idx + 1) {
                self.pending[idx] + ((*next - self.pending[idx]) * frac as f32)
            } else {
                break;
            };

            pcm.push(f32_to_i16(sample));
            self.next_source_position += self.step;
        }

        let drain_len = (self.next_source_position.floor() as usize).min(self.pending.len());
        if drain_len > 0 {
            self.pending.drain(..drain_len);
            self.next_source_position -= drain_len as f64;
        }

        pcm
    }
}

fn f32_to_i16(sample: f32) -> i16 {
    (sample.clamp(-1.0, 1.0) * i16::MAX as f32) as i16
}

fn downmix_interleaved_f32(samples: &[f32], channels: usize) -> Vec<f32> {
    debug_assert!(channels > 0);
    samples
        .chunks_exact(channels)
        .map(|frame| frame.iter().sum::<f32>() / channels as f32)
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
    fn downmix_interleaved_f32_averages_channels() {
        assert_eq!(
            downmix_interleaved_f32(&[1.0, -1.0, 0.25, 0.75], 2),
            vec![0.0, 0.5]
        );
    }

    #[test]
    fn f32_resampler_converts_24khz_to_16khz() {
        let mut resampler = F32ToI16Resampler::new(24_000, TARGET_SAMPLE_RATE);
        let pcm = resampler.push(&vec![0.5; 240]);

        assert_eq!(pcm.len(), 160);
        assert!(pcm.iter().all(|sample| *sample == 16_383));
    }
}
