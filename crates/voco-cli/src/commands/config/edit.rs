//! `voco config edit` — open `$EDITOR` on the config file. After save,
//! re-validate; on validation failure, ask "re-edit / discard / save anyway".

use crate::commands::config::notify::{notify_daemon_reload, print_outcome};
use anyhow::{anyhow, Context, Result};
use std::fs;
use std::io::{self, IsTerminal, Write};
use std::path::Path;
use std::process::Command;
use voco_config::{Config, ConfigIo};

pub fn run() -> Result<()> {
    let path = ConfigIo::default_path();
    if !path.exists() {
        // Make sure $EDITOR has something to open. Save defaults first.
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        ConfigIo::save_to(&path, &Config::default())?;
    }
    let backup = make_backup(&path)?;

    let editor = std::env::var("EDITOR")
        .or_else(|_| std::env::var("VISUAL"))
        .unwrap_or_else(|_| "vi".to_string());

    let status = Command::new(&editor)
        .arg(&path)
        .status()
        .with_context(|| format!("could not launch editor `{editor}` on {}", path.display()))?;
    if !status.success() {
        return Err(anyhow!("editor `{editor}` exited with {status}"));
    }

    loop {
        match ConfigIo::load_from(&path) {
            Ok(c) => {
                let errs = c.validate();
                if errs.is_empty() {
                    println!("✓ saved & valid: {}", path.display());
                    print_outcome(notify_daemon_reload());
                    return Ok(());
                }
                eprintln!(
                    "⚠ {} has {} unresolved issue(s):",
                    path.display(),
                    errs.len()
                );
                for e in &errs {
                    eprintln!("  - {}", e);
                }
                if !io::stdin().is_terminal() {
                    // Script context: keep what the editor produced. This makes
                    // `EDITOR=true voco config edit` viable in tests / CI.
                    println!("  (non-interactive stdin — keeping the file as-is)");
                    return Ok(());
                }
            }
            Err(e) => {
                eprintln!("✗ could not parse {}: {e}", path.display());
                if !io::stdin().is_terminal() {
                    fs::copy(&backup, &path)?;
                    eprintln!("↻ non-interactive stdin — restored from backup");
                    return Err(anyhow!("config file is unparseable"));
                }
            }
        }
        match prompt_recovery()? {
            Recovery::ReEdit => {
                Command::new(&editor).arg(&path).status().ok();
            }
            Recovery::Discard => {
                fs::copy(&backup, &path)?;
                println!("↻ restored from backup");
                return Ok(());
            }
            Recovery::SaveAnyway => {
                println!("⚠ kept invalid config at {}", path.display());
                return Ok(());
            }
        }
    }
}

enum Recovery {
    ReEdit,
    Discard,
    SaveAnyway,
}

fn prompt_recovery() -> Result<Recovery> {
    print!("[r]e-edit / [d]iscard / [s]ave anyway? ");
    io::stdout().flush().ok();
    let mut buf = String::new();
    io::stdin().read_line(&mut buf)?;
    Ok(match buf.trim().to_ascii_lowercase().as_str() {
        "d" | "discard" => Recovery::Discard,
        "s" | "save" => Recovery::SaveAnyway,
        _ => Recovery::ReEdit,
    })
}

fn make_backup(path: &Path) -> Result<std::path::PathBuf> {
    let bak = path.with_extension("toml.bak");
    fs::copy(path, &bak)?;
    Ok(bak)
}
