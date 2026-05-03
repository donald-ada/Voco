use voco_audio::rms_i16;

#[test]
fn silence_has_zero_rms() {
    assert_eq!(rms_i16(&[0, 0, 0, 0]), 0.0);
}

#[test]
fn full_scale_square_normalizes_to_one() {
    let rms = rms_i16(&[i16::MAX, -i16::MAX, i16::MAX, -i16::MAX]);

    assert!((rms - 1.0).abs() < 0.0001, "rms={rms}");
}

#[test]
fn half_scale_sine_normalizes_to_half_over_root_two() {
    let amp = i16::MAX as f32 * 0.5;
    let samples = [
        0,
        amp as i16,
        0,
        -(amp as i16),
        0,
        amp as i16,
        0,
        -(amp as i16),
    ];

    let rms = rms_i16(&samples);

    let expected = 0.5_f32 / 2.0_f32.sqrt();
    assert!((rms - expected).abs() < 0.0001, "rms={rms}");
}
