use crate::ConfigAction;
use anyhow::Result;

pub fn run(_action: Option<ConfigAction>) -> Result<()> {
    eprintln!("voco config: implemented in Phase 2");
    std::process::exit(1);
}
