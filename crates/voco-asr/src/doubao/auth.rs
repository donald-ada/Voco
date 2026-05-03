//! Auth header builder for the Doubao WebSocket handshake. Supports
//! - **old console**: `X-Api-App-Key` + `X-Api-Access-Key`
//! - **new console**: `X-Api-Key` only
//!
//! Selection is automatic from the `DoubaoCreds` shape: if `api_key` is
//! `Some`, new-console wins. If both shapes are configured, new-console
//! takes precedence (matches Volcengine doc footnote).

use crate::AsrError;
use voco_config::DoubaoCreds;

/// Resolved auth headers ready to attach to a WS upgrade request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DoubaoAuth {
    pub headers: Vec<(String, String)>,
    pub request_id: String,
    pub connect_id: String,
}

impl DoubaoAuth {
    pub fn from_creds(c: &DoubaoCreds) -> Result<Self, AsrError> {
        let request_id = uuid::Uuid::new_v4().to_string();
        let connect_id = uuid::Uuid::new_v4().to_string();
        let mut headers = Vec::new();

        if let Some(api_key) = c.api_key.as_ref().filter(|s| !s.is_empty()) {
            headers.push(("X-Api-Key".to_string(), api_key.clone()));
        } else if !c.app_id.is_empty() && !c.access_token.is_empty() {
            headers.push(("X-Api-App-Key".to_string(), c.app_id.clone()));
            headers.push(("X-Api-Access-Key".to_string(), c.access_token.clone()));
        } else {
            return Err(AsrError::Auth(
                "doubao creds missing: need either api_key (new console) or app_id+access_token (old console)".into(),
            ));
        }

        if c.resource_id.is_empty() {
            return Err(AsrError::Auth("doubao.resource_id is empty".into()));
        }
        headers.push(("X-Api-Resource-Id".to_string(), c.resource_id.clone()));
        headers.push(("X-Api-Request-Id".to_string(), request_id.clone()));
        headers.push(("X-Api-Connect-Id".to_string(), connect_id.clone()));

        Ok(Self {
            headers,
            request_id,
            connect_id,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn old_console_creds() -> DoubaoCreds {
        DoubaoCreds {
            app_id: "APP-OLD".into(),
            access_token: "TOK-OLD".into(),
            ..Default::default()
        }
    }

    fn new_console_creds() -> DoubaoCreds {
        DoubaoCreds {
            api_key: Some("KEY-NEW".into()),
            ..Default::default()
        }
    }

    fn header_value<'a>(a: &'a DoubaoAuth, name: &str) -> Option<&'a str> {
        a.headers
            .iter()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.as_str())
    }

    #[test]
    fn old_console_emits_app_key_pair() {
        let a = DoubaoAuth::from_creds(&old_console_creds()).unwrap();
        assert_eq!(header_value(&a, "X-Api-App-Key"), Some("APP-OLD"));
        assert_eq!(header_value(&a, "X-Api-Access-Key"), Some("TOK-OLD"));
        assert!(header_value(&a, "X-Api-Key").is_none());
    }

    #[test]
    fn new_console_emits_single_key() {
        let a = DoubaoAuth::from_creds(&new_console_creds()).unwrap();
        assert_eq!(header_value(&a, "X-Api-Key"), Some("KEY-NEW"));
        assert!(header_value(&a, "X-Api-App-Key").is_none());
        assert!(header_value(&a, "X-Api-Access-Key").is_none());
    }

    #[test]
    fn new_console_wins_when_both_configured() {
        let mut c = old_console_creds();
        c.api_key = Some("KEY-NEW".into());
        let a = DoubaoAuth::from_creds(&c).unwrap();
        assert_eq!(header_value(&a, "X-Api-Key"), Some("KEY-NEW"));
        assert!(header_value(&a, "X-Api-App-Key").is_none());
    }

    #[test]
    fn empty_api_key_falls_through_to_old_console() {
        let mut c = old_console_creds();
        c.api_key = Some(String::new()); // empty doesn't count
        let a = DoubaoAuth::from_creds(&c).unwrap();
        assert_eq!(header_value(&a, "X-Api-App-Key"), Some("APP-OLD"));
    }

    #[test]
    fn missing_creds_errors() {
        let c = DoubaoCreds::default();
        let r = DoubaoAuth::from_creds(&c);
        assert!(matches!(r, Err(AsrError::Auth(_))));
    }

    #[test]
    fn resource_id_always_attached() {
        let a = DoubaoAuth::from_creds(&new_console_creds()).unwrap();
        assert_eq!(
            header_value(&a, "X-Api-Resource-Id"),
            Some("volc.seedasr.sauc.duration")
        );
    }

    #[test]
    fn request_and_connect_ids_are_uuids() {
        let a = DoubaoAuth::from_creds(&new_console_creds()).unwrap();
        // 36-char dashed UUID
        assert_eq!(a.request_id.len(), 36);
        assert_eq!(a.connect_id.len(), 36);
        assert_ne!(a.request_id, a.connect_id);
    }
}
