//! The command line's grammar (SPEC section 14.2 and 24), as data.
//!
//! Each option is one row in `OPTION_TABLE`: its short form, long form, the places it is allowed and
//! whether it takes a value. Adding a command or an option means adding a case and a row; the
//! parser does not change. This is the Mac command's `CommandParser`, argument for argument.

use std::ffi::OsString;

/// The commands that come first on the command line.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CommandName {
    Check,
    Make,
    Encoders,
    Preview,
}

impl CommandName {
    fn from_word(word: &str) -> Option<CommandName> {
        match word {
            "check" => Some(CommandName::Check),
            "make" => Some(CommandName::Make),
            "encoders" => Some(CommandName::Encoders),
            "preview" => Some(CommandName::Preview),
            _ => None,
        }
    }

    /// Where the options after this command are read.
    pub fn scope(self) -> CommandScope {
        match self {
            CommandName::Check => CommandScope::Check,
            CommandName::Make => CommandScope::Make,
            CommandName::Encoders => CommandScope::Encoders,
            CommandName::Preview => CommandScope::Preview,
        }
    }
}

/// Where an option is being read: with no command (the global options), or after a command's name.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CommandScope {
    Global,
    Check,
    Make,
    Encoders,
    Preview,
}

impl CommandScope {
    /// The command that prints help for this scope, as the usage errors name it.
    pub fn help_command(self) -> &'static str {
        match self {
            CommandScope::Global => "song2vid --help",
            CommandScope::Check => "song2vid check --help",
            CommandScope::Make => "song2vid make --help",
            CommandScope::Encoders => "song2vid encoders --help",
            CommandScope::Preview => "song2vid preview --help",
        }
    }
}

/// The options the command knows.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CommandOption {
    Help,
    Version,
    Repo,
    Skill,
    Update,
    Json,
    Shape,
    Resolution,
    Crop,
    Out,
    Overwrite,
    DryRun,
    Quiet,
    Codec,
    CancelOnEof,
}

/// One option: how it is spelled, where it applies and whether a value follows it.
pub struct OptionSpec {
    pub option: CommandOption,
    pub short: &'static str,
    pub long: &'static str,
    pub scopes: &'static [CommandScope],
    pub takes_value: bool,
}

impl OptionSpec {
    fn applies_in(&self, scope: CommandScope) -> bool {
        self.scopes.contains(&scope)
    }

    fn is_spelled(&self, argument: &str) -> bool {
        argument == self.short || argument == self.long
    }
}

const ANY_SCOPE: &[CommandScope] = &[
    CommandScope::Global,
    CommandScope::Check,
    CommandScope::Make,
    CommandScope::Encoders,
    CommandScope::Preview,
];

/// Every option the command knows (SPEC sections 14.2, 24.1 and 24.4).
pub const OPTION_TABLE: [OptionSpec; 15] = [
    OptionSpec {
        option: CommandOption::Help,
        short: "-h",
        long: "--help",
        scopes: ANY_SCOPE,
        takes_value: false,
    },
    OptionSpec {
        option: CommandOption::Version,
        short: "-v",
        long: "--version",
        scopes: &[CommandScope::Global],
        takes_value: false,
    },
    OptionSpec {
        option: CommandOption::Repo,
        short: "-R",
        long: "--repo",
        scopes: &[CommandScope::Global],
        takes_value: false,
    },
    OptionSpec {
        option: CommandOption::Skill,
        short: "-S",
        long: "--skill",
        scopes: &[CommandScope::Global],
        takes_value: false,
    },
    OptionSpec {
        option: CommandOption::Update,
        short: "-u",
        long: "--update",
        scopes: &[CommandScope::Global],
        takes_value: false,
    },
    OptionSpec {
        option: CommandOption::Json,
        short: "-j",
        long: "--json",
        scopes: ANY_SCOPE,
        takes_value: false,
    },
    OptionSpec {
        option: CommandOption::Shape,
        short: "-s",
        long: "--shape",
        scopes: &[CommandScope::Make],
        takes_value: true,
    },
    OptionSpec {
        option: CommandOption::Resolution,
        short: "-r",
        long: "--resolution",
        scopes: &[CommandScope::Make],
        takes_value: true,
    },
    OptionSpec {
        option: CommandOption::Crop,
        short: "-c",
        long: "--crop",
        scopes: &[CommandScope::Make],
        takes_value: true,
    },
    OptionSpec {
        option: CommandOption::Out,
        short: "-o",
        long: "--out",
        scopes: &[CommandScope::Make, CommandScope::Preview],
        takes_value: true,
    },
    OptionSpec {
        option: CommandOption::Overwrite,
        short: "-w",
        long: "--overwrite",
        scopes: &[CommandScope::Make, CommandScope::Preview],
        takes_value: false,
    },
    OptionSpec {
        option: CommandOption::DryRun,
        short: "-n",
        long: "--dry-run",
        scopes: &[CommandScope::Make],
        takes_value: false,
    },
    OptionSpec {
        option: CommandOption::Codec,
        short: "-C",
        long: "--codec",
        scopes: &[CommandScope::Make],
        takes_value: true,
    },
    OptionSpec {
        option: CommandOption::CancelOnEof,
        short: "-E",
        long: "--cancel-on-eof",
        scopes: &[CommandScope::Make, CommandScope::Preview],
        takes_value: false,
    },
    OptionSpec {
        option: CommandOption::Quiet,
        short: "-q",
        long: "--quiet",
        scopes: &[CommandScope::Make],
        takes_value: false,
    },
];

/// One word of the command line. `text` is how it reads for matching options; `raw` is the exact
/// value Windows passed, kept for file names, which may hold characters that are not valid text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Argument {
    pub raw: OsString,
    pub text: String,
}

impl Argument {
    pub fn new(raw: OsString) -> Argument {
        let text: String = raw.to_string_lossy().into_owned();
        Argument { raw, text }
    }
}

/// An option as the person gave it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ParsedOption {
    pub option: CommandOption,
    pub value: Option<Argument>,
}

/// A command line that follows the grammar.
#[derive(Clone, Debug)]
pub struct ParsedCommandLine {
    /// None when only global options were given.
    pub command: Option<CommandName>,
    pub options: Vec<ParsedOption>,
    /// The words that are not options: the files after a command.
    pub operands: Vec<Argument>,
}

impl ParsedCommandLine {
    pub fn has(&self, option: CommandOption) -> bool {
        self.options
            .iter()
            .any(|parsed: &ParsedOption| -> bool { parsed.option == option })
    }

    /// The value given to an option that takes one, if it was given.
    pub fn value_of(&self, option: CommandOption) -> Option<&Argument> {
        self.options
            .iter()
            .find(|parsed: &&ParsedOption| -> bool { parsed.option == option })
            .and_then(|parsed: &ParsedOption| -> Option<&Argument> { parsed.value.as_ref() })
    }
}

/// A command line that breaks the grammar. The message is fixed text: nothing the person typed is
/// in it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UsageProblem {
    pub message: String,
    /// A known option name close to what was typed, never the typed text itself.
    pub suggestion: Option<String>,
    pub scope: CommandScope,
    /// True when `--json` was given in a place where it applies, so the problem is a JSON line.
    pub json_requested: bool,
}

impl UsageProblem {
    pub fn new(message: &str, scope: CommandScope, json_requested: bool) -> UsageProblem {
        UsageProblem {
            message: String::from(message),
            suggestion: None,
            scope,
            json_requested,
        }
    }
}

/// Reads the arguments that follow the command's own name. Short options are never combined (`-wn`
/// is not `-w -n`), and an option's value is the next argument or follows `=` in the long form.
pub fn parse(arguments: &[Argument]) -> Result<ParsedCommandLine, UsageProblem> {
    let Some(first) = arguments.first() else {
        return Err(UsageProblem::new(
            "Missing command.",
            CommandScope::Global,
            false,
        ));
    };
    let mut command: Option<CommandName> = None;
    let mut rest: &[Argument] = arguments;
    if !first.text.starts_with('-') {
        let Some(named) = CommandName::from_word(&first.text) else {
            return Err(UsageProblem::new(
                "Unknown command.",
                CommandScope::Global,
                false,
            ));
        };
        command = Some(named);
        rest = &arguments[1..];
    }
    let scope: CommandScope = command.map_or(CommandScope::Global, CommandName::scope);
    let in_scope: Vec<&OptionSpec> = OPTION_TABLE
        .iter()
        .filter(|spec: &&OptionSpec| -> bool { spec.applies_in(scope) })
        .collect();
    let wants_json: bool = rest.iter().any(|argument: &Argument| -> bool {
        in_scope.iter().any(|spec: &&OptionSpec| -> bool {
            spec.option == CommandOption::Json && spec.is_spelled(&argument.text)
        })
    });
    let problem = |message: &str, suggestion: Option<String>| -> UsageProblem {
        UsageProblem {
            message: String::from(message),
            suggestion,
            scope,
            json_requested: wants_json,
        }
    };

    let mut options: Vec<ParsedOption> = Vec::new();
    let mut operands: Vec<Argument> = Vec::new();
    let mut remaining: &[Argument] = rest;
    while let Some((argument, after)) = remaining.split_first() {
        remaining = after;
        if !argument.text.starts_with('-') {
            // A word with no command in front of it is a command that does not exist.
            if command.is_none() {
                return Err(problem("Unknown command.", None));
            }
            operands.push(argument.clone());
            continue;
        }
        let (name, attached): (&str, Option<&str>) = split_attached_value(&argument.text);
        let found: Option<&OptionSpec> = OPTION_TABLE.iter().find(|spec: &&OptionSpec| -> bool {
            spec.is_spelled(&argument.text)
                || (spec.takes_value && attached.is_some() && spec.long == name)
        });
        let Some(spec) = found else {
            return Err(problem(
                "Unknown option.",
                suggestion(&argument.text, &in_scope),
            ));
        };
        if !spec.applies_in(scope) {
            return Err(problem("That option does not apply here.", None));
        }
        if !spec.takes_value {
            options.push(ParsedOption {
                option: spec.option,
                value: None,
            });
            continue;
        }
        // The next word is the value unless it is another option, so `-o -w` is a missing value, not a
        // file called `-w`. (A value that starts with a dash can be attached: `--out=-name.mp4`.)
        let value: Argument = if attached.is_some() {
            // The attached text is everything after the first `=` of the raw word.
            attached_argument(argument)
        } else {
            match remaining.first() {
                Some(next) if !next.text.starts_with('-') => {
                    remaining = &remaining[1..];
                    next.clone()
                }
                _ => return Err(problem("An option is missing its value.", None)),
            }
        };
        if options
            .iter()
            .any(|parsed: &ParsedOption| -> bool { parsed.option == spec.option })
        {
            return Err(problem("An option can be given only once.", None));
        }
        options.push(ParsedOption {
            option: spec.option,
            value: Some(value),
        });
    }
    Ok(ParsedCommandLine {
        command,
        options,
        operands,
    })
}

/// `--out=file` is `--out` with the value `file`. Anything else has no attached value.
fn split_attached_value(argument: &str) -> (&str, Option<&str>) {
    if !argument.starts_with("--") {
        return (argument, None);
    }
    match argument.find('=') {
        Some(index) => (&argument[..index], Some(&argument[index + 1..])),
        None => (argument, None),
    }
}

/// The value after the first `=` of a `--name=value` word, with the raw text kept for the file name.
fn attached_argument(argument: &Argument) -> Argument {
    let (_, value): (&str, Option<&str>) = split_attached_value(&argument.text);
    let text: String = String::from(value.unwrap_or(""));
    // A value that is not valid text keeps its exact form: split the raw word at its first `=`.
    let raw: OsString =
        split_raw_after_equals(&argument.raw).unwrap_or_else(|| OsString::from(&text));
    Argument { raw, text }
}

#[cfg(windows)]
fn split_raw_after_equals(raw: &OsString) -> Option<OsString> {
    use std::os::windows::ffi::{OsStrExt, OsStringExt};
    let wide: Vec<u16> = raw.encode_wide().collect();
    let index: usize = wide
        .iter()
        .position(|unit: &u16| -> bool { *unit == u16::from(b'=') })?;
    Some(OsString::from_wide(&wide[index + 1..]))
}

#[cfg(not(windows))]
fn split_raw_after_equals(raw: &OsString) -> Option<OsString> {
    use std::os::unix::ffi::{OsStrExt, OsStringExt};
    let bytes: &[u8] = raw.as_bytes();
    let index: usize = bytes
        .iter()
        .position(|byte: &u8| -> bool { *byte == b'=' })?;
    Some(OsString::from_vec(bytes[index + 1..].to_vec()))
}

/// The one known long option within two edits of what was typed, if there is exactly one.
fn suggestion(argument: &str, among: &[&OptionSpec]) -> Option<String> {
    if !argument.starts_with("--") {
        return None;
    }
    let close: Vec<&str> = among
        .iter()
        .map(|spec: &&OptionSpec| -> &str { spec.long })
        .filter(|long: &&str| -> bool { edit_distance(long, argument) <= 2 })
        .collect();
    if close.len() == 1 {
        Some(String::from(close[0]))
    } else {
        None
    }
}

/// The number of single-character edits (insert, delete, replace) between two strings.
pub fn edit_distance(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let mut previous: Vec<usize> = (0..=b.len()).collect();
    for i in 1..=a.len() {
        let mut row: Vec<usize> = vec![0; b.len() + 1];
        row[0] = i;
        for j in 1..=b.len() {
            let cost: usize = usize::from(a[i - 1] != b[j - 1]);
            row[j] = (previous[j] + 1)
                .min(row[j - 1] + 1)
                .min(previous[j - 1] + cost);
        }
        previous = row;
    }
    previous[b.len()]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn arguments(words: &[&str]) -> Vec<Argument> {
        words
            .iter()
            .map(|word: &&str| -> Argument { Argument::new(OsString::from(*word)) })
            .collect()
    }

    fn problem_of(words: &[&str]) -> UsageProblem {
        match parse(&arguments(words)) {
            Err(problem) => problem,
            Ok(_) => panic!("expected a usage problem for {words:?}"),
        }
    }

    #[test]
    fn a_command_line_with_a_command_and_options_is_read() {
        let line: ParsedCommandLine = parse(&arguments(&[
            "make",
            "a.wav",
            "b.png",
            "-s",
            "1:1",
            "--out=x.mp4",
            "-w",
        ]))
        .unwrap();
        assert_eq!(line.command, Some(CommandName::Make));
        assert_eq!(line.operands.len(), 2);
        assert_eq!(line.value_of(CommandOption::Shape).unwrap().text, "1:1");
        assert_eq!(line.value_of(CommandOption::Out).unwrap().text, "x.mp4");
        assert!(line.has(CommandOption::Overwrite));
    }

    #[test]
    fn short_options_cannot_be_clustered() {
        for word in ["-wn", "-vh", "-jj", "-hj"] {
            assert_eq!(problem_of(&["check", "a", word]).message, "Unknown option.");
        }
        assert_eq!(problem_of(&["-vh"]).message, "Unknown option.");
    }

    #[test]
    fn unknown_text_is_never_in_the_problem() {
        let problem: UsageProblem = problem_of(&["check", "a", "b", "--zzz-typed-text"]);
        assert_eq!(problem.message, "Unknown option.");
        assert_eq!(problem.suggestion, None);
        assert_eq!(problem_of(&["frobnicate"]).message, "Unknown command.");
        assert_eq!(problem_of(&[]).message, "Missing command.");
        // A bare dash and a double dash are unknown options.
        assert_eq!(problem_of(&["--"]).message, "Unknown option.");
        assert_eq!(problem_of(&["-"]).message, "Unknown option.");
    }

    #[test]
    fn a_near_miss_names_the_known_option() {
        assert_eq!(
            problem_of(&["--versoin"]).suggestion.as_deref(),
            Some("--version")
        );
        assert_eq!(
            problem_of(&["--version=2"]).suggestion.as_deref(),
            Some("--version")
        );
        assert_eq!(
            problem_of(&["--repoo"]).suggestion.as_deref(),
            Some("--repo")
        );
        assert_eq!(
            problem_of(&["check", "--jsno"]).suggestion.as_deref(),
            Some("--json")
        );
        assert_eq!(
            problem_of(&["check", "--json=1"]).suggestion.as_deref(),
            Some("--json")
        );
        // A name that is not close to any known one has no suggestion.
        assert_eq!(problem_of(&["make", "--frobnicate"]).suggestion, None);
    }

    #[test]
    fn options_outside_their_scope_do_not_apply() {
        for word in [
            "--version",
            "-v",
            "--repo",
            "-o",
            "-s",
            "-n",
            "-q",
            "--overwrite",
            "-S",
            "-u",
        ] {
            assert_eq!(
                problem_of(&["check", "a", word]).message,
                "That option does not apply here."
            );
        }
        assert_eq!(
            problem_of(&["--shape", "1:1"]).message,
            "That option does not apply here."
        );
    }

    #[test]
    fn a_value_that_looks_like_an_option_is_a_missing_value() {
        assert_eq!(
            problem_of(&["make", "a", "b", "-o", "-w"]).message,
            "An option is missing its value."
        );
        assert_eq!(
            problem_of(&["make", "a", "b", "-o"]).message,
            "An option is missing its value."
        );
        let line: ParsedCommandLine =
            parse(&arguments(&["make", "a", "b", "--out=-name.mp4"])).unwrap();
        assert_eq!(line.value_of(CommandOption::Out).unwrap().text, "-name.mp4");
    }

    #[test]
    fn an_option_can_be_given_once() {
        assert_eq!(
            problem_of(&["make", "a", "b", "-s", "1:1", "-s", "4:3"]).message,
            "An option can be given only once."
        );
    }

    #[test]
    fn json_is_requested_only_where_it_applies() {
        assert!(problem_of(&["check", "a", "b", "--nope", "--json"]).json_requested);
        assert!(problem_of(&["--nope", "-j"]).json_requested);
        assert!(!problem_of(&["check", "a", "--nope"]).json_requested);
    }

    #[test]
    fn edit_distance_counts_edits() {
        assert_eq!(edit_distance("--version", "--versoin"), 2);
        assert_eq!(edit_distance("", "abc"), 3);
        assert_eq!(edit_distance("same", "same"), 0);
    }
}
