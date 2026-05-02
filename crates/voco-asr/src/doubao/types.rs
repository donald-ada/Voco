//! JSON payload types for Doubao's `full client request`. Serialized to
//! JSON, gzipped, then sent as the FullClientRequest frame body.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize)]
pub struct FullClientRequest {
    pub user: User,
    pub audio: Audio,
    pub request: RequestParams,
}

#[derive(Debug, Clone, Serialize)]
pub struct User {
    pub uid: String,
    pub platform: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct Audio {
    pub format: String,
    pub codec: String,
    pub rate: u32,
    pub bits: u32,
    pub channel: u32,
}

#[derive(Debug, Clone, Serialize)]
pub struct RequestParams {
    pub model_name: String,
    pub enable_punc: bool,
    pub enable_itn: bool,
    pub enable_ddc: bool,
    pub result_type: String,
    pub end_window_size: u32,
}

impl FullClientRequest {
    /// Default Voco settings: pcm s16le mono 16kHz, punctuation + ITN on,
    /// 800ms VAD silence threshold, full result mode.
    pub fn voco_defaults() -> Self {
        Self {
            user: User {
                uid: "voco".to_string(),
                platform: "macOS".to_string(),
            },
            audio: Audio {
                format: "pcm".to_string(),
                codec: "raw".to_string(),
                rate: 16000,
                bits: 16,
                channel: 1,
            },
            request: RequestParams {
                model_name: "bigmodel".to_string(),
                enable_punc: true,
                enable_itn: true,
                enable_ddc: false,
                result_type: "full".to_string(),
                end_window_size: 800,
            },
        }
    }
}

/// Server response payload. Maps to the JSON body of a FullServerResponse
/// frame after gunzip.
#[derive(Debug, Clone, Deserialize, Default)]
pub struct ServerResponse {
    #[serde(default)]
    pub result: Option<ServerResult>,
    #[serde(default)]
    pub audio_info: Option<AudioInfo>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct ServerResult {
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub utterances: Vec<Utterance>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Utterance {
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub start_time: u32,
    #[serde(default)]
    pub end_time: u32,
    #[serde(default)]
    pub definite: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AudioInfo {
    #[serde(default)]
    pub duration: u32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn full_client_request_serializes_to_known_keys() {
        let r = FullClientRequest::voco_defaults();
        let v: serde_json::Value = serde_json::to_value(&r).unwrap();
        assert_eq!(v["audio"]["format"], "pcm");
        assert_eq!(v["audio"]["rate"], 16000);
        assert_eq!(v["request"]["model_name"], "bigmodel");
        assert_eq!(v["request"]["enable_punc"], true);
        assert_eq!(v["request"]["end_window_size"], 800);
    }

    #[test]
    fn parses_doc_response_example() {
        // Pasted directly from volcengine-api.md §full server response example.
        let json = r#"
        {
          "audio_info": {"duration": 10000},
          "result": {
              "text": "这是字节跳动， 今日头条母公司。",
              "utterances": [
                {
                  "definite": true,
                  "end_time": 1705,
                  "start_time": 0,
                  "text": "这是字节跳动，",
                  "words": []
                },
                {
                  "definite": true,
                  "end_time": 3696,
                  "start_time": 2110,
                  "text": "今日头条母公司。",
                  "words": []
                }
              ]
           }
        }
        "#;
        let r: ServerResponse = serde_json::from_str(json).unwrap();
        let result = r.result.unwrap();
        assert_eq!(result.text, "这是字节跳动， 今日头条母公司。");
        assert_eq!(result.utterances.len(), 2);
        assert!(result.utterances[0].definite);
        assert_eq!(result.utterances[0].text, "这是字节跳动，");
    }

    #[test]
    fn parses_response_with_no_result() {
        let r: ServerResponse = serde_json::from_str("{}").unwrap();
        assert!(r.result.is_none());
        assert!(r.audio_info.is_none());
    }
}
