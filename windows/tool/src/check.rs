//! `song2vid check <audio> <image> [-j]` and `song2vid check <file> [-j]` (SPEC sections 14.3 and
//! 24.8): reads the files and reports what would be made. It writes nothing.

use crate::cancel::CancelToken;
use crate::context::Context;
use crate::error::{CommandError, CommandOutput, ErrorCode};
use crate::inputs::InputFile;
use crate::media::{self, AudioStream, Inspection, MediaError, Picture};
use crate::options::{Argument, CommandScope, UsageProblem};
use crate::report::{AudioFacts, CheckReport, ImageFacts};

pub fn run(operands: &[Argument], json: bool, context: &Context) -> CommandOutput {
    let report: Result<CheckReport, CommandError> = match operands {
        [one] => read_one(&InputFile::new(&one.raw), context),
        [audio, image] => read_two(
            &InputFile::new(&audio.raw),
            &InputFile::new(&image.raw),
            context,
        ),
        _ => Err(CommandError::from_usage(&UsageProblem::new(
            "check needs one audio file and one image file, or a single file.",
            CommandScope::Check,
            json,
        ))),
    };
    match report {
        Ok(report) => CommandOutput::success(if json {
            report.json_value().line()
        } else {
            report.text()
        }),
        Err(error) => CommandOutput::failure(&error, json),
    }
}

/// Looks for both files first (status 1), then reads the audio, then the image (status 3).
fn read_two(
    audio: &InputFile,
    image: &InputFile,
    context: &Context,
) -> Result<CheckReport, CommandError> {
    if !audio.exists() {
        return Err(CommandError::audio_not_found());
    }
    if !image.exists() {
        return Err(CommandError::image_not_found());
    }
    let song: AudioFacts = song_facts(audio, context)?;
    let picture: ImageFacts = picture_facts(image, context)?;
    Ok(CheckReport::new(Some(song), Some(picture)))
}

/// Reads a file alone (SPEC section 24.8). Its type comes from its contents: a file with audio is a
/// song, else a still picture is an image. A file that is neither, or is missing, is reported as the
/// kind its extension says (a section 7 song type means audio, anything else means image).
fn read_one(file: &InputFile, context: &Context) -> Result<CheckReport, CommandError> {
    let extension_is_song: bool = file.has_song_extension();
    if !file.exists() {
        return Err(if extension_is_song {
            CommandError::audio_not_found()
        } else {
            CommandError::image_not_found()
        });
    }
    match inspect(file, context)? {
        Inspection::Audio(audio) => Ok(CheckReport::new(Some(audio_facts(file, &audio)), None)),
        Inspection::Picture(picture) => {
            Ok(CheckReport::new(None, Some(image_facts(file, &picture))))
        }
        Inspection::Neither => Err(if extension_is_song {
            CommandError::audio_unreadable()
        } else {
            CommandError::image_unreadable()
        }),
    }
}

fn song_facts(file: &InputFile, context: &Context) -> Result<AudioFacts, CommandError> {
    match inspect(file, context)? {
        Inspection::Audio(audio) => Ok(audio_facts(file, &audio)),
        Inspection::Picture(_) | Inspection::Neither => Err(CommandError::audio_unreadable()),
    }
}

fn picture_facts(file: &InputFile, context: &Context) -> Result<ImageFacts, CommandError> {
    match inspect(file, context)? {
        Inspection::Picture(picture) => Ok(image_facts(file, &picture)),
        Inspection::Audio(_) | Inspection::Neither => Err(CommandError::image_unreadable()),
    }
}

fn audio_facts(file: &InputFile, audio: &AudioStream) -> AudioFacts {
    AudioFacts {
        name: file.name(),
        duration: audio.duration,
        sample_rate: audio.sample_rate,
        channels: audio.channels,
    }
}

fn image_facts(file: &InputFile, picture: &Picture) -> ImageFacts {
    ImageFacts {
        name: file.name(),
        size: picture.size(),
    }
}

/// What a file is, by its contents. A folder or device is neither.
fn inspect(file: &InputFile, context: &Context) -> Result<Inspection, CommandError> {
    let Some(path) = file.path_for_tools() else {
        return Ok(Inspection::Neither);
    };
    let tools = context.tools().ok_or_else(CommandError::tools_missing)?;
    let cancel: CancelToken = CancelToken::new();
    media::inspect(tools, &path, &cancel).map_err(|error: MediaError| -> CommandError {
        match error {
            MediaError::ToolUnavailable => CommandError::tools_missing(),
            MediaError::Cancelled => CommandError::cancelled(),
        }
    })
}

impl CommandError {
    /// A usage problem as an error: the message, a known suggestion if there is one, and where to
    /// get help.
    pub fn from_usage(problem: &UsageProblem) -> CommandError {
        let mut text: String = format!(
            "{} Run '{}'.",
            problem.message,
            problem.scope.help_command()
        );
        if let Some(suggestion) = &problem.suggestion {
            text.push_str(&format!(" Did you mean {suggestion}?"));
        }
        CommandError {
            code: ErrorCode::Usage,
            message: text,
        }
    }

    /// FFmpeg and FFprobe are not beside this program.
    pub fn tools_missing() -> CommandError {
        CommandError::new(
            ErrorCode::ExportFailed,
            "The helper programs are missing from this copy of Song2Vid.",
        )
    }
}
