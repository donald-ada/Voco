//! `voco config show` — print the current config as TOML.
//! `access_token` is masked unless `--unsafe-show-secrets` is passed.

use anyhow::{Context, Result};
use voco_config::ConfigIo;

pub fn run(unsafe_show_secrets: bool) -> Result<()> {
    let path = ConfigIo::default_path();
    let cfg =
        ConfigIo::load_from(&path).with_context(|| format!("failed to load {}", path.display()))?;

    let to_print = if unsafe_show_secrets {
        eprintln!("⚠ printing secrets — do not paste this output anywhere public.");
        cfg
    } else {
        cfg.redacted_clone()
    };

    let s = toml::to_string_pretty(&to_print).context("serialize config to TOML")?;
    println!("# {}", path.display());
    print!("{}", s);
    Ok(())
}
