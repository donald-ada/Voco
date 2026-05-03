//! `voco config` (no args) — interactive wizard.
//!
//! Architecture: separate **engine** (`apply_choices` — pure, unit-testable)
//! from **prompts** (inquire-driven, hard to test). The engine takes a
//! `WizardChoices` struct; the prompt layer fills it from user input.

use super::hotkey_preset::HotkeyPreset;
use super::keymap;
use super::notify::{notify_daemon_reload, print_outcome};
use anyhow::{anyhow, Context, Result};
use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode};
use inquire::{Confirm, Password, PasswordDisplayMode, Select, Text};
use std::time::Duration;
use voco_config::{
    BackendChoice, Config, ConfigIo, DoubaoCreds, HotkeyConfig, HudStyle, OutputMode,
};

#[derive(Debug, Clone)]
pub struct WizardChoices {
    pub backend: BackendChoice,
    pub hotkey: HotkeyConfig,
    pub output_mode: OutputMode,
    pub hud_style: HudStyle,
    pub doubao: Option<DoubaoCreds>,
}

pub fn apply_choices(cfg: &mut Config, c: WizardChoices) {
    cfg.backend = c.backend;
    cfg.hotkey = c.hotkey;
    cfg.output.mode = c.output_mode;
    cfg.hud.style = c.hud_style;
    if let Some(d) = c.doubao {
        cfg.doubao = Some(d);
    }
}

pub fn run() -> Result<()> {
    let path = ConfigIo::default_path();
    let mut cfg =
        ConfigIo::load_from(&path).with_context(|| format!("failed to load {}", path.display()))?;

    println!("✓ Loaded config from {}", path.display());
    println!();

    let choices = match prompt_choices(&cfg) {
        Ok(c) => c,
        Err(e) if e.to_string() == "aborted" => {
            println!("aborted.");
            return Ok(());
        }
        Err(e) => return Err(e),
    };

    let new_cfg = {
        let mut c = cfg.clone();
        apply_choices(&mut c, choices);
        c
    };

    print_diff(&cfg, &new_cfg);

    let go = Confirm::new("Apply these changes?")
        .with_default(true)
        .prompt()
        .map_err(|e| anyhow!("confirm: {e}"))?;
    if !go {
        println!("aborted.");
        return Ok(());
    }

    cfg = new_cfg;
    ConfigIo::save_to(&path, &cfg)
        .with_context(|| format!("failed to write {}", path.display()))?;
    println!("✓ Saved to {}", path.display());

    let errs = cfg.validate();
    if !errs.is_empty() {
        println!("⚠ config still has {} unresolved issue(s):", errs.len());
        for e in &errs {
            println!("  - {e}");
        }
    }

    print_outcome(notify_daemon_reload());
    Ok(())
}

fn prompt_choices(current: &Config) -> Result<WizardChoices> {
    // 1. Backend
    let backend = {
        let opts = vec!["doubao (cloud)", "sherpa (local — not yet implemented)"];
        let default = match current.backend {
            BackendChoice::Doubao => 0,
            BackendChoice::Sherpa => 1,
        };
        let pick = Select::new("Default ASR backend", opts)
            .with_starting_cursor(default)
            .prompt()
            .map_err(|e| anyhow!("backend: {e}"))?;
        if pick.starts_with("doubao") {
            BackendChoice::Doubao
        } else {
            println!("  (sherpa selected — note: not implemented in MVP)");
            BackendChoice::Sherpa
        }
    };

    // 2. Hotkey
    let hotkey = {
        let opts: Vec<&str> = HotkeyPreset::ALL.iter().map(|p| p.label()).collect();
        let default = HotkeyPreset::from_config(&current.hotkey)
            .map(|p| HotkeyPreset::ALL.iter().position(|x| *x == p).unwrap())
            .unwrap_or(0);
        let pick = Select::new("Hotkey", opts.clone())
            .with_starting_cursor(default)
            .prompt()
            .map_err(|e| anyhow!("hotkey: {e}"))?;
        let preset = HotkeyPreset::ALL[opts.iter().position(|x| *x == pick).unwrap()];
        match preset.to_config() {
            Some(cfg) => cfg,
            None => capture_custom_hotkey()?,
        }
    };

    // 3. Output mode
    let output_mode = {
        let opts = vec![
            "Inject to focused app, fall back to clipboard (recommended)",
            "Clipboard only (manual paste)",
        ];
        let default = match current.output.mode {
            OutputMode::InjectThenClipboard => 0,
            OutputMode::ClipboardOnly => 1,
        };
        let pick = Select::new("Text output mode", opts)
            .with_starting_cursor(default)
            .prompt()
            .map_err(|e| anyhow!("output: {e}"))?;
        if pick.starts_with("Inject") {
            OutputMode::InjectThenClipboard
        } else {
            OutputMode::ClipboardOnly
        }
    };

    // 4. Doubao creds (optional)
    let doubao = if matches!(backend, BackendChoice::Doubao) {
        let want = Confirm::new("Configure Doubao credentials now?")
            .with_default(current.doubao.is_none() || creds_incomplete(current))
            .prompt()
            .map_err(|e| anyhow!("doubao prompt: {e}"))?;
        if want {
            Some(prompt_doubao_creds(current.doubao.as_ref())?)
        } else {
            None
        }
    } else {
        None
    };

    // 5. HUD style
    let hud_style = {
        let opts = vec![
            "Capsule (mic + waveform + dot)",
            "Minimal (single dot)",
            "Disabled",
        ];
        let default = match current.hud.style {
            HudStyle::Capsule => 0,
            HudStyle::Minimal => 1,
            HudStyle::Disabled => 2,
        };
        let pick = Select::new("HUD style", opts)
            .with_starting_cursor(default)
            .prompt()
            .map_err(|e| anyhow!("hud: {e}"))?;
        if pick.starts_with("Capsule") {
            HudStyle::Capsule
        } else if pick.starts_with("Minimal") {
            HudStyle::Minimal
        } else {
            HudStyle::Disabled
        }
    };

    Ok(WizardChoices {
        backend,
        hotkey,
        output_mode,
        hud_style,
        doubao,
    })
}

fn creds_incomplete(c: &Config) -> bool {
    match &c.doubao {
        None => true,
        Some(d) => {
            d.app_id.is_empty()
                || d.access_token.is_empty()
                || d.endpoint.is_empty()
                || d.model_id.is_empty()
        }
    }
}

fn prompt_doubao_creds(current: Option<&DoubaoCreds>) -> Result<DoubaoCreds> {
    let app_id = Text::new("App ID")
        .with_default(current.map(|c| c.app_id.as_str()).unwrap_or(""))
        .prompt()
        .map_err(|e| anyhow!("app_id: {e}"))?;

    let access_token = Password::new("Access Token")
        .with_display_mode(PasswordDisplayMode::Masked)
        .without_confirmation()
        .prompt()
        .map_err(|e| anyhow!("access_token: {e}"))?;

    let endpoint_default = current
        .map(|c| c.endpoint.clone())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| {
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream".to_string()
        });
    let endpoint = Text::new("Endpoint")
        .with_default(&endpoint_default)
        .prompt()
        .map_err(|e| anyhow!("endpoint: {e}"))?;

    let model_opts = vec!["bigmodel", "bigmodel_async", "bigmodel_nostream"];
    let model_default = current
        .map(|c| c.model_id.as_str())
        .filter(|s| model_opts.contains(s))
        .map(|s| model_opts.iter().position(|x| *x == s).unwrap())
        .unwrap_or(0);
    let model_id = Select::new("Model", model_opts.clone())
        .with_starting_cursor(model_default)
        .prompt()
        .map_err(|e| anyhow!("model_id: {e}"))?;

    Ok(DoubaoCreds {
        app_id,
        access_token,
        api_key: current.and_then(|c| c.api_key.clone()),
        endpoint,
        model_id: model_id.to_string(),
        resource_id: current
            .map(|c| c.resource_id.clone())
            .unwrap_or_else(|| "volc.seedasr.sauc.duration".to_string()),
    })
}

/// Capture a real keypress in raw mode. Always re-disables raw mode, even
/// on panic (Drop guard).
fn capture_custom_hotkey() -> Result<HotkeyConfig> {
    println!("  Press the desired hotkey now (Esc to cancel)…");
    let _guard = RawModeGuard::enter()?;

    loop {
        if !event::poll(Duration::from_millis(500))? {
            continue;
        }
        match event::read()? {
            Event::Key(k) if k.kind == KeyEventKind::Press => {
                if k.code == KeyCode::Esc {
                    return Err(anyhow!("aborted"));
                }
                if let Some(h) = keymap::capture(&k) {
                    println!("  ↳ captured: {}", h.display_name);
                    return Ok(HotkeyConfig {
                        keycode: h.keycode,
                        modifiers: h.modifiers,
                        display_name: h.display_name,
                    });
                }
                println!("  (key not recognized — try a different one)");
            }
            _ => {}
        }
    }
}

struct RawModeGuard;

impl RawModeGuard {
    fn enter() -> Result<Self> {
        enable_raw_mode().map_err(|e| anyhow!("enable raw mode: {e}"))?;
        Ok(Self)
    }
}

impl Drop for RawModeGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
    }
}

fn print_diff(old: &Config, new: &Config) {
    println!();
    println!("─── Summary of changes ───");
    let mut changed = false;
    if old.backend != new.backend {
        println!(
            "  backend:           {} → {}",
            backend_str(old.backend),
            backend_str(new.backend)
        );
        changed = true;
    }
    if old.hotkey != new.hotkey {
        println!(
            "  hotkey:            {} → {}",
            old.hotkey.display_name, new.hotkey.display_name
        );
        changed = true;
    }
    if old.output.mode != new.output.mode {
        println!(
            "  output.mode:       {:?} → {:?}",
            old.output.mode, new.output.mode
        );
        changed = true;
    }
    if old.hud.style != new.hud.style {
        println!(
            "  hud.style:         {:?} → {:?}",
            old.hud.style, new.hud.style
        );
        changed = true;
    }
    match (&old.doubao, &new.doubao) {
        (None, Some(_)) => {
            println!("  doubao:            (added)");
            changed = true;
        }
        (Some(o), Some(n)) if o != n => {
            println!(
                "  doubao:            updated (token {})",
                if o.access_token == n.access_token {
                    "unchanged"
                } else {
                    "changed"
                }
            );
            changed = true;
        }
        _ => {}
    }
    if !changed {
        println!("  (no changes)");
    }
    println!("──────────────────────────");
    println!();
}

fn backend_str(b: BackendChoice) -> &'static str {
    match b {
        BackendChoice::Doubao => "doubao",
        BackendChoice::Sherpa => "sherpa",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base_cfg() -> Config {
        Config::default()
    }

    #[test]
    fn apply_choices_overwrites_targeted_fields() {
        let mut cfg = base_cfg();
        let choices = WizardChoices {
            backend: BackendChoice::Sherpa,
            hotkey: HotkeyConfig {
                keycode: 80,
                modifiers: 0,
                display_name: "F19".into(),
            },
            output_mode: OutputMode::ClipboardOnly,
            hud_style: HudStyle::Minimal,
            doubao: None,
        };
        apply_choices(&mut cfg, choices);
        assert_eq!(cfg.backend, BackendChoice::Sherpa);
        assert_eq!(cfg.hotkey.display_name, "F19");
        assert_eq!(cfg.output.mode, OutputMode::ClipboardOnly);
        assert_eq!(cfg.hud.style, HudStyle::Minimal);
    }

    #[test]
    fn apply_choices_with_no_doubao_keeps_existing() {
        let mut cfg = base_cfg();
        cfg.doubao = Some(DoubaoCreds {
            app_id: "X".into(),
            access_token: "Y".into(),
            endpoint: "Z".into(),
            model_id: "M".into(),
            ..Default::default()
        });
        let choices = WizardChoices {
            backend: BackendChoice::Doubao,
            hotkey: cfg.hotkey.clone(),
            output_mode: cfg.output.mode,
            hud_style: cfg.hud.style,
            doubao: None,
        };
        apply_choices(&mut cfg, choices);
        assert_eq!(cfg.doubao.unwrap().app_id, "X");
    }

    #[test]
    fn apply_choices_with_doubao_replaces() {
        let mut cfg = base_cfg();
        let new = DoubaoCreds {
            app_id: "NEW".into(),
            access_token: "TKN".into(),
            endpoint: "ENDP".into(),
            model_id: "bigmodel".into(),
            ..Default::default()
        };
        let choices = WizardChoices {
            backend: BackendChoice::Doubao,
            hotkey: cfg.hotkey.clone(),
            output_mode: cfg.output.mode,
            hud_style: cfg.hud.style,
            doubao: Some(new.clone()),
        };
        apply_choices(&mut cfg, choices);
        assert_eq!(cfg.doubao.unwrap(), new);
    }

    #[test]
    fn creds_incomplete_for_default_config() {
        let c = base_cfg();
        assert!(creds_incomplete(&c));
    }

    #[test]
    fn creds_incomplete_with_partial() {
        let c = Config {
            doubao: Some(DoubaoCreds {
                app_id: "x".into(),
                access_token: "".into(),
                endpoint: "y".into(),
                model_id: "m".into(),
                ..Default::default()
            }),
            ..Default::default()
        };
        assert!(creds_incomplete(&c));
    }

    #[test]
    fn creds_complete_when_all_set() {
        let c = Config {
            doubao: Some(DoubaoCreds {
                app_id: "x".into(),
                access_token: "y".into(),
                endpoint: "z".into(),
                model_id: "m".into(),
                ..Default::default()
            }),
            ..Default::default()
        };
        assert!(!creds_incomplete(&c));
    }
}
