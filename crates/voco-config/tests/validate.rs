// crates/voco-config/tests/validate.rs
use std::path::PathBuf;
use voco_config::schema::*;
use voco_config::validate::ValidationKind;

fn cfg_with_backend(backend: BackendChoice) -> Config {
    Config {
        backend,
        ..Config::default()
    }
}

#[test]
fn default_is_invalid_in_strict_mode() {
    // Default has backend=Doubao but no creds. Strict mode rejects.
    let cfg = Config::default();
    let errors = cfg.validate();
    assert_eq!(errors.len(), 1);
    assert!(matches!(errors[0].kind, ValidationKind::DoubaoCredsMissing));
}

#[test]
fn doubao_with_creds_is_valid() {
    let mut cfg = cfg_with_backend(BackendChoice::Doubao);
    cfg.doubao = Some(DoubaoCreds {
        app_id: "x".into(),
        access_token: "y".into(),
        endpoint: "wss://example.invalid/asr".into(),
        model_id: "bigmodel-streaming".into(),
        ..Default::default()
    });
    assert!(cfg.validate().is_empty());
}

#[test]
fn sherpa_without_paths_fails() {
    let cfg = cfg_with_backend(BackendChoice::Sherpa);
    let errors = cfg.validate();
    assert!(errors
        .iter()
        .any(|e| matches!(e.kind, ValidationKind::SherpaPathsMissing)));
}

#[test]
fn sherpa_with_nonexistent_dir_fails() {
    let mut cfg = cfg_with_backend(BackendChoice::Sherpa);
    cfg.sherpa = Some(SherpaPaths {
        model_dir: PathBuf::from("/definitely/does/not/exist/voco-test"),
        num_threads: 2,
        provider: "cpu".into(),
    });
    let errors = cfg.validate();
    assert!(errors
        .iter()
        .any(|e| matches!(e.kind, ValidationKind::SherpaModelDirMissing)));
}

#[test]
fn doubao_with_empty_token_fails() {
    let mut cfg = cfg_with_backend(BackendChoice::Doubao);
    cfg.doubao = Some(DoubaoCreds {
        app_id: "x".into(),
        access_token: "".into(),
        endpoint: "wss://example.invalid/asr".into(),
        model_id: "bigmodel-streaming".into(),
        ..Default::default()
    });
    let errors = cfg.validate();
    assert!(errors
        .iter()
        .any(|e| matches!(e.kind, ValidationKind::DoubaoCredsEmpty(_))));
}

#[test]
fn doubao_with_empty_model_id_fails() {
    let mut cfg = cfg_with_backend(BackendChoice::Doubao);
    cfg.doubao = Some(DoubaoCreds {
        app_id: "x".into(),
        access_token: "y".into(),
        endpoint: "wss://example.invalid/asr".into(),
        model_id: "".into(),
        ..Default::default()
    });
    let errors = cfg.validate();
    assert!(errors
        .iter()
        .any(|e| matches!(e.kind, ValidationKind::DoubaoCredsEmpty("model_id"))));
}

#[test]
fn recording_max_duration_zero_fails() {
    let cfg = Config {
        doubao: Some(DoubaoCreds {
            app_id: "x".into(),
            access_token: "y".into(),
            endpoint: "wss://example.invalid/asr".into(),
            model_id: "bigmodel-streaming".into(),
            ..Default::default()
        }),
        recording_max_duration_secs: 0,
        ..Config::default()
    };
    let errors = cfg.validate();
    assert!(errors
        .iter()
        .any(|e| matches!(e.kind, ValidationKind::RecordingMaxDurationOutOfRange)));
}

#[test]
fn hotkey_keycode_zero_fails() {
    let mut cfg = Config {
        doubao: Some(DoubaoCreds {
            app_id: "x".into(),
            access_token: "y".into(),
            endpoint: "wss://example.invalid/asr".into(),
            model_id: "bigmodel-streaming".into(),
            ..Default::default()
        }),
        ..Config::default()
    };
    cfg.hotkey.keycode = 0;
    let errors = cfg.validate();
    assert!(errors
        .iter()
        .any(|e| matches!(e.kind, ValidationKind::HotkeyKeycodeUnset)));
}

#[test]
fn sherpa_threads_zero_fails() {
    let cfg = Config {
        backend: BackendChoice::Sherpa,
        sherpa: Some(SherpaPaths {
            model_dir: std::env::temp_dir(), // exists
            num_threads: 0,
            provider: "cpu".into(),
        }),
        ..Config::default()
    };
    let errors = cfg.validate();
    assert!(errors
        .iter()
        .any(|e| matches!(e.kind, ValidationKind::SherpaThreadsOutOfRange)));
}

#[test]
fn sherpa_threads_too_many_fails() {
    let cfg = Config {
        backend: BackendChoice::Sherpa,
        sherpa: Some(SherpaPaths {
            model_dir: std::env::temp_dir(),
            num_threads: 64,
            provider: "cpu".into(),
        }),
        ..Config::default()
    };
    let errors = cfg.validate();
    assert!(errors
        .iter()
        .any(|e| matches!(e.kind, ValidationKind::SherpaThreadsOutOfRange)));
}

#[test]
fn recording_max_duration_too_long_fails() {
    let cfg = Config {
        doubao: Some(DoubaoCreds {
            app_id: "x".into(),
            access_token: "y".into(),
            endpoint: "wss://example.invalid/asr".into(),
            model_id: "bigmodel-streaming".into(),
            ..Default::default()
        }),
        recording_max_duration_secs: 601,
        ..Config::default()
    };
    let errors = cfg.validate();
    assert!(errors
        .iter()
        .any(|e| matches!(e.kind, ValidationKind::RecordingMaxDurationOutOfRange)));
}
