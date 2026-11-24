//! What a run of the command may look at besides its arguments: the helper programs beside it and
//! the few environment variables it reads.

use crate::process::Tools;

/// The environment variables the command reads. Nothing else in the environment is ever looked at,
/// and no value from it reaches the output.
#[derive(Clone, Debug, Default)]
pub struct Environment {
    /// `SONG2VID_UPDATE_URL`: where `--update` looks, for tests. Only a file or this computer
    /// (localhost) is accepted, so it can't send the request anywhere else.
    pub update_url: Option<String>,
}

impl Environment {
    /// Reads the variables from the process.
    pub fn from_process() -> Environment {
        Environment {
            update_url: std::env::var("SONG2VID_UPDATE_URL").ok(),
        }
    }
}

/// The helpers and environment for one run.
#[derive(Clone, Debug)]
pub struct Context {
    pub environment: Environment,
    tools: Option<Tools>,
}

impl Context {
    pub fn new(environment: Environment, tools: Option<Tools>) -> Context {
        Context { environment, tools }
    }

    /// FFmpeg and FFprobe, when they are beside this program.
    pub fn tools(&self) -> Option<&Tools> {
        self.tools.as_ref()
    }
}
