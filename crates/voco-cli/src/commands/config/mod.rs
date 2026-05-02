//! `voco config` — driver. Each subcommand lives in its own file so the
//! match in `run()` stays a thin dispatcher.
//!
//! `voco config` (no args) launches the interactive wizard (Task 3, not yet
//! implemented). For now, no-args prints usage.

use crate::ConfigAction;
use anyhow::Result;

pub mod edit;
pub mod notify;
pub mod reset;
pub mod set;
pub mod show;
pub mod validate;

pub fn run(action: Option<ConfigAction>) -> Result<()> {
    match action {
        None => {
            eprintln!("voco config: interactive wizard lands in Task 3");
            eprintln!("  available now: voco config show / set / validate / reset / edit");
            std::process::exit(1);
        }
        Some(ConfigAction::Show {
            unsafe_show_secrets,
        }) => show::run(unsafe_show_secrets),
        Some(ConfigAction::Set { key, value }) => set::run(&key, &value),
        Some(ConfigAction::Validate) => validate::run(),
        Some(ConfigAction::Reset { yes }) => reset::run(yes),
        Some(ConfigAction::Edit) => edit::run(),
    }
}
