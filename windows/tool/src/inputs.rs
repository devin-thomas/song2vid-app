//! The files named on the command line: finding them, naming them in output without their folder,
//! and the song and picture types of SPEC section 7.

use std::ffi::OsStr;
use std::fs;
use std::path::PathBuf;

/// The file name extensions of the song types in SPEC section 7 (the types the Mac command's
/// system type table calls audio: MP3, M4A and its ringtone twin, WAV, AIFF, FLAC and CAF).
const SONG_EXTENSIONS: [&str; 9] = [
    "mp3", "m4a", "m4r", "wav", "wave", "aiff", "aif", "flac", "caf",
];

/// A file named on the command line.
#[derive(Clone, Debug)]
pub struct InputFile {
    /// The path as given, for asking the system about it.
    pub given: PathBuf,
}

impl InputFile {
    pub fn new(given: &OsStr) -> InputFile {
        InputFile {
            given: PathBuf::from(given),
        }
    }

    /// The file name only: a folder never reaches the output.
    pub fn name(&self) -> String {
        self.given
            .file_name()
            .map(|name: &OsStr| -> String { name.to_string_lossy().into_owned() })
            .unwrap_or_default()
    }

    /// True when something is there, of any kind (a folder counts: it is found, then unreadable).
    pub fn exists(&self) -> bool {
        self.given.exists()
    }

    /// True when the name ends in one of SPEC section 7's song types.
    pub fn has_song_extension(&self) -> bool {
        self.given
            .extension()
            .map(|extension: &OsStr| -> String { extension.to_string_lossy().to_lowercase() })
            .is_some_and(|extension: String| -> bool {
                SONG_EXTENSIONS.contains(&extension.as_str())
            })
    }

    /// The full, absolute path the helper programs open, or None when it is not a plain file (a
    /// folder, a device). A path too long for the usual 260-character limit gets the `\\?\` form on
    /// Windows; a shorter one is written the usual way, because FFmpeg decides what kind of file it
    /// is partly by looking at the name, and it does that less well with the long form.
    pub fn path_for_tools(&self) -> Option<PathBuf> {
        let resolved: PathBuf = fs::canonicalize(&self.given).ok()?;
        if resolved.is_file() {
            Some(shortest_form(resolved))
        } else {
            None
        }
    }
}

/// The path without the `\\?\` prefix when it fits in 259 characters, which every program accepts.
#[cfg(windows)]
pub(crate) fn shortest_form(path: PathBuf) -> PathBuf {
    use std::os::windows::ffi::{OsStrExt, OsStringExt};

    const MAX_PLAIN_PATH: usize = 259;
    let units: Vec<u16> = path.as_os_str().encode_wide().collect();
    let verbatim: Vec<u16> = r"\\?\".encode_utf16().collect();
    let unc: Vec<u16> = r"\\?\UNC\".encode_utf16().collect();
    if units.starts_with(&unc) {
        // \\?\UNC\server\share\file is \\server\share\file.
        let mut plain: Vec<u16> = r"\\".encode_utf16().collect();
        plain.extend_from_slice(&units[unc.len()..]);
        if plain.len() <= MAX_PLAIN_PATH {
            return PathBuf::from(std::ffi::OsString::from_wide(&plain));
        }
    } else if units.starts_with(&verbatim) && units.len() - verbatim.len() <= MAX_PLAIN_PATH {
        return PathBuf::from(std::ffi::OsString::from_wide(&units[verbatim.len()..]));
    }
    path
}

#[cfg(not(windows))]
pub(crate) fn shortest_form(path: PathBuf) -> PathBuf {
    path
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input(text: &str) -> InputFile {
        InputFile::new(OsStr::new(text))
    }

    #[test]
    fn the_name_has_no_folder() {
        assert_eq!(input("some/folder/song one.wav").name(), "song one.wav");
        assert_eq!(input("folder/").name(), "folder");
        assert_eq!(input("plain.png").name(), "plain.png");
    }

    #[test]
    fn song_types_are_found_by_extension_ignoring_case() {
        for name in [
            "a.mp3", "a.M4A", "a.wav", "a.aiff", "a.AIF", "a.flac", "a.caf", "a.b.mp3",
        ] {
            assert!(input(name).has_song_extension(), "{name}");
        }
        for name in ["a.png", "a.aac", "a", "a.mp3 ", ".mp3", "a.txt", "mp3"] {
            assert!(!input(name).has_song_extension(), "{name}");
        }
    }

    #[cfg(windows)]
    #[test]
    fn a_short_verbatim_path_is_written_the_usual_way_and_a_long_one_is_not() {
        let plain = |text: &str| -> PathBuf { shortest_form(PathBuf::from(text)) };
        assert_eq!(plain(r"\\?\C:\a\b.png"), PathBuf::from(r"C:\a\b.png"));
        assert_eq!(
            plain(r"\\?\UNC\srv\share\f.png"),
            PathBuf::from(r"\\srv\share\f.png")
        );
        let long: String = format!(r"\\?\C:\{}\f.png", "x".repeat(300));
        assert_eq!(plain(&long), PathBuf::from(long));
        assert_eq!(
            plain(r"C:\already\plain.png"),
            PathBuf::from(r"C:\already\plain.png")
        );
    }
}
