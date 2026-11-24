//! Children in a kill-on-close job object (SPEC section 26.3, ADR-029).
//!
//! Every FFmpeg or FFprobe child is created suspended, put in a job object whose kill-on-close
//! flag is set, and resumed only once it is inside the job. It gets `CREATE_NO_WINDOW` and a handle
//! list of exactly its three standard handles (NUL for input, one pipe each for output and
//! errors), so it inherits nothing else. If this program is killed, Windows closes the job's last
//! handle, and every child dies with it.
//!
//! The Win32 calls are the one place this crate uses `unsafe`. Each block says what it relies on.

#![allow(unsafe_code)]

use std::ffi::{c_void, OsStr, OsString};
use std::fs::File;
use std::io::Read;
use std::mem;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::io::{FromRawHandle, RawHandle};
use std::path::Path;
use std::ptr;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::thread;
use std::time::Instant;

use windows_sys::Win32::Foundation::{
    CloseHandle, SetHandleInformation, FALSE, HANDLE, HANDLE_FLAG_INHERIT, INVALID_HANDLE_VALUE,
    TRUE, WAIT_OBJECT_0,
};
use windows_sys::Win32::Security::SECURITY_ATTRIBUTES;
use windows_sys::Win32::Storage::FileSystem::{
    CreateFileW, FILE_ATTRIBUTE_NORMAL, FILE_GENERIC_READ, FILE_SHARE_READ, FILE_SHARE_WRITE,
    OPEN_EXISTING,
};
use windows_sys::Win32::System::JobObjects::{
    AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
    SetInformationJobObject, TerminateJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
};
use windows_sys::Win32::System::Pipes::CreatePipe;
use windows_sys::Win32::System::Threading::{
    CreateProcessW, DeleteProcThreadAttributeList, GetExitCodeProcess,
    InitializeProcThreadAttributeList, ResumeThread, TerminateProcess, UpdateProcThreadAttribute,
    WaitForSingleObject, CREATE_NO_WINDOW, CREATE_SUSPENDED, EXTENDED_STARTUPINFO_PRESENT,
    LPPROC_THREAD_ATTRIBUTE_LIST, PROCESS_INFORMATION, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
    STARTF_USESTDHANDLES, STARTUPINFOEXW,
};

use super::{keep_tail, tail_of, OutputSink, RunError, RunLimits, ToolRun, STDERR_TAIL};
use crate::cancel::CancelToken;

/// How often a running child is checked for cancel and time.
const WAIT_SLICE_MILLISECONDS: u32 = 20;

/// A handle that is closed when it goes out of scope.
struct Handle(HANDLE);

impl Handle {
    fn is_valid(&self) -> bool {
        !self.0.is_null() && self.0 != INVALID_HANDLE_VALUE
    }
}

impl Drop for Handle {
    fn drop(&mut self) -> () {
        if self.is_valid() {
            // SAFETY: the handle was opened by this program, is not used after this, and is
            // closed exactly once here.
            let _ = unsafe { CloseHandle(self.0) };
        }
    }
}

/// The attribute list that limits what the child inherits. Freed when it goes out of scope.
struct AttributeList {
    /// Eight-byte units, so the list is aligned as the API requires.
    storage: Vec<u64>,
}

impl AttributeList {
    fn pointer(&mut self) -> LPPROC_THREAD_ATTRIBUTE_LIST {
        self.storage.as_mut_ptr().cast::<c_void>()
    }
}

impl Drop for AttributeList {
    fn drop(&mut self) -> () {
        // SAFETY: the list was initialised by `handle_list_attribute` and is deleted once.
        unsafe { DeleteProcThreadAttributeList(self.pointer()) };
    }
}

/// A pipe's read end and the write end the child gets.
struct Pipe {
    read: File,
    write: Handle,
}

/// Runs the program as a child in its own job and returns its exit code and standard output.
/// With `on_output`, each chunk of standard output is also passed to it while the child runs.
pub(super) fn run(
    program: &Path,
    arguments: &[OsString],
    limits: RunLimits,
    cancel: &CancelToken,
    mut on_output: Option<OutputSink<'_>>,
) -> Result<ToolRun, RunError> {
    let job: Handle = create_job()?;
    let input: Handle = open_nul()?;
    let output: Pipe = create_pipe()?;
    let errors: Pipe = create_pipe()?;
    let child: PROCESS_INFORMATION = start_suspended(program, arguments, &input, &output, &errors)?;
    let process: Handle = Handle(child.hProcess);
    let thread_handle: Handle = Handle(child.hThread);

    // SAFETY: both handles are valid: the job from `create_job`, the process from `CreateProcessW`.
    if unsafe { AssignProcessToJobObject(job.0, process.0) } == FALSE {
        // The child never ran, so ending it leaves nothing behind.
        // SAFETY: the process handle is valid and has the terminate right.
        let _ = unsafe { TerminateProcess(process.0, 1) };
        return Err(RunError::CouldNotStart);
    }
    // SAFETY: the thread handle is the suspended main thread returned by `CreateProcessW`.
    if unsafe { ResumeThread(thread_handle.0) } == u32::MAX {
        // SAFETY: the job is valid; closing it also ends the child.
        let _ = unsafe { TerminateJobObject(job.0, 1) };
        return Err(RunError::CouldNotStart);
    }
    drop(thread_handle);
    // The child has its own copies of these. Keeping ours would stop the pipes from ever ending.
    drop(input);
    let Pipe {
        read: output_read,
        write: output_write,
    } = output;
    let Pipe {
        read: errors_read,
        write: errors_write,
    } = errors;
    drop(output_write);
    drop(errors_write);

    let keep: usize = limits.max_stdout;
    let (chunks, arrivals): (Sender<Vec<u8>>, Receiver<Vec<u8>>) = channel();
    let forward: Option<Sender<Vec<u8>>> = on_output
        .as_ref()
        .map(|_sink| -> Sender<Vec<u8>> { chunks.clone() });
    drop(chunks);
    let out_reader =
        thread::spawn(move || -> (Vec<u8>, bool) { drain(output_read, keep, forward) });
    let err_reader = thread::spawn(move || -> Vec<u8> { drain_tail(errors_read) });

    let started: Instant = Instant::now();
    let mut failure: Option<RunError> = None;
    loop {
        // SAFETY: the process handle is valid for the whole loop.
        let waited: u32 = unsafe { WaitForSingleObject(process.0, WAIT_SLICE_MILLISECONDS) };
        deliver(&arrivals, &mut on_output);
        if waited == WAIT_OBJECT_0 {
            break;
        }
        if cancel.is_requested() {
            failure = Some(RunError::Cancelled);
        } else if started.elapsed() > limits.timeout {
            failure = Some(RunError::TimedOut);
        }
        if failure.is_some() {
            // SAFETY: the job is valid; this ends the child and anything it started.
            let _ = unsafe { TerminateJobObject(job.0, 1) };
            // SAFETY: the process handle is valid. Ending the job ends the process promptly.
            let _ = unsafe { WaitForSingleObject(process.0, 5000) };
            break;
        }
    }

    let mut code: u32 = 1;
    // SAFETY: the process handle is valid and `code` is a writable u32.
    let _ = unsafe { GetExitCodeProcess(process.0, &mut code) };
    let (stdout, too_much): (Vec<u8>, bool) = out_reader.join().unwrap_or((Vec::new(), false));
    let stderr_tail: Vec<u8> = err_reader.join().unwrap_or_default();
    deliver(&arrivals, &mut on_output);
    // The job closes here, ending anything still in it.
    drop(job);
    if let Some(error) = failure {
        return Err(error);
    }
    if too_much {
        return Err(RunError::TooMuchOutput);
    }
    Ok(ToolRun {
        exit_code: i32::from_ne_bytes(code.to_ne_bytes()),
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

fn create_job() -> Result<Handle, RunError> {
    // SAFETY: null attributes and name are allowed; the result is checked below.
    let job: Handle = Handle(unsafe { CreateJobObjectW(ptr::null(), ptr::null()) });
    if !job.is_valid() {
        return Err(RunError::CouldNotStart);
    }
    // SAFETY: an all-zero JOBOBJECT_EXTENDED_LIMIT_INFORMATION is a valid value (no limits).
    let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = unsafe { mem::zeroed() };
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    let size: u32 = u32::try_from(mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>())
        .map_err(|_error: std::num::TryFromIntError| -> RunError { RunError::CouldNotStart })?;
    // SAFETY: `limits` is a valid structure of the size given, for the class named.
    let set: i32 = unsafe {
        SetInformationJobObject(
            job.0,
            JobObjectExtendedLimitInformation,
            ptr::from_ref(&limits).cast::<c_void>(),
            size,
        )
    };
    if set == FALSE {
        return Err(RunError::CouldNotStart);
    }
    Ok(job)
}

fn inheritable() -> SECURITY_ATTRIBUTES {
    SECURITY_ATTRIBUTES {
        nLength: u32::try_from(mem::size_of::<SECURITY_ATTRIBUTES>()).unwrap_or(0),
        lpSecurityDescriptor: ptr::null_mut(),
        bInheritHandle: TRUE,
    }
}

/// An inheritable handle on the NUL device, for the child's standard input.
fn open_nul() -> Result<Handle, RunError> {
    let name: Vec<u16> = wide("NUL");
    let attributes: SECURITY_ATTRIBUTES = inheritable();
    // SAFETY: `name` is a NUL-terminated wide string and `attributes` is valid for the call.
    let handle: Handle = Handle(unsafe {
        CreateFileW(
            name.as_ptr(),
            FILE_GENERIC_READ,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            &attributes,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL,
            ptr::null_mut(),
        )
    });
    if handle.is_valid() {
        Ok(handle)
    } else {
        Err(RunError::CouldNotStart)
    }
}

/// An anonymous pipe. The write end can be inherited by the child; the read end cannot.
fn create_pipe() -> Result<Pipe, RunError> {
    let attributes: SECURITY_ATTRIBUTES = inheritable();
    let mut read: HANDLE = ptr::null_mut();
    let mut write: HANDLE = ptr::null_mut();
    // SAFETY: both out-pointers are valid, and `attributes` is valid for the call.
    if unsafe { CreatePipe(&mut read, &mut write, &attributes, 0) } == FALSE {
        return Err(RunError::CouldNotStart);
    }
    let write: Handle = Handle(write);
    // SAFETY: `read` was just created; the flag clear makes it private to this program.
    let cleared: i32 = unsafe { SetHandleInformation(read, HANDLE_FLAG_INHERIT, 0) };
    // SAFETY: `read` is a pipe handle owned by nothing else, so the File takes it over.
    let file: File = unsafe { File::from_raw_handle(read as RawHandle) };
    if cleared == FALSE {
        return Err(RunError::CouldNotStart);
    }
    Ok(Pipe { read: file, write })
}

/// Creates the child suspended, with only its three standard handles inherited.
fn start_suspended(
    program: &Path,
    arguments: &[OsString],
    input: &Handle,
    output: &Pipe,
    errors: &Pipe,
) -> Result<PROCESS_INFORMATION, RunError> {
    let application: Vec<u16> = wide_os(program.as_os_str());
    let mut command_line: Vec<u16> = command_line(program.as_os_str(), arguments);
    let mut inherited: [HANDLE; 3] = [input.0, output.write.0, errors.write.0];
    let mut list: AttributeList = handle_list_attribute(&mut inherited)?;

    // SAFETY: an all-zero STARTUPINFOEXW is valid; the fields that matter are set next.
    let mut startup: STARTUPINFOEXW = unsafe { mem::zeroed() };
    startup.StartupInfo.cb = u32::try_from(mem::size_of::<STARTUPINFOEXW>())
        .map_err(|_error: std::num::TryFromIntError| -> RunError { RunError::CouldNotStart })?;
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = input.0;
    startup.StartupInfo.hStdOutput = output.write.0;
    startup.StartupInfo.hStdError = errors.write.0;
    startup.lpAttributeList = list.pointer();

    // SAFETY: an all-zero PROCESS_INFORMATION is valid; CreateProcessW fills it.
    let mut info: PROCESS_INFORMATION = unsafe { mem::zeroed() };
    // SAFETY: `application` and `command_line` are NUL-terminated wide strings (the command line
    // is writable, as the API requires), `startup` is a STARTUPINFOEXW whose size and attribute
    // list are set, and `info` is writable. The environment and folder are inherited (null).
    let created: i32 = unsafe {
        CreateProcessW(
            application.as_ptr(),
            command_line.as_mut_ptr(),
            ptr::null(),
            ptr::null(),
            TRUE,
            CREATE_SUSPENDED | CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT,
            ptr::null(),
            ptr::null(),
            ptr::from_ref(&startup.StartupInfo),
            &mut info,
        )
    };
    drop(list);
    if created == FALSE {
        return Err(RunError::CouldNotStart);
    }
    Ok(info)
}

/// An attribute list holding the handle list for the child. The handles must stay alive and
/// inheritable until the child has been created.
fn handle_list_attribute(handles: &mut [HANDLE; 3]) -> Result<AttributeList, RunError> {
    for handle in handles.iter() {
        // SAFETY: each handle is open and owned by the caller for the whole call.
        let marked: i32 =
            unsafe { SetHandleInformation(*handle, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT) };
        if marked == FALSE {
            return Err(RunError::CouldNotStart);
        }
    }
    let mut size: usize = 0;
    // SAFETY: asking for the size only: a null list with a size out-pointer is the documented call
    // (it reports failure and the size needed).
    let _ = unsafe { InitializeProcThreadAttributeList(ptr::null_mut(), 1, 0, &mut size) };
    if size == 0 {
        return Err(RunError::CouldNotStart);
    }
    let mut list: AttributeList = AttributeList {
        storage: vec![0u64; size.div_ceil(8)],
    };
    // SAFETY: the storage is at least `size` bytes and aligned to eight.
    if unsafe { InitializeProcThreadAttributeList(list.pointer(), 1, 0, &mut size) } == FALSE {
        // Not initialised, so it must not be deleted.
        mem::forget(list);
        return Err(RunError::CouldNotStart);
    }
    // SAFETY: the list is initialised; `handles` outlives the list's use in CreateProcessW, since
    // the caller keeps it until the child is created.
    let updated: i32 = unsafe {
        UpdateProcThreadAttribute(
            list.pointer(),
            0,
            PROC_THREAD_ATTRIBUTE_HANDLE_LIST as usize,
            handles.as_mut_ptr().cast::<c_void>(),
            mem::size_of::<[HANDLE; 3]>(),
            ptr::null_mut(),
            ptr::null(),
        )
    };
    if updated == FALSE {
        return Err(RunError::CouldNotStart);
    }
    Ok(list)
}

/// Reads a pipe to its end, keeping at most `keep` bytes. The flag says the pipe held more. Every
/// chunk is also sent on `forward`, when there is one.
fn drain(mut pipe: File, keep: usize, forward: Option<Sender<Vec<u8>>>) -> (Vec<u8>, bool) {
    let mut kept: Vec<u8> = Vec::new();
    let mut chunk: Vec<u8> = vec![0; 65536];
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
fn drain_tail(mut pipe: File) -> Vec<u8> {
    let mut kept: Vec<u8> = Vec::new();
    let mut chunk: Vec<u8> = vec![0; 16384];
    loop {
        match pipe.read(&mut chunk) {
            Ok(0) | Err(_) => return tail_of(kept, STDERR_TAIL),
            Ok(count) => keep_tail(&mut kept, &chunk[..count], STDERR_TAIL),
        }
    }
}

fn wide(text: &str) -> Vec<u16> {
    wide_os(OsStr::new(text))
}

/// The text as UTF-16 with a closing NUL.
fn wide_os(text: &OsStr) -> Vec<u16> {
    let mut units: Vec<u16> = text.encode_wide().collect();
    units.push(0);
    units
}

/// The command line for CreateProcessW, quoted so that CommandLineToArgvW (which FFmpeg's own
/// startup uses) gives back exactly these arguments.
fn command_line(program: &OsStr, arguments: &[OsString]) -> Vec<u16> {
    let mut line: Vec<u16> = Vec::new();
    append_quoted(&mut line, &program.encode_wide().collect::<Vec<u16>>());
    for argument in arguments {
        line.push(u16::from(b' '));
        append_quoted(&mut line, &argument.encode_wide().collect::<Vec<u16>>());
    }
    line.push(0);
    line
}

fn append_quoted(line: &mut Vec<u16>, argument: &[u16]) -> () {
    const SPACE: u16 = b' ' as u16;
    const TAB: u16 = b'\t' as u16;
    const NEWLINE: u16 = b'\n' as u16;
    const VERTICAL_TAB: u16 = 0x0B;
    const QUOTE: u16 = b'"' as u16;
    const BACKSLASH: u16 = b'\\' as u16;
    let needs_quotes: bool = argument.is_empty()
        || argument.iter().any(|unit: &u16| -> bool {
            matches!(*unit, SPACE | TAB | NEWLINE | VERTICAL_TAB | QUOTE)
        });
    if !needs_quotes {
        line.extend_from_slice(argument);
        return;
    }
    line.push(QUOTE);
    let mut backslashes: usize = 0;
    for unit in argument {
        match *unit {
            BACKSLASH => backslashes += 1,
            QUOTE => {
                // Backslashes before a quote are doubled, and the quote itself is escaped.
                line.extend(std::iter::repeat_n(BACKSLASH, backslashes * 2 + 1));
                line.push(QUOTE);
                backslashes = 0;
            }
            other => {
                line.extend(std::iter::repeat_n(BACKSLASH, backslashes));
                line.push(other);
                backslashes = 0;
            }
        }
    }
    // Backslashes before the closing quote are doubled so that they do not escape it.
    line.extend(std::iter::repeat_n(BACKSLASH, backslashes * 2));
    line.push(QUOTE);
}
