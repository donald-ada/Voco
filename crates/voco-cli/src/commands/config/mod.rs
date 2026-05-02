//! `voco config` — driver. Each subcommand lives in its own file so the
//! match in `run()` stays a thin dispatcher.
//!
//! `voco config` (no args) launches the interactive wizard (Task 3, not yet
//! implemented). For now, no-args prints usage.

use crate::ConfigAction;
use anyhow::Result;

pub mod edit;
pub mod hotkey_preset;
pub mod keymap;
pub mod notify;
pub mod reset;
pub mod set;
pub mod show;
pub mod validate;
pub mod wizard;

pub fn run(action: Option<ConfigAction>) -> Result<()> {
    match action {
        None => wizard::run(),
        Some(ConfigAction::Show {
            unsafe_show_secrets,
        }) => show::run(unsafe_show_secrets),
        Some(ConfigAction::Set { key, value }) => set::run(&key, &value),
        Some(ConfigAction::Validate) => validate::run(),
        Some(ConfigAction::Reset { yes }) => reset::run(yes),
        Some(ConfigAction::Edit) => edit::run(),
    }
}
