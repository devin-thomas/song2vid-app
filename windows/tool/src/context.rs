//! What a run of the command may look at besides its arguments: the helper programs beside it and
//! the few environment variables it reads.

use std::sync::Arc;

use crate::console::{StandardStreams, Streams};
use crate::process::Tools;

/// The environment variables the command reads. Nothing else in the environment is ever looked at,
/// and no value from it reaches the output.
#[derive(Clone, Debug, Default)]
pub struct Environment {
    /// `SONG2VID_UPDATE_URL`: where `--update` looks, for tests. Only a file or this computer
    /// (localhost) is accepted, so it can't send the request anywhere else.
    pub update_url: Option<String>,
    /// `SONG2VID_TEST_ENCODER` (`nvenc`, `media_foundation` or `software`): forces one Encoder,
    /// for tests only (SPEC section 26.3).
    pub test_encoder: Option<String>,
    /// `NO_COLOR` is set to something: the live line has no colour (SPEC section 14.5).
    pub no_color: bool,
    /// `TERM` is `dumb`: the live line has no colour and no line-clearing sequence.
    pub dumb_terminal: bool,
}

impl Environment {
    /// Reads the variables from the process.
    pub fn from_process() -> Environment {
        Environment {
            update_url: std::env::var("SONG2VID_UPDATE_URL").ok(),
            test_encoder: std::env::var("SONG2VID_TEST_ENCODER").ok(),
            no_color: std::env::var_os("NO_COLOR")
                .is_some_and(|value: std::ffi::OsString| -> bool { !value.is_empty() }),
            dumb_terminal: std::env::var("TERM")
                .is_ok_and(|value: String| -> bool { value == "dumb" }),
        }
    }
}

/// The helpers and environment for one run.
#[derive(Clone)]
pub struct Context {
    pub environment: Environment,
    tools: Option<Tools>,
    streams: Arc<dyn Streams>,
}

impl std::fmt::Debug for Context {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("Context")
            .field("environment", &self.environment)
            .field("tools", &self.tools)
            .finish_non_exhaustive()
    }
}

impl Context {
    /// A context that writes to the process's own standard output and standard error.
    pub fn new(environment: Environment, tools: Option<Tools>) -> Context {
        Context::with_streams(environment, tools, Arc::new(StandardStreams::new()))
    }

    pub fn with_streams(
        environment: Environment,
        tools: Option<Tools>,
        streams: Arc<dyn Streams>,
    ) -> Context {
        Context {
            environment,
            tools,
            streams,
        }
    }

    /// FFmpeg and FFprobe, when they are beside this program.
    pub fn tools(&self) -> Option<&Tools> {
        self.tools.as_ref()
    }

    /// Where progress is written while a command runs.
    pub fn streams(&self) -> Arc<dyn Streams> {
        Arc::clone(&self.streams)
    }
}
