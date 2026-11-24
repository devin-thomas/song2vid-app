//! Cancelling a run (SPEC sections 14.4 and 24.4): Ctrl-C and Ctrl-Break in a console, and with
//! `--cancel-on-eof` end-of-file or a `cancel` line on standard input.
//!
//! The default action for Ctrl-C ends the process on the spot, which would leave a half-made file
//! behind. Here the signal only sets a flag; the running command notices it, stops its children,
//! removes its temporary file and reports `cancelled`.

use std::io::Read;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, OnceLock};
use std::thread;
use std::time::Duration;

/// How long a start waits to learn whether standard input is already closed.
const FIRST_READ_PATIENCE: Duration = Duration::from_millis(50);

/// A cancellation request that any thread can read and any signal source can set.
#[derive(Clone, Debug)]
pub struct CancelToken {
    requested: Arc<AtomicBool>,
}

impl CancelToken {
    pub fn new() -> CancelToken {
        CancelToken {
            requested: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn request(&self) -> () {
        self.requested.store(true, Ordering::SeqCst);
    }

    pub fn is_requested(&self) -> bool {
        self.requested.load(Ordering::SeqCst)
    }
}

impl Default for CancelToken {
    fn default() -> CancelToken {
        CancelToken::new()
    }
}

/// The token the console control handler sets. A handler is a bare function with no way to carry
/// state, so the one token for this process waits here.
static CONSOLE_TARGET: OnceLock<CancelToken> = OnceLock::new();

/// Watches for the signals that cancel a run, for as long as it is alive.
pub struct CancelSignals {
    token: CancelToken,
}

impl CancelSignals {
    /// Starts watching. `watch_stdin` is true with `--cancel-on-eof`; without it the command never
    /// reads standard input.
    pub fn start(watch_stdin: bool) -> CancelSignals {
        let token: CancelToken = CancelToken::new();
        let _ = CONSOLE_TARGET.set(token.clone());
        install_console_handler();
        if watch_stdin {
            let watcher: CancelToken = token.clone();
            let (first_read, first_read_done): (Sender<()>, Receiver<()>) = channel();
            // The thread ends with the process: standard input has no way to be interrupted.
            let started = thread::Builder::new()
                .name(String::from("song2vid-stdin"))
                .spawn(move || -> () { watch_standard_input(&watcher, &first_read) });
            if started.is_ok() {
                // A closed standard input answers at once. Waiting a moment for the first answer makes
                // a command started with its input already closed cancel before it does any work.
                let _ = first_read_done.recv_timeout(FIRST_READ_PATIENCE);
            }
        }
        CancelSignals { token }
    }

    pub fn token(&self) -> CancelToken {
        self.token.clone()
    }

    pub fn is_requested(&self) -> bool {
        self.token.is_requested()
    }
}

/// Requests cancel at end-of-file, or when a line holds only `cancel` (a CR before the newline is
/// allowed). Keeps at most `cancel` plus a CR of any line, so a long line costs nothing.
fn watch_standard_input(token: &CancelToken, first_read: &Sender<()>) -> () {
    const COMMAND: &[u8] = b"cancel";
    let mut input = std::io::stdin().lock();
    let mut chunk: [u8; 4096] = [0; 4096];
    let mut line: Vec<u8> = Vec::new();
    let mut discarding: bool = false;
    let mut told_first: bool = false;
    loop {
        let answer: std::io::Result<usize> = input.read(&mut chunk);
        // End of file, or input that can't be read, is a cancel. It is set before the starter is
        // told, so a starter that was waiting sees it.
        let ended: bool = match &answer {
            Ok(0) => true,
            Ok(_) => false,
            Err(error) => error.kind() != std::io::ErrorKind::Interrupted,
        };
        if ended {
            token.request();
        }
        if !told_first {
            told_first = true;
            let _ = first_read.send(());
        }
        let count: usize = match answer {
            Ok(0) => return,
            Ok(count) => count,
            Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => return,
        };
        for byte in &chunk[..count] {
            if *byte == b'\n' {
                let is_cancel: bool = line == COMMAND || line == [COMMAND, b"\r"].concat();
                if !discarding && is_cancel {
                    token.request();
                    return;
                }
                line.clear();
                discarding = false;
            } else if line.len() < COMMAND.len() + 1 {
                line.push(*byte);
            } else {
                discarding = true;
            }
        }
    }
}

#[cfg(windows)]
#[allow(unsafe_code)]
fn install_console_handler() -> () {
    use windows_sys::core::BOOL;
    use windows_sys::Win32::System::Console::SetConsoleCtrlHandler;

    unsafe extern "system" fn handler(_control_type: u32) -> BOOL {
        // Ctrl-C, Ctrl-Break, closing the console, logoff and shutdown all cancel the run.
        match CONSOLE_TARGET.get() {
            Some(token) => {
                token.request();
                1
            }
            None => 0,
        }
    }

    // SAFETY: `handler` has the signature SetConsoleCtrlHandler requires, lives for the whole
    // process, and only reads a OnceLock and sets an atomic, which is safe on any thread.
    let _ = unsafe { SetConsoleCtrlHandler(Some(handler), 1) };
}

#[cfg(not(windows))]
fn install_console_handler() -> () {}
