//! voco — terminal entry point.

use clap::{Parser, Subcommand};
use std::path::PathBuf;

mod commands;

#[derive(Parser)]
#[command(
    name = "voco",
    version,
    about = "Terminal-controlled voice input for macOS"
)]
struct Cli {
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Show daemon status
    Status,
    /// Daemon lifecycle: start | stop | restart | logs
    Daemon {
        #[command(subcommand)]
        action: DaemonAction,
    },
    /// Configuration: wizard | show | set | edit | reset | validate
    Config {
        #[command(subcommand)]
        action: Option<ConfigAction>,
    },
    /// Self-diagnostic
    Doctor,
    /// Internal recording smoke command for Phase 3 development.
    #[command(name = "_internal_record", hide = true)]
    InternalRecord {
        /// How many seconds to record. Accepts `3` or `3s`.
        #[arg(long, default_value = "5")]
        duration: String,
        /// Print returned partial snapshots.
        #[arg(long)]
        show_partials: bool,
        /// Placeholder for Phase 3 amplitude debugging.
        #[arg(long)]
        debug_amp: bool,
    },
}

#[derive(Subcommand)]
pub enum DaemonAction {
    /// Install the user LaunchAgent plist without starting the daemon.
    Install {
        /// Install a LaunchAgent that runs voco-daemon from this Voco.app bundle.
        #[arg(long, value_name = "PATH")]
        app_bundle: Option<PathBuf>,
    },
    /// Stop and remove the user LaunchAgent plist. Config and logs are preserved.
    Uninstall,
    Start,
    Stop,
    Restart,
    Logs {
        #[arg(short, long)]
        follow: bool,
        /// How many trailing lines to show before following.
        #[arg(short = 'n', long, default_value_t = 50)]
        lines: u32,
    },
}

#[derive(Subcommand)]
pub enum ConfigAction {
    /// Print the current config (access_token masked).
    Show {
        /// Print the actual token. Use only for verifying creds.
        #[arg(long)]
        unsafe_show_secrets: bool,
    },
    /// Set a single leaf field by dotted path.
    Set { key: String, value: String },
    /// Open `$EDITOR` on the config file (validates after save).
    Edit,
    /// Reset to default config. Requires confirmation.
    Reset {
        /// Skip the y/N confirmation. Use in scripts.
        #[arg(short = 'y', long)]
        yes: bool,
    },
    /// Exit 0 if config is valid, 1 otherwise.
    Validate,
}

fn main() -> anyhow::Result<()> {
    init_log();
    let cli = Cli::parse();
    match cli.command {
        Cmd::Status => commands::status::run(),
        Cmd::Daemon { action } => commands::daemon::run(action),
        Cmd::Config { action } => commands::config::run(action),
        Cmd::Doctor => commands::doctor::run(),
        Cmd::InternalRecord {
            duration,
            show_partials,
            debug_amp,
        } => commands::internal_record::run(duration, show_partials, debug_amp),
    }
}

fn init_log() {
    let env = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("warn"));
    let _ = tracing_subscriber::fmt()
        .with_env_filter(env)
        .with_writer(std::io::stderr)
        .with_target(false)
        .compact()
        .try_init();
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    #[test]
    fn parses_daemon_install_uninstall_actions() {
        let install = Cli::try_parse_from(["voco", "daemon", "install"]).unwrap();
        assert!(matches!(
            install.command,
            Cmd::Daemon {
                action: DaemonAction::Install { app_bundle: None }
            }
        ));

        let install_bundle = Cli::try_parse_from([
            "voco",
            "daemon",
            "install",
            "--app-bundle",
            "target/Voco.app",
        ])
        .unwrap();
        match install_bundle.command {
            Cmd::Daemon {
                action:
                    DaemonAction::Install {
                        app_bundle: Some(path),
                    },
            } => assert_eq!(path, std::path::PathBuf::from("target/Voco.app")),
            _ => panic!("unexpected command"),
        }

        let uninstall = Cli::try_parse_from(["voco", "daemon", "uninstall"]).unwrap();
        assert!(matches!(
            uninstall.command,
            Cmd::Daemon {
                action: DaemonAction::Uninstall
            }
        ));
    }

    #[test]
    fn parses_app_install_action() {
        let install = Cli::try_parse_from([
            "voco",
            "app",
            "install",
            "--app-bundle",
            "target/Voco.app",
        ])
        .unwrap();

        match install.command {
            Cmd::App {
                action:
                    AppAction::Install {
                        app_bundle: path,
                    },
            } => assert_eq!(path, std::path::PathBuf::from("target/Voco.app")),
            _ => panic!("unexpected command"),
        }
    }
}
