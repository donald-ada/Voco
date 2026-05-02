//! `Config::redacted_clone()` must mask `access_token` and never reveal length.

use voco_config::*;

fn cfg_with_token(token: &str) -> Config {
    Config {
        backend: BackendChoice::Doubao,
        doubao: Some(DoubaoCreds {
            app_id: "AID-123".into(),
            access_token: token.into(),
            endpoint: "wss://example/api".into(),
            model_id: "bigmodel".into(),
            ..Default::default()
        }),
        ..Default::default()
    }
}

#[test]
fn redacted_replaces_access_token() {
    let c = cfg_with_token("supersecret");
    let r = c.redacted_clone();
    assert_eq!(r.doubao.as_ref().unwrap().access_token, "********");
    // Other fields unchanged.
    assert_eq!(r.doubao.as_ref().unwrap().app_id, "AID-123");
}

#[test]
fn redacted_token_does_not_reveal_length() {
    let short = cfg_with_token("ab").redacted_clone();
    let long = cfg_with_token(&"x".repeat(500)).redacted_clone();
    assert_eq!(
        short.doubao.unwrap().access_token,
        long.doubao.unwrap().access_token
    );
}

#[test]
fn redacted_serialized_toml_does_not_contain_secret() {
    let c = cfg_with_token("CORRECT-HORSE-BATTERY-STAPLE");
    let s = toml::to_string_pretty(&c.redacted_clone()).unwrap();
    assert!(!s.contains("CORRECT-HORSE-BATTERY-STAPLE"));
    assert!(s.contains("********"));
}

#[test]
fn redacted_with_no_doubao_is_noop() {
    let c = Config {
        doubao: None,
        ..Default::default()
    };
    assert_eq!(c.redacted_clone(), c);
}

#[test]
fn redacted_with_empty_token_stays_empty() {
    let c = cfg_with_token("");
    let r = c.redacted_clone();
    assert_eq!(r.doubao.unwrap().access_token, "");
}
