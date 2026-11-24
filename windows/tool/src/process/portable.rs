//! The same contract as `job.rs` for the systems where only the tests run (the Mac and Linux).
//! The released command is Windows only; this lets the logic be tried where Windows is not.

use std::ffi::OsString;
use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::thread;
use std::time::Instant;

use super::{keep_tail, tail_of, OutputSink, RunError, RunLimits, ToolRun, STDERR_TAIL};
use crate::cancel::CancelToken;

pub(super) fn run(
    program: &Path,
    arguments: &[OsString],
    limits: RunLimits,
    cancel: &CancelToken,
    mut on_output: Option<OutputSink<'_>>,
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
    let (chunks, arrivals): (Sender<Vec<u8>>, Receiver<Vec<u8>>) = channel();
    let forward: Option<Sender<Vec<u8>>> = on_output
        .as_ref()
        .map(|_sink| -> Sender<Vec<u8>> { chunks.clone() });
    drop(chunks);
    let out_reader = thread::spawn(move || -> (Vec<u8>, bool) { drain(stdout, max, forward) });
    let err_reader = thread::spawn(move || -> Vec<u8> { drain_tail(stderr) });

    let started: Instant = Instant::now();
    let mut failure: Option<RunError> = None;
    loop {
        deliver(&arrivals, &mut on_output);
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
    let stderr_tail: Vec<u8> = err_reader.join().unwrap_or_default();
    deliver(&arrivals, &mut on_output);
    if let Some(error) = failure {
        return Err(error);
    }
    if too_much {
        return Err(RunError::TooMuchOutput);
    }
    Ok(ToolRun {
        exit_code: status.code().unwrap_or(-1),
        stdout,
        stderr_tail,
    })
}

/// Hands everything that has arrived from the child's standard output to the caller's sink.
fn deliver(arrivals: &Receiver<Vec<u8>>, sink: &mut Option<OutputSink<'_>>) -> () {
    while let Ok(chunk) = arrivals.try_recv() {
        if let Some(sink) = sink.as_mut() {
            sink(&chunk);
        }
    }
}

/// Reads a pipe to its end, keeping at most `keep` bytes. The flag says the pipe held more. Every
/// chunk is also sent on `forward`, when there is one.
fn drain<R: Read>(mut pipe: R, keep: usize, forward: Option<Sender<Vec<u8>>>) -> (Vec<u8>, bool) {
    let mut kept: Vec<u8> = Vec::new();
    let mut chunk: [u8; 65536] = [0; 65536];
    let mut overflow: bool = false;
    loop {
        match pipe.read(&mut chunk) {
            Ok(0) | Err(_) => return (kept, overflow),
            Ok(count) => {
                if let Some(sender) = &forward {
                    let _ = sender.send(chunk[..count].to_vec());
                }
                let room: usize = keep.saturating_sub(kept.len());
                kept.extend_from_slice(&chunk[..count.min(room)]);
                if count > room {
                    overflow = true;
                }
            }
        }
    }
}

/// Reads a pipe to its end, keeping only the last bytes.
fn drain_tail<R: Read>(mut pipe: R) -> Vec<u8> {
    let mut kept: Vec<u8> = Vec::new();
    let mut chunk: [u8; 16384] = [0; 16384];
    loop {
        match pipe.read(&mut chunk) {
            Ok(0) | Err(_) => return tail_of(kept, STDERR_TAIL),
            Ok(count) => keep_tail(&mut kept, &chunk[..count], STDERR_TAIL),
        }
    }
}
