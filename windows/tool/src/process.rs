//! Running FFmpeg and FFprobe (SPEC sections 26.1 and 26.3).
//!
//! Both programs are children of this one, started by absolute path from this program's own
//! folder. On Windows each runs in a job object that kills it when this program ends for any
//! reason; see `process/job.rs`.

use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::time::Duration;

use crate::cancel::CancelToken;

#[cfg(windows)]
mod job;
#[cfg(not(windows))]
mod portable;

/// The two helper programs, found only beside this program (never through PATH or the current
/// folder).
#[derive(Clone, Debug)]
pub struct Tools {
    pub ffmpeg: PathBuf,
    pub ffprobe: PathBuf,
}

impl Tools {
    /// Looks in the folder that holds this program. `None` when either helper is missing.
    pub fn beside_executable() -> Option<Tools> {
        let executable: PathBuf = std::env::current_exe().ok()?;
        Tools::in_folder(executable.parent()?)
    }

    pub fn in_folder(folder: &Path) -> Option<Tools> {
        let suffix: &str = if cfg!(windows) { ".exe" } else { "" };
        let ffmpeg: PathBuf = folder.join(format!("ffmpeg{suffix}"));
        let ffprobe: PathBuf = folder.join(format!("ffprobe{suffix}"));
        if ffmpeg.is_file() && ffprobe.is_file() {
            Some(Tools { ffmpeg, ffprobe })
        } else {
            None
        }
    }
}

/// How long a child may run and how much of its standard output is kept.
#[derive(Clone, Copy, Debug)]
pub struct RunLimits {
    pub timeout: Duration,
    pub max_stdout: usize,
}

/// What a child that ran to the end left behind.
#[derive(Debug)]
pub struct ToolRun {
    pub exit_code: i32,
    pub stdout: Vec<u8>,
}

/// Why a child did not run to the end.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RunError {
    /// The program could not be started.
    CouldNotStart,
    /// A cancel arrived and the child was stopped.
    Cancelled,
    /// The child ran past its time limit and was stopped.
    TimedOut,
    /// The child wrote more to standard output than the limit allows and was stopped.
    TooMuchOutput,
}

/// Runs a program with the given arguments and no standard input, waits for it and returns its
/// exit code and standard output. Its standard error is read and thrown away: it can name files.
pub fn run_tool(
    program: &Path,
    arguments: &[OsString],
    limits: RunLimits,
    cancel: &CancelToken,
) -> Result<ToolRun, RunError> {
    #[cfg(windows)]
    {
        job::run(program, arguments, limits, cancel)
    }
    #[cfg(not(windows))]
    {
        portable::run(program, arguments, limits, cancel)
    }
}
