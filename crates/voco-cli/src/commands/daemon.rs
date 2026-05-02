use crate::DaemonAction;
use anyhow::Result;

pub fn run(_action: DaemonAction) -> Result<()> {
    eprintln!("voco daemon: not yet implemented (Task 12 fills this in)");
    std::process::exit(1);
}
