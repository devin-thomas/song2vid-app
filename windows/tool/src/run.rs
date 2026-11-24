//! The command: reads the command line, decides what to run, and returns what it wrote and how it
//! ended. The program's `main` only passes its arguments here and writes the result.

use crate::check;
use crate::context::Context;
use crate::error::{status, CommandError, CommandOutput, ErrorCode};
use crate::help::help_text;
use crate::make;
use crate::make_options::MakeOptions;
use crate::options::{
    parse, Argument, CommandName, CommandOption, CommandScope, ParsedCommandLine, UsageProblem,
};
use crate::preview;
use crate::skill;
use crate::update;
use crate::{REPOSITORY_URL, VERSION};

/// Runs the command with the arguments that follow its name.
pub fn run(arguments: &[Argument], context: &Context) -> CommandOutput {
    // Every argument is checked before any is acted on, so a typo never runs half a command.
    let line: ParsedCommandLine = match parse(arguments) {
        Ok(line) => line,
        Err(problem) => return usage_failure(&problem),
    };
    let Some(command) = line.command else {
        return run_global(&line, context);
    };
    if line.has(CommandOption::Help) {
        return CommandOutput::success(String::from(help_text(command.scope())));
    }
    match command {
        CommandName::Check => check::run(&line.operands, line.has(CommandOption::Json), context),
        CommandName::Make => match MakeOptions::resolve(&line) {
            Err(problem) => usage_failure(&problem),
            Ok(options) => make::run(&options, context),
        },
        CommandName::Encoders => {
            if line.operands.is_empty() {
                not_built_yet(line.has(CommandOption::Json))
            } else {
                let problem: UsageProblem = UsageProblem::new(
                    "encoders takes no files.",
                    CommandScope::Encoders,
                    line.has(CommandOption::Json),
                );
                usage_failure(&problem)
            }
        }
        CommandName::Preview => preview::run(&line, context),
    }
}

fn usage_failure(problem: &UsageProblem) -> CommandOutput {
    CommandOutput::failure(&CommandError::from_usage(problem), problem.json_requested)
}

/// `encoders` is written in S2V-027. Until then it says so, with the export failure status, so
/// nothing mistakes it for an answer.
fn not_built_yet(json: bool) -> CommandOutput {
    let error: CommandError = CommandError::new(
        ErrorCode::ExportFailed,
        "This build of song2vid.exe can't make videos yet.",
    );
    CommandOutput::failure(&error, json)
}

/// The options that stand on their own: help, version, repo, skill, update.
fn run_global(line: &ParsedCommandLine, context: &Context) -> CommandOutput {
    // `--json` goes only with `--update`; every other global option stands alone.
    let json: bool = line.has(CommandOption::Json);
    let options: Vec<CommandOption> = line
        .options
        .iter()
        .map(|parsed: &crate::options::ParsedOption| -> CommandOption { parsed.option })
        .filter(|option: &CommandOption| -> bool { *option != CommandOption::Json })
        .collect();
    let single: Option<CommandOption> = if options.len() == 1 {
        Some(options[0])
    } else {
        None
    };
    let Some(option) = single
        .filter(|option: &CommandOption| -> bool { !json || *option == CommandOption::Update })
    else {
        let message: &str = if json && options.len() == 1 {
            "That option does not apply here."
        } else {
            "Use one option at a time."
        };
        return usage_failure(&UsageProblem::new(message, CommandScope::Global, json));
    };
    match option {
        CommandOption::Help => {
            CommandOutput::success(String::from(help_text(CommandScope::Global)))
        }
        CommandOption::Version => CommandOutput::success(format!("song2vid {VERSION}\n")),
        CommandOption::Repo => CommandOutput::success(format!("{REPOSITORY_URL}\n")),
        CommandOption::Skill => skill::run(),
        CommandOption::Update => update::run(json, &context.environment),
        // The other options belong to commands, so the parser never lets them get here.
        CommandOption::Json
        | CommandOption::Shape
        | CommandOption::Resolution
        | CommandOption::Crop
        | CommandOption::Out
        | CommandOption::Overwrite
        | CommandOption::DryRun
        | CommandOption::Quiet
        | CommandOption::Codec
        | CommandOption::CancelOnEof => CommandOutput {
            stdout: String::new(),
            stderr: String::new(),
            status: status::USAGE,
        },
    }
}
