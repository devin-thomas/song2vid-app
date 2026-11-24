//! A checked output and the single step that publishes it (SPEC sections 14.4 and 26.3, ADR-014).
//!
//! The file is written under a temporary name beside the final name and moved into place in one
//! step, so a half-made file never has the final name. Without `--overwrite` the move refuses to
//! replace anything, so a name that appeared during the run is never touched.

use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use crate::error::CommandError;

/// Where an output goes, once its folder and name have been checked.
#[derive(Clone, Debug)]
pub struct Destination {
    /// The final name, in the folder as the system names it.
    path: PathBuf,
    folder: PathBuf,
    /// The file name only: a folder never reaches the output.
    pub name: String,
}

/// A file being written under its temporary name. It is removed when this goes out of scope,
/// unless it was moved into place.
pub struct TemporaryFile {
    path: PathBuf,
    file: Option<File>,
    placed: bool,
}

impl TemporaryFile {
    pub fn write_all(&mut self, bytes: &[u8]) -> Result<(), CommandError> {
        let Some(file) = self.file.as_mut() else {
            return Err(CommandError::output_folder_not_writable());
        };
        file.write_all(bytes)
            .map_err(|error: std::io::Error| -> CommandError { write_error(&error) })?;
        file.flush()
            .map_err(|error: std::io::Error| -> CommandError { write_error(&error) })
    }

    /// Closes the file, so it can be moved.
    pub fn finish(&mut self) -> () {
        self.file = None;
    }
}

impl Drop for TemporaryFile {
    fn drop(&mut self) -> () {
        self.file = None;
        if !self.placed {
            let _ = fs::remove_file(&self.path);
        }
    }
}

impl Destination {
    /// Checks the output name and folder. Without `overwrite`, a file already there is an error.
    /// Nothing is created or changed.
    pub fn plan(
        output: &Path,
        inputs: &[&Path],
        overwrite: bool,
    ) -> Result<Destination, CommandError> {
        let name: String = output
            .file_name()
            .map(|name: &std::ffi::OsStr| -> String { name.to_string_lossy().into_owned() })
            .unwrap_or_default();
        let given_folder: &Path = match output.parent() {
            Some(parent) if !parent.as_os_str().is_empty() => parent,
            _ => Path::new("."),
        };
        let folder: PathBuf = fs::canonicalize(given_folder)
            .ok()
            .filter(|resolved: &PathBuf| -> bool { resolved.is_dir() })
            .ok_or_else(CommandError::output_folder_not_found)?;
        if !platform::folder_accepts_files(&folder) {
            return Err(CommandError::output_folder_not_writable());
        }
        let path: PathBuf = folder.join(&name);
        let destination: Destination = Destination { path, folder, name };

        // An entry of any kind at the output (a dangling link counts) is "already there".
        let Ok(entry) = fs::symlink_metadata(&destination.path) else {
            return Ok(destination);
        };
        // Never the person's own song or image, whatever the name and whatever --overwrite says.
        if let Some(target) = platform::file_identity(&destination.path) {
            let same: bool = inputs
                .iter()
                .any(|input: &&Path| -> bool { platform::file_identity(input) == Some(target) });
            if same {
                return Err(CommandError::output_is_an_input());
            }
        }
        if !overwrite {
            return Err(CommandError::output_exists());
        }
        if entry.is_dir() {
            return Err(CommandError::output_is_a_folder());
        }
        Ok(destination)
    }

    /// Creates the temporary file beside the final name.
    pub fn create_temporary(&self) -> Result<TemporaryFile, CommandError> {
        let random: String = platform::random_hex().ok_or_else(CommandError::preview_failed)?;
        let path: PathBuf = self.folder.join(format!(".song2vid-{random}.tmp"));
        let file: File = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
            .map_err(|error: std::io::Error| -> CommandError { write_error(&error) })?;
        Ok(TemporaryFile {
            path,
            file: Some(file),
            placed: false,
        })
    }

    /// Moves the finished file to the final name, which is touched only here.
    pub fn place(
        &self,
        temporary: &mut TemporaryFile,
        overwrite: bool,
    ) -> Result<(), CommandError> {
        temporary.finish();
        platform::move_into_place(&temporary.path, &self.path, overwrite)?;
        temporary.placed = true;
        Ok(())
    }
}

/// A failed write as the command reports it.
fn write_error(error: &std::io::Error) -> CommandError {
    if platform::is_disk_full(error) {
        CommandError::disk_full()
    } else {
        CommandError::output_folder_not_writable()
    }
}

#[cfg(windows)]
#[allow(unsafe_code)]
mod platform {
    use std::ffi::OsStr;
    use std::fs::File;
    use std::os::windows::ffi::OsStrExt;
    use std::os::windows::io::AsRawHandle;
    use std::path::Path;
    use std::ptr;
    use std::thread;
    use std::time::{Duration, Instant};

    use windows_sys::Win32::Foundation::{
        CloseHandle, GetLastError, ERROR_ACCESS_DENIED, ERROR_ALREADY_EXISTS, ERROR_DISK_FULL,
        ERROR_FILE_EXISTS, ERROR_HANDLE_DISK_FULL, ERROR_LOCK_VIOLATION, ERROR_SHARING_VIOLATION,
        FALSE, HANDLE, INVALID_HANDLE_VALUE,
    };
    use windows_sys::Win32::Security::Cryptography::{
        BCryptGenRandom, BCRYPT_USE_SYSTEM_PREFERRED_RNG,
    };
    use windows_sys::Win32::Storage::FileSystem::{
        CreateFileW, GetFileInformationByHandle, MoveFileExW, BY_HANDLE_FILE_INFORMATION,
        FILE_ADD_FILE, FILE_FLAG_BACKUP_SEMANTICS, FILE_SHARE_DELETE, FILE_SHARE_READ,
        FILE_SHARE_WRITE, MOVEFILE_REPLACE_EXISTING, OPEN_EXISTING,
    };

    use crate::error::CommandError;

    /// How long a replace waits for another program to let go of the old file (SPEC section 26.3).
    const REPLACE_PATIENCE: Duration = Duration::from_secs(2);
    const RETRY_PAUSE: Duration = Duration::from_millis(50);

    fn wide(path: &OsStr) -> Vec<u16> {
        let mut units: Vec<u16> = path.encode_wide().collect();
        units.push(0);
        units
    }

    /// True when a file can be added to the folder. The folder is opened with the right to add
    /// files; nothing is created.
    pub(super) fn folder_accepts_files(folder: &Path) -> bool {
        let name: Vec<u16> = wide(folder.as_os_str());
        // SAFETY: `name` is a NUL-terminated wide string; the other arguments are plain values.
        let handle: HANDLE = unsafe {
            CreateFileW(
                name.as_ptr(),
                FILE_ADD_FILE,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                ptr::null(),
                OPEN_EXISTING,
                FILE_FLAG_BACKUP_SEMANTICS,
                ptr::null_mut(),
            )
        };
        if handle == INVALID_HANDLE_VALUE {
            return false;
        }
        // SAFETY: the handle was just opened and is closed once.
        let _ = unsafe { CloseHandle(handle) };
        true
    }

    /// Which file a path names: the volume and the file's index on it. Two paths to one file (a
    /// link, a different spelling) give the same answer.
    pub(super) fn file_identity(path: &Path) -> Option<(u32, u64)> {
        let file: File = File::open(path).ok()?;
        // SAFETY: an all-zero BY_HANDLE_FILE_INFORMATION is valid; the call fills it.
        let mut info: BY_HANDLE_FILE_INFORMATION = unsafe { std::mem::zeroed() };
        // SAFETY: the handle belongs to `file`, which is open, and `info` is writable.
        let read: i32 = unsafe { GetFileInformationByHandle(file.as_raw_handle(), &mut info) };
        if read == FALSE {
            return None;
        }
        let index: u64 = u64::from(info.nFileIndexHigh) << 32 | u64::from(info.nFileIndexLow);
        Some((info.dwVolumeSerialNumber, index))
    }

    pub(super) fn random_hex() -> Option<String> {
        let mut bytes: [u8; 16] = [0; 16];
        // SAFETY: the buffer is writable for 16 bytes; no algorithm handle is needed with the
        // system-preferred generator flag.
        let status: i32 = unsafe {
            BCryptGenRandom(
                ptr::null_mut(),
                bytes.as_mut_ptr(),
                16,
                BCRYPT_USE_SYSTEM_PREFERRED_RNG,
            )
        };
        if status != 0 {
            return None;
        }
        Some(
            bytes
                .iter()
                .map(|byte: &u8| -> String { format!("{byte:02x}") })
                .collect(),
        )
    }

    pub(super) fn is_disk_full(error: &std::io::Error) -> bool {
        matches!(
            error
                .raw_os_error()
                .and_then(|code: i32| -> Option<u32> { u32::try_from(code).ok() }),
            Some(ERROR_DISK_FULL | ERROR_HANDLE_DISK_FULL)
        )
    }

    /// Moves `from` to `to` in one step. Without `overwrite` nothing is replaced, so a name that
    /// appeared since the check gives `output_exists`. With it, an old file another program holds
    /// open is retried for two seconds, then `output_in_use`.
    pub(super) fn move_into_place(
        from: &Path,
        to: &Path,
        overwrite: bool,
    ) -> Result<(), CommandError> {
        let source: Vec<u16> = wide(from.as_os_str());
        let target: Vec<u16> = wide(to.as_os_str());
        let flags: u32 = if overwrite {
            MOVEFILE_REPLACE_EXISTING
        } else {
            0
        };
        let started: Instant = Instant::now();
        loop {
            // SAFETY: both are NUL-terminated wide strings.
            let moved: i32 = unsafe { MoveFileExW(source.as_ptr(), target.as_ptr(), flags) };
            if moved != FALSE {
                return Ok(());
            }
            // SAFETY: reads the calling thread's last error, right after the failed call.
            let code: u32 = unsafe { GetLastError() };
            match code {
                ERROR_ALREADY_EXISTS | ERROR_FILE_EXISTS if !overwrite => {
                    return Err(CommandError::output_exists());
                }
                ERROR_SHARING_VIOLATION | ERROR_LOCK_VIOLATION | ERROR_ACCESS_DENIED
                    if overwrite =>
                {
                    let read_only: bool = std::fs::metadata(to)
                        .map(|found: std::fs::Metadata| -> bool { found.permissions().readonly() })
                        .unwrap_or(false);
                    if code == ERROR_ACCESS_DENIED && read_only {
                        return Err(CommandError::output_folder_not_writable());
                    }
                    if started.elapsed() >= REPLACE_PATIENCE {
                        return Err(CommandError::output_in_use());
                    }
                    thread::sleep(RETRY_PAUSE);
                }
                ERROR_DISK_FULL | ERROR_HANDLE_DISK_FULL => return Err(CommandError::disk_full()),
                _ => return Err(CommandError::output_folder_not_writable()),
            }
        }
    }
}

#[cfg(not(windows))]
mod platform {
    use std::fs::{self, File};
    use std::io::Read;
    use std::os::unix::fs::MetadataExt;
    use std::path::Path;

    use crate::error::CommandError;

    pub(super) fn folder_accepts_files(folder: &Path) -> bool {
        fs::metadata(folder)
            .map(|found: fs::Metadata| -> bool { !found.permissions().readonly() })
            .unwrap_or(false)
    }

    pub(super) fn file_identity(path: &Path) -> Option<(u64, u64)> {
        let found: fs::Metadata = fs::metadata(path).ok()?;
        Some((found.dev(), found.ino()))
    }

    pub(super) fn random_hex() -> Option<String> {
        let mut bytes: [u8; 16] = [0; 16];
        File::open("/dev/urandom")
            .ok()?
            .read_exact(&mut bytes)
            .ok()?;
        Some(
            bytes
                .iter()
                .map(|byte: &u8| -> String { format!("{byte:02x}") })
                .collect(),
        )
    }

    pub(super) fn is_disk_full(error: &std::io::Error) -> bool {
        error.raw_os_error() == Some(28)
    }

    pub(super) fn move_into_place(
        from: &Path,
        to: &Path,
        overwrite: bool,
    ) -> Result<(), CommandError> {
        if !overwrite {
            // A hard link fails if the name is taken, and leaves the temporary name to be removed.
            return match fs::hard_link(from, to) {
                Ok(()) => {
                    let _ = fs::remove_file(from);
                    Ok(())
                }
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                    Err(CommandError::output_exists())
                }
                Err(_) => Err(CommandError::output_folder_not_writable()),
            };
        }
        fs::rename(from, to).map_err(|_error: std::io::Error| -> CommandError {
            CommandError::output_folder_not_writable()
        })
    }
}
