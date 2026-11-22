import Foundation

/// What a run of the `song2vid` command wrote and how it ended.
public struct CommandOutput: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
    public var status: Int32

    public init(stdout: String = "", stderr: String = "", status: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
    }
}

/// The `song2vid` command (SPEC section 14). The command target only passes its arguments here and
/// writes the result, so everything it decides lives in this package.
///
/// The command line is read by `CommandParser` (CommandOptions.swift), each command lives in its own file,
/// and `run` joins them.
public enum Song2VidCommand {
    /// The version of the app and the command (ADR-013: one number covers both).
    public static let version = "1.1.0"
    /// Where the project lives, printed by `--repo`.
    public static let repositoryURL = "https://github.com/devin-thomas/song2vid-app"

    /// Exit statuses (SPEC section 14.6). The statuses for the commands that come later are added with them.
    public enum ExitStatus {
        public static let success: Int32 = 0
        public static let notFound: Int32 = 1
        public static let usage: Int32 = 2
        public static let unreadable: Int32 = 3
    }

    /// Runs the command with the arguments that follow its name.
    public static func run(arguments: [String]) -> CommandOutput {
        // Every argument is checked before any is acted on, so a typo never runs half a command.
        let line: ParsedCommandLine
        switch CommandParser.parse(arguments) {
        case .failure(let problem):
            return .failure(CommandError(problem), json: problem.jsonRequested)
        case .success(let parsed):
            line = parsed
        }

        guard let command = line.command else { return runGlobal(line) }
        if line.has(.help) {
            return CommandOutput(stdout: helpText(for: command.scope), status: ExitStatus.success)
        }
        switch command {
        case .check:
            return CheckCommand.run(operands: line.operands, json: line.has(.json))
        }
    }

    /// The options that stand on their own: help, version, repo.
    private static func runGlobal(_ line: ParsedCommandLine) -> CommandOutput {
        guard line.options.count == 1, let option = line.options.first?.option else {
            let problem = UsageProblem(message: "Use one option at a time.", suggestion: nil, scope: .global, jsonRequested: false)
            return .failure(CommandError(problem), json: false)
        }
        switch option {
        case .help:
            return CommandOutput(stdout: helpText(for: .global), status: ExitStatus.success)
        case .version:
            return CommandOutput(stdout: "song2vid \(version)\n", status: ExitStatus.success)
        case .repo:
            return CommandOutput(stdout: repositoryURL + "\n", status: ExitStatus.success)
        case .json:
            // --json does not apply without a command, so the parser never lets it get here.
            return CommandOutput(status: ExitStatus.usage)
        }
    }

    static func helpText(for scope: CommandScope) -> String {
        switch scope {
        case .global: globalHelpText
        case .check: checkHelpText
        }
    }

    static let globalHelpText = """
    song2vid turns one song and one image into an MP4 video.

    Usage:
      song2vid check <audio> <image> [-j]
      song2vid -h | --help       Show this help. After a command, help for that command.
      song2vid -v | --version    Print the version.
      song2vid -R | --repo       Print the project address.

    Commands:
      check    Read a song and an image and report what Song2Vid would make from them.
               Run 'song2vid check --help' for details.

    Examples:
      song2vid check song.mp3 cover.png
      song2vid check song.mp3 cover.png --json
      song2vid --version

    Exit statuses:
      0  Success.
      1  An input file does not exist.
      2  Usage error: an option or command that song2vid does not know, or a missing file.
      3  An input file can't be read or isn't usable.

    """

    static let checkHelpText = """
    song2vid check reads a song and an image and reports what Song2Vid would make from them.
    It writes nothing, and it never changes your files.

    Usage:
      song2vid check <audio> <image> [-j]

    It reports the song's length, sample rate and channels, the image's size after its
    orientation tag, and for every Frame Shape and Resolution the video's size, how the
    image is placed (fit or crop) and whether it would be enlarged. Original has one size,
    or is too small when a side of the image is under 16 pixels.

    Options:
      -j | --json    Write one JSON line (api_version "1") instead of text.
      -h | --help    Show this help.

    Examples:
      song2vid check song.mp3 cover.png
      song2vid check song.mp3 cover.png --json
      song2vid check -j song.wav photo.heic

    Exit statuses:
      0  Success.
      1  An input file does not exist (audio_not_found, image_not_found).
      2  Usage error (usage).
      3  An input file can't be read or isn't usable (audio_unreadable, image_unreadable).

    With --json, errors are a JSON line on stdout too, with the error code, and stderr is empty.

    """
}
