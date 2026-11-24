//! The Song2Vid command for Windows (SPEC sections 14, 24 and 26).
//!
//! `main.rs` only passes the arguments to `run` and writes what comes back. Everything the command
//! decides lives here.

pub mod cancel;
pub mod check;
pub mod context;
pub mod destination;
pub mod error;
pub mod frame;
pub mod heif;
pub mod help;
pub mod http;
pub mod inputs;
pub mod json;
pub mod make_options;
pub mod media;
pub mod options;
pub mod orientation;
pub mod preview;
pub mod process;
pub mod report;
pub mod run;
pub mod skill;
pub mod update;

/// The version of the command (SPEC section 24.7).
pub const VERSION: &str = "1.2.0";
/// Where the project lives, printed by `--repo`.
pub const REPOSITORY_URL: &str = "https://github.com/devin-thomas/song2vid-app";

pub use context::{Context, Environment};
pub use options::Argument;
pub use run::run;
