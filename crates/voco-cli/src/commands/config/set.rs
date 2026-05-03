//! `voco config set <key> <value>` — mutate a single leaf field by dotted
//! path, then validate + save + best-effort daemon reload.
//!
//! Whitelist only. Anything off the list is rejected with a hint to use
//! `voco config edit` for nested changes.

use crate::commands::config::notify::{notify_daemon_reload, print_outcome};
use anyhow::{anyhow, bail, Context, Result};
use std::path::PathBuf;
use std::str::FromStr;
use voco_config::{
    BackendChoice, Config, ConfigIo, DoubaoCreds, HudStyle, LogLevel, OutputMode, SherpaPaths,
};

pub fn run(key: &str, value: &str) -> Result<()> {
    let path = ConfigIo::default_path();
    let mut cfg =
        ConfigIo::load_from(&path).with_context(|| format!("failed to load {}", path.display()))?;

    apply(&mut cfg, key, value).with_context(|| format!("could not set `{key}` = `{value}`"))?;

    ConfigIo::save_to(&path, &cfg)
        .with_context(|| format!("failed to write {}", path.display()))?;

    if key == "doubao.access_token" {
        println!("✓ Saved (token masked).");
    } else {
        println!("✓ {key} = {value}");
    }

    // Validate AFTER saving — saving an in-progress config is fine, but the
    // user should see what's still missing so they can fix it next.
    let errs = cfg.validate();
    if !errs.is_empty() {
        println!("⚠ config still has {} unresolved issue(s):", errs.len());
        for e in &errs {
            println!("  - {e}");
        }
        println!("  run `voco config validate` once you've filled them in.");
    }

    print_outcome(notify_daemon_reload());
    Ok(())
}

fn apply(cfg: &mut Config, key: &str, value: &str) -> Result<()> {
    match key {
        "backend" => cfg.backend = parse_backend(value)?,
        "hotkey.keycode" => cfg.hotkey.keycode = parse_num(value)?,
        "hotkey.modifiers" => cfg.hotkey.modifiers = parse_num(value)?,
        "hotkey.display_name" => cfg.hotkey.display_name = value.to_string(),
        "output.mode" => cfg.output.mode = parse_output_mode(value)?,
        "output.trim_trailing_punct" => cfg.output.trim_trailing_punct = parse_bool(value)?,
        "output.auto_capitalize" => cfg.output.auto_capitalize = parse_bool(value)?,
        "hud.style" => cfg.hud.style = parse_hud_style(value)?,
        "log_level" => cfg.log_level = parse_log_level(value)?,
        "recording_max_duration_secs" => cfg.recording_max_duration_secs = parse_num(value)?,

        "doubao.app_id" => doubao_mut(cfg).app_id = value.to_string(),
        "doubao.access_token" => doubao_mut(cfg).access_token = value.to_string(),
        "doubao.api_key" => {
            doubao_mut(cfg).api_key = if value.is_empty() {
                None
            } else {
                Some(value.to_string())
            }
        }
        "doubao.endpoint" => doubao_mut(cfg).endpoint = value.to_string(),
        "doubao.model_id" => doubao_mut(cfg).model_id = value.to_string(),
        "doubao.resource_id" => doubao_mut(cfg).resource_id = value.to_string(),

        "sherpa.model_dir" => sherpa_mut(cfg).model_dir = PathBuf::from(value),
        "sherpa.num_threads" => sherpa_mut(cfg).num_threads = parse_num(value)?,
        "sherpa.provider" => sherpa_mut(cfg).provider = value.to_string(),

        other => {
            bail!(
                "unknown leaf key `{other}` — for nested edits use `voco config edit`. \
                 valid keys: see the spec at docs/superpowers/specs/2026-05-01-voco-design.md §3.1"
            );
        }
    }
    Ok(())
}

fn parse_num<T: FromStr>(s: &str) -> Result<T>
where
    T::Err: std::fmt::Display,
{
    s.parse::<T>().map_err(|e| anyhow!("not a number: {e}"))
}

fn parse_bool(s: &str) -> Result<bool> {
    match s.to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" | "on" => Ok(true),
        "false" | "0" | "no" | "off" => Ok(false),
        other => Err(anyhow!("not a bool: `{other}` (use true/false)")),
    }
}

fn parse_backend(s: &str) -> Result<BackendChoice> {
    match s.to_ascii_lowercase().as_str() {
        "doubao" => Ok(BackendChoice::Doubao),
        "sherpa" => Ok(BackendChoice::Sherpa),
        _ => Err(anyhow!("unknown backend `{s}` (try doubao | sherpa)")),
    }
}

fn parse_output_mode(s: &str) -> Result<OutputMode> {
    match s.to_ascii_lowercase().as_str() {
        "inject_then_clipboard" | "inject" => Ok(OutputMode::InjectThenClipboard),
        "clipboard_only" | "clipboard" => Ok(OutputMode::ClipboardOnly),
        _ => Err(anyhow!(
            "unknown output mode `{s}` (try inject_then_clipboard | clipboard_only)"
        )),
    }
}

fn parse_hud_style(s: &str) -> Result<HudStyle> {
    match s.to_ascii_lowercase().as_str() {
        "capsule" => Ok(HudStyle::Capsule),
        "minimal" => Ok(HudStyle::Minimal),
        "disabled" => Ok(HudStyle::Disabled),
        _ => Err(anyhow!(
            "unknown hud style `{s}` (try capsule | minimal | disabled)"
        )),
    }
}

fn parse_log_level(s: &str) -> Result<LogLevel> {
    match s.to_ascii_lowercase().as_str() {
        "trace" => Ok(LogLevel::Trace),
        "debug" => Ok(LogLevel::Debug),
        "info" => Ok(LogLevel::Info),
        "warn" => Ok(LogLevel::Warn),
        "error" => Ok(LogLevel::Error),
        _ => Err(anyhow!("unknown log level `{s}`")),
    }
}

fn doubao_mut(cfg: &mut Config) -> &mut DoubaoCreds {
    cfg.doubao.get_or_insert_with(|| DoubaoCreds {
        app_id: String::new(),
        access_token: String::new(),
        api_key: None,
        endpoint: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream".to_string(),
        model_id: "bigmodel".to_string(),
        resource_id: "volc.seedasr.sauc.duration".to_string(),
    })
}

fn sherpa_mut(cfg: &mut Config) -> &mut SherpaPaths {
    cfg.sherpa.get_or_insert_with(|| SherpaPaths {
        model_dir: PathBuf::new(),
        num_threads: 1,
        provider: "cpu".to_string(),
    })
}
