//! The same contract as `job.rs` for the systems where only the tests run (the Mac and Linux).
//! The released command is Windows only; this lets the logic be tried where Windows is not.

use std::ffi::OsString;
use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;
use std::time::Instant;

use super::{RunError, RunLimits, ToolRun};
use crate::cancel::CancelToken;

pub(super) fn run(
    program: &Path,
    arguments: &[OsString],
    limits: RunLimits,
    cancel: &CancelToken,
) -> Result<ToolRun, RunError> {
    let mut child = Command::new(program)
        .args(arguments)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|_error: std::io::Error| -> RunError { RunError::CouldNotStart })?;
    let stdout = child.stdout.take().ok_or(RunError::CouldNotStart)?;
    let stderr = child.stderr.take().ok_or(RunError::CouldNotStart)?;
    let max: usize = limits.max_stdout;
    let out_reader = thread::spawn(move || -> (Vec<u8>, bool) { drain(stdout, max) });
    let err_reader = thread::spawn(move || -> (Vec<u8>, bool) { drain(stderr, 0) });

    let started: Instant = Instant::now();
    let mut failure: Option<RunError> = None;
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) => {}
            Err(_) => {
                failure = Some(RunError::CouldNotStart);
                break;
            }
        }
        if cancel.is_requested() {
            failure = Some(RunError::Cancelled);
        } else if started.elapsed() > limits.timeout {
            failure = Some(RunError::TimedOut);
        }
        if failure.is_some() {
            let _ = child.kill();
            break;
        }
        thread::sleep(std::time::Duration::from_millis(5));
    }
    let status = child
        .wait()
        .map_err(|_error: std::io::Error| -> RunError { RunError::CouldNotStart })?;
    let (stdout, too_much): (Vec<u8>, bool) = out_reader.join().unwrap_or((Vec::new(), false));
    let _ = err_reader.join();
    if let Some(error) = failure {
        return Err(error);
    }
    if too_much {
        return Err(RunError::TooMuchOutput);
    }
    Ok(ToolRun {
        exit_code: status.code().unwrap_or(-1),
        stdout,
    })
}

/// Reads a pipe to its end, keeping at most `keep` bytes. The flag says the pipe held more.
fn drain<R: Read>(mut pipe: R, keep: usize) -> (Vec<u8>, bool) {
    let mut kept: Vec<u8> = Vec::new();
    let mut chunk: [u8; 65536] = [0; 65536];
    let mut overflow: bool = false;
    loop {
        match pipe.read(&mut chunk) {
            Ok(0) | Err(_) => return (kept, overflow),
            Ok(count) => {
                let room: usize = keep.saturating_sub(kept.len());
                kept.extend_from_slice(&chunk[..count.min(room)]);
                if count > room {
                    overflow = true;
                }
            }
        }
    }
}
