//! `song2vid make <audio> <image> [options]` (SPEC sections 14.4 and 26.3): checks everything,
//! then makes the video with FFmpeg and publishes it in one step.
//!
//! The order of the checks is the Mac command's, so the same mistake gives the same error on both:
//! the files (missing, then unreadable), the size for Original, the output name and place, the
//! Codec. Nothing is written until all of them pass. The video is made in a temporary file beside
//! the final name and moved into place at the end, so a half-made video never has the final name
//! and a cancel leaves nothing.

use std::path::{Path, PathBuf};

use crate::cancel::{CancelSignals, CancelToken};
use crate::context::Context;
use crate::destination::{Destination, TemporaryFile};
use crate::encode::{self, Failure, Files, Job};
use crate::encoder::{self, Encoder};
use crate::error::{CommandError, CommandOutput};
use crate::frame::{FrameError, OutputFrame};
use crate::inputs::InputFile;
use crate::make_options::MakeOptions;
use crate::make_report::MakeReport;
use crate::media::{self, AudioStream, Inspection, MediaError, Picture};
use crate::process::Tools;
use crate::progress::{Display, Reporter, Stage};

pub fn run(options: &MakeOptions, context: &Context) -> CommandOutput {
    let signals: CancelSignals = CancelSignals::start(options.cancel_on_eof);
    let token: CancelToken = signals.token();
    // A dry run and --quiet show no progress; with --json the result or error line still comes.
    let mut reporter: Reporter = if options.quiet || options.dry_run {
        Reporter::silent()
    } else {
        Reporter::showing(Display::choose(
            options.json,
            context.streams(),
            context.environment.no_color,
            context.environment.dumb_terminal,
        ))
    };
    let outcome: Result<MakeReport, CommandError> =
        execute(options, context, &token, &mut reporter);
    // The live line is wiped before the result takes its place.
    reporter.close();
    match outcome {
        Ok(report) => CommandOutput::success(if options.json {
            report.json_value().line()
        } else {
            report.text()
        }),
        // A cancel that arrives while something else fails is still a cancel.
        Err(error) => CommandOutput::failure(
            &if signals.is_requested() {
                CommandError::cancelled()
            } else {
                error
            },
            options.json,
        ),
    }
}

fn execute(
    options: &MakeOptions,
    context: &Context,
    cancel: &CancelToken,
    reporter: &mut Reporter,
) -> Result<MakeReport, CommandError> {
    check_cancel(cancel)?;
    reporter.stage(Stage::Checking);

    // 1. Validate everything first: the files, the size for Original, the output, the Codec.
    // Nothing is written until all pass.
    let audio_file: InputFile = InputFile::new(&options.audio.raw);
    let image_file: InputFile = InputFile::new(&options.image.raw);
    if !audio_file.exists() {
        return Err(CommandError::audio_not_found());
    }
    if !image_file.exists() {
        return Err(CommandError::image_not_found());
    }
    let tools: &Tools = context.tools().ok_or_else(CommandError::tools_missing)?;
    let (audio_path, audio): (PathBuf, AudioStream) = read_song(&audio_file, tools, cancel)?;
    let (image_path, picture): (PathBuf, Picture) = read_picture(&image_file, tools, cancel)?;
    let frame: OutputFrame = OutputFrame::new(
        picture.size(),
        options.shape,
        options.resolution,
        options.crop,
    )
    .map_err(|_error: FrameError| -> CommandError { CommandError::image_too_small() })?;

    let output_path: PathBuf = match &options.output {
        Some(given) => PathBuf::from(&given.raw),
        None => default_output(&audio_file),
    };
    let name: String = output_path
        .file_name()
        .map(|name: &std::ffi::OsStr| -> String { name.to_string_lossy().into_owned() })
        .unwrap_or_default();
    if name.chars().count() <= 4 || !name.to_lowercase().ends_with(".mp4") {
        return Err(CommandError::output_not_mp4());
    }
    let destination: Destination = Destination::plan(
        &output_path,
        &[audio_file.given.as_path(), image_file.given.as_path()],
        options.overwrite,
    )?;
    check_cancel(cancel)?;
    let encoder: Encoder = encoder::choose(options.codec, &context.environment)?;
    check_cancel(cancel)?;

    let mut report: MakeReport = MakeReport {
        output_name: destination.name.clone(),
        frame,
        shape: options.shape,
        codec: options.codec,
        encoder,
        encoder_fallback: false,
        duration: audio.duration,
        bytes: None,
        dry_run: options.dry_run,
    };
    // 2. A dry run says what would be made and stops.
    if options.dry_run {
        return Ok(report);
    }

    // 3. Make it in a temporary file beside the output. The working files go the same way, and
    // all three are removed when they go out of scope, whatever the way out.
    reporter.stage(Stage::Preparing);
    reporter.set_encoder(encoder.json_name());
    let mut temporary: TemporaryFile = destination.create_temporary()?;
    let mut still: TemporaryFile = destination.create_scratch("still")?;
    let mut group: TemporaryFile = destination.create_scratch("group")?;
    // FFmpeg writes these, so they are closed here.
    temporary.finish();
    still.finish();
    group.finish();
    let still_path: PathBuf = plain_path(still.path());
    let group_path: PathBuf = plain_path(group.path());
    let temporary_path: PathBuf = plain_path(temporary.path());
    let job: Job = Job {
        tools,
        picture_path: &image_path,
        picture: &picture,
        audio_path: &audio_path,
        audio: &audio,
        frame: &report.frame,
        codec: options.codec,
        encoder,
    };
    let files: Files = Files {
        still: &still_path,
        group: &group_path,
        output: &temporary_path,
    };
    let mut on_fraction = |fraction: f64| -> () { reporter.encoding(fraction) };
    encode::make(&job, &files, cancel, &mut on_fraction).map_err(
        |failure: Failure| -> CommandError {
            match failure {
                Failure::Cancelled => CommandError::cancelled(),
                Failure::ToolsMissing => CommandError::tools_missing(),
                Failure::DiskFull => CommandError::disk_full(),
                Failure::Failed => CommandError::export_failed(),
            }
        },
    )?;
    drop(still);
    drop(group);

    // 4. Only now is the final name touched: --overwrite replaces an old file here, and without
    // it a file that appeared during the run is an error and the new video is deleted.
    reporter.stage(Stage::Finishing);
    check_cancel(cancel)?;
    destination.place(&mut temporary, options.overwrite)?;
    let size: i64 = std::fs::metadata(destination.path())
        .ok()
        .and_then(|found: std::fs::Metadata| -> Option<i64> { i64::try_from(found.len()).ok() })
        .unwrap_or(0);
    report.bytes = Some(size);
    Ok(report)
}

/// The song's facts and the path FFmpeg opens it by. Missing is status 1, so only unreadable
/// comes from here.
fn read_song(
    file: &InputFile,
    tools: &Tools,
    cancel: &CancelToken,
) -> Result<(PathBuf, AudioStream), CommandError> {
    let path: PathBuf = file
        .path_for_tools()
        .ok_or_else(CommandError::audio_unreadable)?;
    match inspect(tools, &path, cancel)? {
        Inspection::Audio(audio) => Ok((path, audio)),
        Inspection::Picture(_) | Inspection::Neither => Err(CommandError::audio_unreadable()),
    }
}

fn read_picture(
    file: &InputFile,
    tools: &Tools,
    cancel: &CancelToken,
) -> Result<(PathBuf, Picture), CommandError> {
    let path: PathBuf = file
        .path_for_tools()
        .ok_or_else(CommandError::image_unreadable)?;
    match inspect(tools, &path, cancel)? {
        Inspection::Picture(picture) => Ok((path, picture)),
        Inspection::Audio(_) | Inspection::Neither => Err(CommandError::image_unreadable()),
    }
}

fn inspect(tools: &Tools, path: &Path, cancel: &CancelToken) -> Result<Inspection, CommandError> {
    media::inspect(tools, path, cancel).map_err(|error: MediaError| -> CommandError {
        match error {
            MediaError::ToolUnavailable => CommandError::tools_missing(),
            MediaError::Cancelled => CommandError::cancelled(),
        }
    })
}

/// The output when none is given: the song's name with `.mp4`, in the current folder.
fn default_output(audio: &InputFile) -> PathBuf {
    let stem: String = audio
        .given
        .file_stem()
        .map(|stem: &std::ffi::OsStr| -> String { stem.to_string_lossy().into_owned() })
        .unwrap_or_default();
    PathBuf::from(format!("{stem}.mp4"))
}

/// A path as FFmpeg is given it: written the usual way unless it is too long for that.
fn plain_path(path: &Path) -> PathBuf {
    crate::inputs::shortest_form(path.to_path_buf())
}

fn check_cancel(cancel: &CancelToken) -> Result<(), CommandError> {
    if cancel.is_requested() {
        Err(CommandError::cancelled())
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::OsStr;

    #[test]
    fn the_default_output_is_the_songs_name_with_mp4() {
        let named = |text: &str| -> PathBuf { default_output(&InputFile::new(OsStr::new(text))) };
        assert_eq!(named("folder/song.wav"), PathBuf::from("song.mp4"));
        assert_eq!(
            named("My Song.final.flac"),
            PathBuf::from("My Song.final.mp4")
        );
        assert_eq!(named("noextension"), PathBuf::from("noextension.mp4"));
    }
}
