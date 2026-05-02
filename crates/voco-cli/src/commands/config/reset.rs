//! `voco config reset` — overwrite config with `Config::default()`.

use crate::commands::config::notify::{notify_daemon_reload, print_outcome};
use anyhow::{anyhow, Context, Result};
use std::io::{self, IsTerminal, Write};
use voco_config::{Config, ConfigIo};

pub fn run(skip_confirm: bool) -> Result<()> {
    let path = ConfigIo::default_path();
    println!("This will overwrite {}.", path.display());
    println!("Doubao credentials and any custom hotkey will be lost.");

    if !skip_confirm {
        if !io::stdin().is_terminal() {
            return Err(anyhow!(
                "refusing to reset without confirmation in a non-interactive shell — \
                 pass `--yes` to override"
            ));
        }
        print!("Continue? [y/N] ");
        io::stdout().flush().ok();
        let mut buf = String::new();
        io::stdin().read_line(&mut buf)?;
        if !matches!(buf.trim().to_ascii_lowercase().as_str(), "y" | "yes") {
            println!("aborted.");
            return Ok(());
        }
    }

    ConfigIo::save_to(&path, &Config::default())
        .with_context(|| format!("failed to write {}", path.display()))?;
    println!("✓ reset to defaults at {}", path.display());
    print_outcome(notify_daemon_reload());
    Ok(())
}
