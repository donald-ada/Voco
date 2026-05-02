//! Voco configuration: schema, IO, validation.
//!
//! Three layers (added incrementally over Tasks 3-5):
//! * `schema` — pure data types
//! * `io`     — load/save with atomic writes
//! * `validate` — semantic checks before applying

pub mod io;
pub mod schema;
pub mod validate;

pub use io::{ConfigError, ConfigIo};
pub use schema::*;
pub use validate::{ValidationError, ValidationKind};
