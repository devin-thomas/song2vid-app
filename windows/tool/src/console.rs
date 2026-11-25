//! The command's own copies of standard output and standard error, and what the display needs to
//! know about the terminal (SPEC sections 14.5 and 26.3).
//!
//! Progress is written through `Streams`, so a test can collect it and the live line can wait for
//! virtual terminal sequences to be turned on. Where they cannot be turned on, the display falls
//! back to the plain lines of headless mode.

use std::io::{IsTerminal, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;

/// Where the command writes while it runs.
pub trait Streams: Send + Sync {
    /// Text for standard output.
    fn write_output(&self, text: &str) -> ();
    /// Text for standard error.
    fn write_error(&self, text: &str) -> ();
    /// The width of the terminal on standard error when it is a terminal that shows escape
    /// sequences, which is when a live line can be drawn. `None` otherwise.
    fn live_columns(&self) -> Option<usize>;
}

/// The process's real standard output and standard error.
pub struct StandardStreams {
    live: OnceLock<bool>,
    changed_mode: AtomicBool,
}

impl StandardStreams {
    pub fn new() -> StandardStreams {
        StandardStreams {
            live: OnceLock::new(),
            changed_mode: AtomicBool::new(false),
        }
    }

    /// True when standard error is a terminal and escape sequences work in it. Turning them on is
    /// done once, the first time the display asks.
    fn is_live(&self) -> bool {
        *self.live.get_or_init(|| -> bool {
            if !std::io::stderr().is_terminal() {
                return false;
            }
            match platform::enable_virtual_terminal() {
                platform::Enabled::AlreadyOn => true,
                platform::Enabled::TurnedOn => {
                    self.changed_mode.store(true, Ordering::SeqCst);
                    true
                }
                platform::Enabled::Unavailable => false,
            }
        })
    }
}

impl Default for StandardStreams {
    fn default() -> StandardStreams {
        StandardStreams::new()
    }
}

impl Drop for StandardStreams {
    /// The console is left as it was found.
    fn drop(&mut self) -> () {
        if self.changed_mode.load(Ordering::SeqCst) {
            platform::restore_mode();
        }
    }
}

impl Streams for StandardStreams {
    fn write_output(&self, text: &str) -> () {
        let mut out = std::io::stdout().lock();
        // A closed pipe is not an error worth a message: the reader has what it wanted.
        let _ = out.write_all(text.as_bytes());
        let _ = out.flush();
    }

    fn write_error(&self, text: &str) -> () {
        let mut err = std::io::stderr().lock();
        let _ = err.write_all(text.as_bytes());
        let _ = err.flush();
    }

    fn live_columns(&self) -> Option<usize> {
        if self.is_live() {
            Some(platform::columns())
        } else {
            None
        }
    }
}

#[cfg(windows)]
#[allow(unsafe_code)]
mod platform {
    use std::sync::atomic::{AtomicU32, Ordering};

    use windows_sys::Win32::Foundation::{FALSE, INVALID_HANDLE_VALUE};
    use windows_sys::Win32::System::Console::{
        GetConsoleMode, GetConsoleScreenBufferInfo, GetStdHandle, SetConsoleMode,
        CONSOLE_SCREEN_BUFFER_INFO, ENABLE_VIRTUAL_TERMINAL_PROCESSING, STD_ERROR_HANDLE,
    };

    /// The console mode of standard error before this program changed it.
    static ORIGINAL_MODE: AtomicU32 = AtomicU32::new(0);

    pub(super) enum Enabled {
        AlreadyOn,
        TurnedOn,
        Unavailable,
    }

    pub(super) fn enable_virtual_terminal() -> Enabled {
        // SAFETY: asks for a standard handle; the result is checked before use.
        let handle = unsafe { GetStdHandle(STD_ERROR_HANDLE) };
        if handle.is_null() || handle == INVALID_HANDLE_VALUE {
            return Enabled::Unavailable;
        }
        let mut mode: u32 = 0;
        // SAFETY: `handle` is a standard handle and `mode` is writable.
        if unsafe { GetConsoleMode(handle, &mut mode) } == FALSE {
            return Enabled::Unavailable;
        }
        if mode & ENABLE_VIRTUAL_TERMINAL_PROCESSING != 0 {
            return Enabled::AlreadyOn;
        }
        // SAFETY: `handle` is a console handle; the mode is the old one plus one flag.
        if unsafe { SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING) } == FALSE {
            return Enabled::Unavailable;
        }
        ORIGINAL_MODE.store(mode, Ordering::SeqCst);
        Enabled::TurnedOn
    }

    pub(super) fn restore_mode() -> () {
        // SAFETY: as in `enable_virtual_terminal`; restoring the mode that was read there.
        let handle = unsafe { GetStdHandle(STD_ERROR_HANDLE) };
        if handle.is_null() || handle == INVALID_HANDLE_VALUE {
            return;
        }
        // SAFETY: `handle` is a console handle and the mode is the one it had.
        let _ = unsafe { SetConsoleMode(handle, ORIGINAL_MODE.load(Ordering::SeqCst)) };
    }

    /// The visible width of the console window, or 80 when it can't be read.
    pub(super) fn columns() -> usize {
        // SAFETY: asks for a standard handle; the result is checked before use.
        let handle = unsafe { GetStdHandle(STD_ERROR_HANDLE) };
        if handle.is_null() || handle == INVALID_HANDLE_VALUE {
            return 80;
        }
        // SAFETY: an all-zero CONSOLE_SCREEN_BUFFER_INFO is valid; the call fills it.
        let mut info: CONSOLE_SCREEN_BUFFER_INFO = unsafe { std::mem::zeroed() };
        // SAFETY: `handle` is a console handle and `info` is writable.
        if unsafe { GetConsoleScreenBufferInfo(handle, &mut info) } == FALSE {
            return 80;
        }
        let width: i32 = i32::from(info.srWindow.Right) - i32::from(info.srWindow.Left) + 1;
        usize::try_from(width)
            .ok()
            .filter(|width: &usize| -> bool { *width > 0 })
            .unwrap_or(80)
    }
}

#[cfg(not(windows))]
mod platform {
    pub(super) enum Enabled {
        AlreadyOn,
        #[allow(dead_code)]
        TurnedOn,
        #[allow(dead_code)]
        Unavailable,
    }

    pub(super) fn enable_virtual_terminal() -> Enabled {
        Enabled::AlreadyOn
    }

    pub(super) fn restore_mode() -> () {}

    pub(super) fn columns() -> usize {
        80
    }
}
