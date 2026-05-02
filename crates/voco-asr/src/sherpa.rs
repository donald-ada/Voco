//! Sherpa-onnx local backend — placeholder. Phase 2 settles the trait
//! shape; the real implementation lands post-MVP.

use crate::{AsrBackend, AsrError, Final, Partial};
use async_trait::async_trait;

pub struct SherpaBackend;

impl SherpaBackend {
    pub fn new() -> Self {
        Self
    }
}

impl Default for SherpaBackend {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl AsrBackend for SherpaBackend {
    async fn start(&mut self) -> Result<(), AsrError> {
        Err(AsrError::NotImplemented(
            "sherpa-onnx local backend lands post-MVP",
        ))
    }

    async fn feed(&mut self, _pcm: &[i16]) -> Result<Option<Partial>, AsrError> {
        Err(AsrError::NotImplemented("sherpa.feed"))
    }

    async fn stop(&mut self) -> Result<Final, AsrError> {
        Err(AsrError::NotImplemented("sherpa.stop"))
    }

    fn name(&self) -> &'static str {
        "sherpa"
    }
}
