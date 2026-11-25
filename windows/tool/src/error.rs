//! What the command reports when it can't do what was asked (SPEC sections 14.6 and 24.6).
//!
//! The messages are fixed text or the SPEC section 7 wording: none of them contains a path or
//! anything the person typed.

use crate::json::{JsonKey, JsonValue};

/// Exit statuses (SPEC section 14.6).
pub mod status {
    pub const SUCCESS: i32 = 0;
    pub const NOT_FOUND: i32 = 1;
    pub const USAGE: i32 = 2;
    pub const UNREADABLE: i32 = 3;
    pub const OUTPUT_FAILED: i32 = 4;
    pub const EXPORT_FAILED: i32 = 5;
    pub const CANCELLED: i32 = 130;
}

/// The error codes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ErrorCode {
    Usage,
    AudioNotFound,
    ImageNotFound,
    AudioUnreadable,
    ImageUnreadable,
    ImageTooSmall,
    CodecUnavailable,
    OutputExists,
    OutputInUse,
    OutputNotWritable,
    OutputNotMp4,
    DiskFull,
    ExportFailed,
    Network,
    Cancelled,
}

impl ErrorCode {
    /// The code as it is written in JSON.
    pub fn text(self) -> &'static str {
        match self {
            ErrorCode::Usage => "usage",
            ErrorCode::AudioNotFound => "audio_not_found",
            ErrorCode::ImageNotFound => "image_not_found",
            ErrorCode::AudioUnreadable => "audio_unreadable",
            ErrorCode::ImageUnreadable => "image_unreadable",
            ErrorCode::ImageTooSmall => "image_too_small",
            ErrorCode::CodecUnavailable => "codec_unavailable",
            ErrorCode::OutputExists => "output_exists",
            ErrorCode::OutputInUse => "output_in_use",
            ErrorCode::OutputNotWritable => "output_not_writable",
            ErrorCode::OutputNotMp4 => "output_not_mp4",
            ErrorCode::DiskFull => "disk_full",
            ErrorCode::ExportFailed => "export_failed",
            ErrorCode::Network => "network",
            ErrorCode::Cancelled => "cancelled",
        }
    }

    /// The exit status for this code.
    pub fn status(self) -> i32 {
        match self {
            ErrorCode::AudioNotFound | ErrorCode::ImageNotFound => status::NOT_FOUND,
            ErrorCode::Usage => status::USAGE,
            ErrorCode::AudioUnreadable
            | ErrorCode::ImageUnreadable
            | ErrorCode::ImageTooSmall
            | ErrorCode::CodecUnavailable => status::UNREADABLE,
            ErrorCode::OutputExists
            | ErrorCode::OutputInUse
            | ErrorCode::OutputNotWritable
            | ErrorCode::OutputNotMp4
            | ErrorCode::DiskFull => status::OUTPUT_FAILED,
            ErrorCode::ExportFailed | ErrorCode::Network => status::EXPORT_FAILED,
            ErrorCode::Cancelled => status::CANCELLED,
        }
    }
}

/// A failure the command reports: a code and one line of fixed text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommandError {
    pub code: ErrorCode,
    pub message: String,
}

impl CommandError {
    pub fn new(code: ErrorCode, message: &str) -> CommandError {
        CommandError {
            code,
            message: String::from(message),
        }
    }

    pub fn audio_not_found() -> CommandError {
        Self::new(ErrorCode::AudioNotFound, "The audio file was not found.")
    }

    pub fn image_not_found() -> CommandError {
        Self::new(ErrorCode::ImageNotFound, "The image file was not found.")
    }

    pub fn audio_unreadable() -> CommandError {
        Self::new(
            ErrorCode::AudioUnreadable,
            "Song2Vid can't read this audio file.",
        )
    }

    pub fn image_unreadable() -> CommandError {
        Self::new(
            ErrorCode::ImageUnreadable,
            "Song2Vid can't read this image file.",
        )
    }

    pub fn image_too_small() -> CommandError {
        Self::new(
            ErrorCode::ImageTooSmall,
            "This image is too small. Original needs an image of at least 16\u{d7}16 pixels.",
        )
    }

    pub fn output_exists() -> CommandError {
        Self::new(
            ErrorCode::OutputExists,
            "The output file already exists. Use --overwrite to replace it.",
        )
    }

    pub fn output_in_use() -> CommandError {
        Self::new(
            ErrorCode::OutputInUse,
            "Another program is using the output file. Close it and try again.",
        )
    }

    pub fn output_not_mp4() -> CommandError {
        Self::new(
            ErrorCode::OutputNotMp4,
            "The output file name must end in .mp4.",
        )
    }

    pub fn output_folder_not_found() -> CommandError {
        Self::new(
            ErrorCode::OutputNotWritable,
            "The output folder was not found.",
        )
    }

    pub fn output_folder_not_writable() -> CommandError {
        Self::new(
            ErrorCode::OutputNotWritable,
            "Song2Vid can't write to the output folder.",
        )
    }

    pub fn output_is_a_folder() -> CommandError {
        Self::new(
            ErrorCode::OutputNotWritable,
            "The output can't be a folder.",
        )
    }

    pub fn output_is_an_input() -> CommandError {
        Self::new(
            ErrorCode::OutputNotWritable,
            "The output can't be one of the input files.",
        )
    }

    pub fn disk_full() -> CommandError {
        Self::new(ErrorCode::DiskFull, "Not enough disk space.")
    }

    /// The chosen Codec can't be made on this computer (SPEC sections 23 and 24.6).
    pub fn codec_unavailable(title: &str) -> CommandError {
        Self::new(
            ErrorCode::CodecUnavailable,
            &format!("This computer can't make {title} videos."),
        )
    }

    /// The video could not be made after the files were accepted (SPEC section 14.6).
    pub fn export_failed() -> CommandError {
        Self::new(ErrorCode::ExportFailed, "Couldn't make the video.")
    }

    pub fn preview_failed() -> CommandError {
        Self::new(ErrorCode::ExportFailed, "Couldn't make the preview.")
    }

    pub fn cancelled() -> CommandError {
        Self::new(ErrorCode::Cancelled, "Cancelled.")
    }

    pub fn network() -> CommandError {
        Self::new(
            ErrorCode::Network,
            "Couldn't check for updates. Check the internet connection and try again.",
        )
    }

    /// The exit status for this error's code.
    pub fn status(&self) -> i32 {
        self.code.status()
    }
}

/// What a run of the command wrote and how it ended.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommandOutput {
    pub stdout: String,
    pub stderr: String,
    pub status: i32,
}

impl CommandOutput {
    pub fn success(stdout: String) -> CommandOutput {
        CommandOutput {
            stdout,
            stderr: String::new(),
            status: status::SUCCESS,
        }
    }

    /// An error as the command reports it: one line on stderr, or under `--json` one `error` line
    /// on stdout and nothing on stderr.
    pub fn failure(error: &CommandError, json: bool) -> CommandOutput {
        if json {
            let line: JsonValue = JsonValue::line_of_type(
                "error",
                vec![(
                    JsonKey::Error,
                    JsonValue::Object(vec![
                        (
                            JsonKey::Code,
                            JsonValue::String(String::from(error.code.text())),
                        ),
                        (JsonKey::Message, JsonValue::String(error.message.clone())),
                    ]),
                )],
            );
            return CommandOutput {
                stdout: line.line(),
                stderr: String::new(),
                status: error.status(),
            };
        }
        CommandOutput {
            stdout: String::new(),
            stderr: format!("{}\n", error.message),
            status: error.status(),
        }
    }
}
