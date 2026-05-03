use crate::AppAction;
use anyhow::{bail, Result};

pub fn run(action: AppAction) -> Result<()> {
    match action {
        AppAction::Install { .. } => {
            bail!("voco app install is parsed but install implementation is not wired yet")
        }
    }
}
