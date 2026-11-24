//! Shared helpers for the process tests: an installed copy of the command, generated media, and a
//! runner that returns what the command wrote.
//!
//! The tests run the real `song2vid` program, copied into its own folder beside FFmpeg and
//! FFprobe, as an installed copy would be. The helper programs come from the folder named by
//! `SONG2VID_TEST_FFMPEG_DIR`; without it the tests that need them say so and stop.

#![allow(dead_code)]

use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::OnceLock;

/// What a run of the command wrote and how it ended.
#[derive(Debug)]
pub struct Run {
    pub status: i32,
    pub stdout: String,
    pub stderr: String,
}

impl Run {
    pub fn both(&self) -> String {
        format!("{}{}", self.stdout, self.stderr)
    }
}

const SUFFIX: &str = if cfg!(windows) { ".exe" } else { "" };

/// The helper programs' folder, or None when the tests are not set up with them.
pub fn helper_folder() -> Option<PathBuf> {
    let folder: PathBuf = PathBuf::from(std::env::var_os("SONG2VID_TEST_FFMPEG_DIR")?);
    if folder.join(format!("ffmpeg{SUFFIX}")).is_file()
        && folder.join(format!("ffprobe{SUFFIX}")).is_file()
    {
        Some(folder)
    } else {
        None
    }
}

/// True (after saying so) when the helper programs are not available to this test run.
pub fn skip_without_helpers() -> bool {
    if helper_folder().is_none() {
        eprintln!(
            "skipped: SONG2VID_TEST_FFMPEG_DIR does not name a folder with ffmpeg and ffprobe"
        );
        return true;
    }
    false
}

/// The installed copy: `<temp>/song2vid-tests-<id>/bin/{song2vid, ffmpeg, ffprobe, SKILL.md}`.
pub fn installed() -> &'static PathBuf {
    static FOLDER: OnceLock<PathBuf> = OnceLock::new();
    FOLDER.get_or_init(|| -> PathBuf {
        // One folder per test program, inside the target folder, reused from run to run.
        let owner: String = std::env::current_exe()
            .ok()
            .and_then(|path: PathBuf| -> Option<String> {
                path.file_stem()
                    .map(|stem: &std::ffi::OsStr| -> String { stem.to_string_lossy().into_owned() })
            })
            .unwrap_or_else(|| -> String { String::from("tests") });
        let folder: PathBuf = Path::new(env!("CARGO_TARGET_TMPDIR"))
            .join("installed")
            .join(owner)
            .join("bin");
        fs::create_dir_all(&folder).expect("a folder for the installed copy");
        fs::copy(
            env!("CARGO_BIN_EXE_song2vid"),
            folder.join(format!("song2vid{SUFFIX}")),
        )
        .expect("copy of the command");
        fs::write(folder.join("SKILL.md"), SKILL_TEXT).expect("the skill file");
        if let Some(helpers) = helper_folder() {
            for name in ["ffmpeg", "ffprobe"] {
                let file: String = format!("{name}{SUFFIX}");
                put_helper(&helpers.join(&file), &folder.join(&file));
            }
        }
        folder
    })
}

/// Puts a helper program beside the command: a link where the system allows (the Mac, where the
/// helpers are large host programs), a copy on Windows.
fn put_helper(from: &Path, to: &Path) -> () {
    let _ = fs::remove_file(to);
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(from, to).expect("a link to a helper program");
    }
    #[cfg(not(unix))]
    {
        fs::copy(from, to).expect("copy of a helper program");
    }
}

/// A copy of the command with no helper programs and no skill beside it.
pub fn bare_copy() -> PathBuf {
    let folder: PathBuf = Path::new(env!("CARGO_TARGET_TMPDIR")).join("bare").join(
        std::env::current_exe()
            .ok()
            .and_then(|path: PathBuf| -> Option<String> {
                path.file_stem()
                    .map(|stem: &std::ffi::OsStr| -> String { stem.to_string_lossy().into_owned() })
            })
            .unwrap_or_else(|| -> String { String::from("tests") }),
    );
    fs::create_dir_all(&folder).expect("a folder for the bare copy");
    fs::copy(
        env!("CARGO_BIN_EXE_song2vid"),
        folder.join(format!("song2vid{SUFFIX}")),
    )
    .expect("copy of the command");
    folder
}

pub const SKILL_TEXT: &str =
    "# Song2Vid skill\n\nA stand-in with a line of text, and a second one.\n";
/// A word in every folder the tests make, so a folder path in an output is easy to find.
pub const FOLDER_MARKER: &str = "planted-folder-marker";

pub fn unique_folder(purpose: &str) -> PathBuf {
    // Tests run in parallel inside one process, so a counter, not the clock, keeps the folders apart.
    static COUNTER: AtomicU32 = AtomicU32::new(0);
    let nanos: u128 = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed: std::time::Duration| -> u128 { elapsed.as_nanos() })
        .unwrap_or(0);
    let id: String = format!(
        "{:x}-{}-{}",
        nanos,
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::SeqCst)
    );
    let folder: PathBuf = std::env::temp_dir().join(format!("{FOLDER_MARKER}-{purpose}-{id}"));
    fs::create_dir_all(&folder).expect("a scratch folder");
    folder
}

/// A scratch folder for one test, removed when it goes out of scope.
pub struct Workspace {
    pub folder: PathBuf,
}

impl Workspace {
    pub fn new() -> Workspace {
        Workspace {
            folder: unique_folder("work"),
        }
    }

    pub fn path(&self, name: &str) -> PathBuf {
        self.folder.join(name)
    }

    pub fn listing(&self) -> Vec<String> {
        let mut names: Vec<String> = fs::read_dir(&self.folder)
            .expect("the folder")
            .map(|entry| -> String {
                entry
                    .expect("an entry")
                    .file_name()
                    .to_string_lossy()
                    .into_owned()
            })
            .collect();
        names.sort();
        names
    }

    /// A WAV of whole frames, silent. Seconds times the rate must be a whole number.
    pub fn wav(&self, name: &str, seconds: f64, rate: u32, channels: u16) -> PathBuf {
        let path: PathBuf = self.path(name);
        write_wav(&path, seconds, rate, channels);
        path
    }

    /// A picture of four coloured quadrants, with an EXIF orientation when it is not 1.
    pub fn png(&self, name: &str, width: u32, height: u32, orientation: u16) -> PathBuf {
        let path: PathBuf = self.path(name);
        write_png(&path, width, height, orientation, false);
        path
    }

    pub fn transparent_png(&self, name: &str, width: u32, height: u32) -> PathBuf {
        let path: PathBuf = self.path(name);
        write_png(&path, width, height, 1, true);
        path
    }

    pub fn not_media(&self, name: &str) -> PathBuf {
        let path: PathBuf = self.path(name);
        fs::write(&path, "this is plain text, not media").expect("a file");
        path
    }
}

impl Drop for Workspace {
    fn drop(&mut self) -> () {
        let _ = fs::remove_dir_all(&self.folder);
    }
}

pub fn write_wav(path: &Path, seconds: f64, rate: u32, channels: u16) -> () {
    let frames: u32 = (seconds * f64::from(rate)).round() as u32;
    let data_bytes: u32 = frames * u32::from(channels) * 2;
    let mut bytes: Vec<u8> = Vec::new();
    bytes.extend_from_slice(b"RIFF");
    bytes.extend_from_slice(&(36 + data_bytes).to_le_bytes());
    bytes.extend_from_slice(b"WAVEfmt ");
    bytes.extend_from_slice(&16u32.to_le_bytes());
    bytes.extend_from_slice(&1u16.to_le_bytes());
    bytes.extend_from_slice(&channels.to_le_bytes());
    bytes.extend_from_slice(&rate.to_le_bytes());
    bytes.extend_from_slice(&(rate * u32::from(channels) * 2).to_le_bytes());
    bytes.extend_from_slice(&(channels * 2).to_le_bytes());
    bytes.extend_from_slice(&16u16.to_le_bytes());
    bytes.extend_from_slice(b"data");
    bytes.extend_from_slice(&data_bytes.to_le_bytes());
    bytes.resize(bytes.len() + data_bytes as usize, 0);
    fs::write(path, bytes).expect("a WAV file");
}

/// A PNG written without compression (stored deflate blocks), so no encoder is needed.
pub fn write_png(path: &Path, width: u32, height: u32, orientation: u16, transparent: bool) -> () {
    let channels: usize = 4;
    let mut raw: Vec<u8> = Vec::with_capacity((width as usize * channels + 1) * height as usize);
    for y in 0..height {
        raw.push(0);
        for x in 0..width {
            let top: bool = y < height / 2;
            let left: bool = x < width / 2;
            let (r, g, b): (u8, u8, u8) = match (top, left) {
                (true, true) => (255, 0, 0),
                (true, false) => (0, 255, 0),
                (false, true) => (0, 0, 255),
                (false, false) => (255, 255, 0),
            };
            raw.extend_from_slice(&[r, g, b, if transparent { 0 } else { 255 }]);
        }
    }
    let mut zlib: Vec<u8> = vec![0x78, 0x01];
    let mut chunks = raw.chunks(65535).peekable();
    while let Some(chunk) = chunks.next() {
        zlib.push(u8::from(chunks.peek().is_none()));
        zlib.extend_from_slice(&(chunk.len() as u16).to_le_bytes());
        zlib.extend_from_slice(&(!(chunk.len() as u16)).to_le_bytes());
        zlib.extend_from_slice(chunk);
    }
    zlib.extend_from_slice(&adler32(&raw).to_be_bytes());

    let mut png: Vec<u8> = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
    let mut header: Vec<u8> = Vec::new();
    header.extend_from_slice(&width.to_be_bytes());
    header.extend_from_slice(&height.to_be_bytes());
    header.extend_from_slice(&[8, 6, 0, 0, 0]);
    push_chunk(&mut png, b"IHDR", &header);
    if orientation != 1 {
        // A big-endian TIFF block with one entry, Orientation.
        let mut exif: Vec<u8> = b"MM\0*\0\0\0\x08\0\x01".to_vec();
        exif.extend_from_slice(&[0x01, 0x12, 0, 3, 0, 0, 0, 1]);
        exif.extend_from_slice(&orientation.to_be_bytes());
        exif.extend_from_slice(&[0, 0, 0, 0, 0, 0]);
        push_chunk(&mut png, b"eXIf", &exif);
    }
    push_chunk(&mut png, b"IDAT", &zlib);
    push_chunk(&mut png, b"IEND", &[]);
    fs::write(path, png).expect("a PNG file");
}

fn push_chunk(png: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) -> () {
    png.extend_from_slice(&(data.len() as u32).to_be_bytes());
    let mut checked: Vec<u8> = kind.to_vec();
    checked.extend_from_slice(data);
    png.extend_from_slice(&checked);
    png.extend_from_slice(&crc32(&checked).to_be_bytes());
}

fn adler32(data: &[u8]) -> u32 {
    let (mut a, mut b): (u32, u32) = (1, 0);
    for byte in data {
        a = (a + u32::from(*byte)) % 65521;
        b = (b + a) % 65521;
    }
    b << 16 | a
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc: u32 = 0xFFFF_FFFF;
    for byte in data {
        crc ^= u32::from(*byte);
        for _ in 0..8 {
            crc = if crc & 1 == 1 {
                crc >> 1 ^ 0xEDB8_8320
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

/// Runs the installed command. The environment holds only what the program needs to start, plus
/// `extra`.
pub fn run(args: &[&str], extra: &[(&str, &str)], current_dir: Option<&Path>) -> Run {
    run_in(installed(), args, extra, current_dir, true)
}

pub fn run_in(
    folder: &Path,
    args: &[&str],
    extra: &[(&str, &str)],
    current_dir: Option<&Path>,
    stdin_closed: bool,
) -> Run {
    let mut command: Command = Command::new(folder.join(format!("song2vid{SUFFIX}")));
    command.args(args).env_clear();
    for name in ["SystemRoot", "SYSTEMROOT", "TEMP", "TMP", "PATH"] {
        if let Some(value) = std::env::var_os(name) {
            command.env(name, value);
        }
    }
    let extras: BTreeMap<&str, &str> = extra.iter().copied().collect();
    for (name, value) in extras {
        command.env(name, value);
    }
    if let Some(dir) = current_dir {
        command.current_dir(dir);
    }
    command.stdin(if stdin_closed {
        Stdio::null()
    } else {
        Stdio::piped()
    });
    let output = command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .expect("the command runs");
    Run {
        status: output.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
    }
}

/// Runs the command with its standard input held open by the test, so the test can close it.
pub fn spawn_with_open_stdin(args: &[&str], current_dir: Option<&Path>) -> std::process::Child {
    let mut command: Command = Command::new(installed().join(format!("song2vid{SUFFIX}")));
    command.args(args).env_clear();
    for name in ["SystemRoot", "SYSTEMROOT", "TEMP", "TMP", "PATH"] {
        if let Some(value) = std::env::var_os(name) {
            command.env(name, value);
        }
    }
    if let Some(dir) = current_dir {
        command.current_dir(dir);
    }
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("the command starts")
}

pub fn write_to_stdin(child: &mut std::process::Child, text: &str) -> () {
    if let Some(stdin) = child.stdin.as_mut() {
        stdin.write_all(text.as_bytes()).expect("write to stdin");
        stdin.flush().expect("flush stdin");
    }
}

/// The text of one JSON output line, parsed.
pub fn json_line(text: &str) -> serde_json::Value {
    assert!(
        text.ends_with('\n') && text.matches('\n').count() == 1,
        "not exactly one line: {text:?}"
    );
    serde_json::from_str(text.trim_end()).expect("JSON")
}
