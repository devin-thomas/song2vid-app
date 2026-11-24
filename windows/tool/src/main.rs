//! `song2vid.exe`. It passes its arguments to the library and writes what comes back.

use std::io::Write;
use std::process::ExitCode;

use song2vid::process::Tools;
use song2vid::{Argument, Context, Environment};

fn main() -> ExitCode {
    let arguments: Vec<Argument> = std::env::args_os().skip(1).map(Argument::new).collect();
    let context: Context = Context::new(Environment::from_process(), Tools::beside_executable());
    let output = song2vid::run(&arguments, &context);
    // A closed pipe is not an error worth a message: the reader has what it wanted.
    let _ = std::io::stdout().write_all(output.stdout.as_bytes());
    let _ = std::io::stdout().flush();
    let _ = std::io::stderr().write_all(output.stderr.as_bytes());
    let _ = std::io::stderr().flush();
    ExitCode::from(u8::try_from(output.status).unwrap_or(1))
}
