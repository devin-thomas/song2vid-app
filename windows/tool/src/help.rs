//! The help texts (SPEC section 14.2: what the command does, usage, examples, exit statuses).
//!
//! They are the Mac command's own output, saved byte for byte in `help/`, so the two commands
//! print the same help. The Windows check compares them with the Mac command's.

use crate::options::CommandScope;

/// The help text for a scope.
pub fn help_text(scope: CommandScope) -> &'static str {
    match scope {
        CommandScope::Global => include_str!("help/global.txt"),
        CommandScope::Check => include_str!("help/check.txt"),
        CommandScope::Make => include_str!("help/make.txt"),
        CommandScope::Encoders => include_str!("help/encoders.txt"),
        CommandScope::Preview => include_str!("help/preview.txt"),
    }
}
