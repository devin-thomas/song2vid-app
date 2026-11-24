//! `song2vid --skill` (SPEC section 14.2): prints the agent skill that ships with the command, byte
//! for byte. The file is `SKILL.md`, in the same folder as the program.

use std::fs;

use crate::error::{CommandError, CommandOutput, ErrorCode};

const SKILL_FILE: &str = "SKILL.md";

fn unavailable() -> CommandError {
    CommandError::new(
        ErrorCode::ExportFailed,
        "The agent skill is missing from this copy of Song2Vid.",
    )
}

pub fn run() -> CommandOutput {
    let path = match std::env::current_exe() {
        Ok(executable) => executable.with_file_name(SKILL_FILE),
        Err(_) => return CommandOutput::failure(&unavailable(), false),
    };
    match fs::read_to_string(path) {
        Ok(text) => CommandOutput::success(text),
        Err(_) => CommandOutput::failure(&unavailable(), false),
    }
}
