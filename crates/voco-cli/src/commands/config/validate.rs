//! `voco config validate` — exit 0 if valid, 1 otherwise.

use anyhow::Result;
use voco_config::ConfigIo;

pub fn run() -> Result<()> {
    let path = ConfigIo::default_path();
    let cfg = match ConfigIo::load_from(&path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("✗ failed to load {}: {e}", path.display());
            std::process::exit(1);
        }
    };
    let errs = cfg.validate();
    if errs.is_empty() {
        println!("✓ {} valid", path.display());
        Ok(())
    } else {
        eprintln!("✗ {} has {} error(s):", path.display(), errs.len());
        for e in errs {
            eprintln!("  - {}", e);
        }
        std::process::exit(1);
    }
}
