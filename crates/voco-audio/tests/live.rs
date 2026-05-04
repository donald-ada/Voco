use std::time::Duration;

use cpal::traits::{DeviceTrait, HostTrait};
use voco_audio::AudioCapture;

#[test]
#[ignore = "opens the system microphone; run manually on a dev Mac with mic permission"]
fn default_input_stream_yields_pcm_and_amplitude() {
    print_supported_input_configs();

    let mut session = AudioCapture::start().expect("default input stream starts");

    let deadline = std::time::Instant::now() + Duration::from_secs(3);
    let pcm = loop {
        if let Ok(pcm) = session.pcm_rx.try_recv() {
            break pcm;
        }
        if std::time::Instant::now() >= deadline {
            panic!("pcm frame available within 3s");
        }
        std::thread::sleep(Duration::from_millis(50));
    };
    assert!(!pcm.is_empty());

    let amp = *session.amplitude_rx.borrow_and_update();
    assert!((0.0..=1.0).contains(&amp), "amp={amp}");

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
