//! voco — terminal entry point.

use clap::{Parser, Subcommand};

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
}

#[derive(Subcommand)]
pub enum DaemonAction {
    Start,
    Stop,
    Restart,
    Logs {
        #[arg(short, long)]
        follow: bool,
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
