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

/// Where a child's standard output is passed while it runs.
pub type OutputSink<'a> = &'a mut dyn FnMut(&[u8]);

/// How much of the end of a child's standard error is kept, to tell why it failed. It is never
/// printed: it can name files.
pub const STDERR_TAIL: usize = 4096;

/// What a child that ran to the end left behind.
#[derive(Debug)]
pub struct ToolRun {
    pub exit_code: i32,
    pub stdout: Vec<u8>,
    /// The last bytes of standard error, for the command's own use (never shown).
    pub stderr_tail: Vec<u8>,
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
/// exit code and standard output. Its standard error is read and only its tail is kept: it can
/// name files.
pub fn run_tool(
    program: &Path,
    arguments: &[OsString],
    limits: RunLimits,
    cancel: &CancelToken,
) -> Result<ToolRun, RunError> {
    run_tool_streaming(program, arguments, limits, cancel, None)
}

/// Like `run_tool`, and every chunk the child writes to standard output is also handed to
/// `on_output` while it runs, on the calling thread, at least every 20 milliseconds. FFmpeg's
/// `-progress` output reaches the command this way.
pub fn run_tool_streaming(
    program: &Path,
    arguments: &[OsString],
    limits: RunLimits,
    cancel: &CancelToken,
    on_output: Option<OutputSink<'_>>,
) -> Result<ToolRun, RunError> {
    #[cfg(windows)]
    {
        job::run(program, arguments, limits, cancel, on_output)
    }
    #[cfg(not(windows))]
    {
        portable::run(program, arguments, limits, cancel, on_output)
    }
}

/// Appends `chunk` to a buffer that keeps only its last `keep` bytes.
fn keep_tail(kept: &mut Vec<u8>, chunk: &[u8], keep: usize) -> () {
    kept.extend_from_slice(chunk);
    if kept.len() > keep * 2 {
        let drop: usize = kept.len() - keep;
        kept.drain(..drop);
    }
}

/// The last `keep` bytes of a buffer filled by `keep_tail`.
fn tail_of(mut kept: Vec<u8>, keep: usize) -> Vec<u8> {
    if kept.len() > keep {
        let drop: usize = kept.len() - keep;
        kept.drain(..drop);
    }
    kept
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::time::Instant;

    fn limits() -> RunLimits {
        RunLimits {
            timeout: Duration::from_secs(10),
            max_stdout: 1024,
        }
    }

    #[test]
    fn standard_output_is_handed_on_while_the_child_runs() -> () {
        let arguments: Vec<OsString> = ["-c", "echo first; sleep 0.4; echo second"]
            .iter()
            .map(|word: &&str| -> OsString { OsString::from(*word) })
            .collect();
        let started: Instant = Instant::now();
        let mut arrivals: Vec<(String, f64)> = Vec::new();
        let mut sink = |bytes: &[u8]| -> () {
            arrivals.push((
                String::from_utf8_lossy(bytes).into_owned(),
                started.elapsed().as_secs_f64(),
            ));
        };
        let run: ToolRun = run_tool_streaming(
            Path::new("/bin/sh"),
            &arguments,
            limits(),
            &CancelToken::new(),
            Some(&mut sink),
        )
        .expect("the shell runs");
        assert_eq!(run.exit_code, 0);
        assert_eq!(String::from_utf8_lossy(&run.stdout), "first\nsecond\n");
        let joined: String = arrivals
            .iter()
            .map(|(text, _when): &(String, f64)| -> String { text.clone() })
            .collect();
        assert_eq!(joined, "first\nsecond\n");
        // The first line arrived well before the child ended.
        assert!(arrivals[0].1 < 0.3, "{arrivals:?}");
    }

    #[test]
    fn the_tail_of_standard_error_is_kept_and_never_the_whole() -> () {
        let arguments: Vec<OsString> = [
            "-c",
            "head -c 20000 /dev/zero | tr '\\0' x >&2; echo end >&2",
        ]
        .iter()
        .map(|word: &&str| -> OsString { OsString::from(*word) })
        .collect();
        let run: ToolRun = run_tool(
            Path::new("/bin/sh"),
            &arguments,
            limits(),
            &CancelToken::new(),
        )
        .expect("the shell runs");
        assert!(run.stderr_tail.len() <= STDERR_TAIL);
        assert!(String::from_utf8_lossy(&run.stderr_tail).ends_with("xend\n"));
    }

    #[test]
    fn a_cancel_stops_the_child() -> () {
        let arguments: Vec<OsString> = ["-c", "sleep 30"]
            .iter()
            .map(|word: &&str| -> OsString { OsString::from(*word) })
            .collect();
        let token: CancelToken = CancelToken::new();
        let asker: CancelToken = token.clone();
        std::thread::spawn(move || -> () {
            std::thread::sleep(Duration::from_millis(100));
            asker.request();
        });
        let started: Instant = Instant::now();
        let outcome = run_tool(Path::new("/bin/sh"), &arguments, limits(), &token);
        assert_eq!(outcome.unwrap_err(), RunError::Cancelled);
        assert!(started.elapsed() < Duration::from_secs(5));
    }
}
