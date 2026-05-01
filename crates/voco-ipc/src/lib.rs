//! Voco IPC: typed messages + Unix-socket server/client for daemon control.

pub mod codec;
pub mod protocol;

pub use protocol::*;
