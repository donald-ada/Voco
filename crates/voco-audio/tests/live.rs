use std::time::Duration;

use cpal::traits::{DeviceTrait, HostTrait};
use voco_audio::AudioCapture;

#[test]
#[ignore = "opens the system microphone; run manually on a dev Mac with mic permission"]
fn default_input_stream_yields_pcm_and_amplitude() {
    print_supported_input_configs();

    let mut session = AudioCapture::start().expect("default input stream starts");

    std::thread::sleep(Duration::from_millis(100));

    let pcm = session.pcm_rx.try_recv().expect("pcm frame available");
    assert!(!pcm.is_empty());

    let amp = *session.amplitude_rx.borrow_and_update();
    assert!(amp > 0.0 && amp <= 1.0, "amp={amp}");

    session.stop();
}

fn print_supported_input_configs() {
    let host = cpal::default_host();
    let Some(device) = host.default_input_device() else {
        eprintln!("no default input device");
        return;
    };
    eprintln!(
        "default input: {}",
        device.name().unwrap_or_else(|_| "<unknown>".into())
    );
    match device.supported_input_configs() {
        Ok(configs) => {
            for cfg in configs {
                eprintln!(
                    "  channels={} min_rate={} max_rate={} sample_format={:?}",
                    cfg.channels(),
                    cfg.min_sample_rate().0,
                    cfg.max_sample_rate().0,
                    cfg.sample_format()
                );
            }
        }
        Err(err) => eprintln!("supported_input_configs failed: {err}"),
    }
}
