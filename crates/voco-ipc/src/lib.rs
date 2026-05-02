//! Voco IPC: typed messages + Unix-socket server/client for daemon control.

#[cfg(feature = "client")]
pub mod client;
pub mod codec;
pub mod protocol;
#[cfg(feature = "server")]
pub mod server;

pub use protocol::*;
