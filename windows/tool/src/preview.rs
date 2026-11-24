//! `song2vid preview <image> -o <file.png> [-w] [-j] [-E]` (SPEC section 24.3): writes the image as
//! the video will see it, with its orientation applied, transparency made black, and scaled to fit
//! within 2048 by 2048 if it is larger (never enlarged).

use std::path::PathBuf;

use crate::cancel::{CancelSignals, CancelToken};
use crate::context::Context;
use crate::destination::{Destination, TemporaryFile};
use crate::error::{CommandError, CommandOutput};
use crate::frame::PixelSize;
use crate::inputs::InputFile;
use crate::json::{JsonKey, JsonValue};
use crate::media::{self, Inspection, MediaError, Picture, PreviewFailure};
use crate::options::{Argument, CommandOption, CommandScope, ParsedCommandLine, UsageProblem};

pub fn run(line: &ParsedCommandLine, context: &Context) -> CommandOutput {
    let json: bool = line.has(CommandOption::Json);
    let out: Option<&Argument> = line
        .value_of(CommandOption::Out)
        .filter(|value: &&Argument| -> bool { !value.raw.is_empty() });
    let (Some(out), [image]) = (out, line.operands.as_slice()) else {
        return usage(
            "preview needs one image file and an output file (-o).",
            json,
        );
    };
    let output: PathBuf = PathBuf::from(&out.raw);
    let name: String = output
        .file_name()
        .map(|name: &std::ffi::OsStr| -> String { name.to_string_lossy().into_owned() })
        .unwrap_or_default();
    if name.chars().count() <= 4 || !name.to_lowercase().ends_with(".png") {
        return usage("The preview output file name must end in .png.", json);
    }

    let signals: CancelSignals = CancelSignals::start(line.has(CommandOption::CancelOnEof));
    let token: CancelToken = signals.token();
    match write(
        &InputFile::new(&image.raw),
        &output,
        line.has(CommandOption::Overwrite),
        json,
        context,
        &token,
    ) {
        Ok(output) => output,
        // A cancel that arrives while something else fails is still a cancel.
        Err(error) => {
            let reported: CommandError = if signals.is_requested() {
                CommandError::cancelled()
            } else {
                error
            };
            CommandOutput::failure(&reported, json)
        }
    }
}

fn usage(message: &str, json: bool) -> CommandOutput {
    let problem: UsageProblem = UsageProblem::new(message, CommandScope::Preview, json);
    CommandOutput::failure(&CommandError::from_usage(&problem), json)
}

fn write(
    image: &InputFile,
    output: &std::path::Path,
    overwrite: bool,
    json: bool,
    context: &Context,
    cancel: &CancelToken,
) -> Result<CommandOutput, CommandError> {
    check_cancel(cancel)?;
    if !image.exists() {
        return Err(CommandError::image_not_found());
    }
    let path: PathBuf = image
        .path_for_tools()
        .ok_or_else(CommandError::image_unreadable)?;
    let tools = context.tools().ok_or_else(CommandError::tools_missing)?;
    let picture: Picture = match media::inspect(tools, &path, cancel) {
        Ok(Inspection::Picture(picture)) => picture,
        Ok(Inspection::Audio(_) | Inspection::Neither) => {
            return Err(CommandError::image_unreadable())
        }
        Err(MediaError::Cancelled) => return Err(CommandError::cancelled()),
        Err(MediaError::ToolUnavailable) => return Err(CommandError::tools_missing()),
    };
    check_cancel(cancel)?;

    let png: Vec<u8> = media::render_preview(tools, &path, &picture, cancel).map_err(
        |failure: PreviewFailure| -> CommandError {
            match failure {
                PreviewFailure::Cancelled => CommandError::cancelled(),
                PreviewFailure::ToolUnavailable => CommandError::tools_missing(),
                PreviewFailure::Unreadable => CommandError::image_unreadable(),
            }
        },
    )?;
    check_cancel(cancel)?;

    let destination: Destination = Destination::plan(output, &[image.given.as_path()], overwrite)?;
    let mut temporary: TemporaryFile = destination.create_temporary()?;
    temporary.write_all(&png)?;
    check_cancel(cancel)?;
    destination.place(&mut temporary, overwrite)?;

    let size: PixelSize = media::preview_size(picture.size());
    let source: PixelSize = picture.size();
    let result: JsonValue = JsonValue::line_of_type(
        "result",
        vec![
            (JsonKey::Command, JsonValue::String(String::from("preview"))),
            (
                JsonKey::Output,
                JsonValue::Object(vec![
                    (JsonKey::Name, JsonValue::String(destination.name.clone())),
                    (JsonKey::Width, JsonValue::Int(size.width)),
                    (JsonKey::Height, JsonValue::Int(size.height)),
                ]),
            ),
            (
                JsonKey::Source,
                JsonValue::Object(vec![
                    (JsonKey::Width, JsonValue::Int(source.width)),
                    (JsonKey::Height, JsonValue::Int(source.height)),
                ]),
            ),
        ],
    );
    Ok(CommandOutput::success(if json {
        result.line()
    } else {
        format!(
            "Saved {} ({}x{}).\n",
            destination.name, size.width, size.height
        )
    }))
}

fn check_cancel(cancel: &CancelToken) -> Result<(), CommandError> {
    if cancel.is_requested() {
        Err(CommandError::cancelled())
    } else {
        Ok(())
    }
}
