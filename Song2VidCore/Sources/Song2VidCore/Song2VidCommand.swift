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

/// What the command reports while it works (SPEC section 14.5). The window and the live display (S2V-013) turn
/// these into text, a bar or JSON lines; the command only says what stage it is in and how far it has got.
public struct CommandProgress: Equatable, Sendable {
    public enum Stage: String, Sendable {
        case checking, preparing, encoding, finishing
    }

    public let stage: Stage
    /// How much of the video is done, from 0 to 1, or nil while that is not known (`checking`, `preparing`).
    public let fraction: Double?
    /// The encoder name on the wire, once the encoding stage starts.
    public let encoder: String?

    public init(stage: Stage, fraction: Double?, encoder: String? = nil) {
        self.stage = stage
        self.fraction = fraction
        self.encoder = encoder
    }
}

/// Receives each progress event, with the channel to write it to. It is called from any thread, one call at a time,
/// never after the command has returned. `make --quiet` makes no calls.
public typealias CommandProgressHandler = @Sendable (CommandProgress, CommandChannel) -> Void

/// The `song2vid` command (SPEC section 14). The command target only passes its arguments here and
/// writes the result, so everything it decides lives in this package.
///
/// The command line is read by `CommandParser` (CommandOptions.swift), each command lives in its own file,
/// and `run` joins them.
public enum Song2VidCommand {
    /// The version of the app and the command (ADR-013: one number covers both).
    public static let version = "1.2.0"
    /// Where the project lives, printed by `--repo`.
    public static let repositoryURL = "https://github.com/devin-thomas/song2vid-app"

    /// Exit statuses (SPEC section 14.6). The statuses for the commands that come later are added with them.
    public enum ExitStatus {
        public static let success: Int32 = 0
        public static let notFound: Int32 = 1
        public static let usage: Int32 = 2
        public static let unreadable: Int32 = 3
        public static let outputFailed: Int32 = 4
        public static let exportFailed: Int32 = 5
        public static let cancelled: Int32 = 130
    }

    /// Runs the command with the arguments that follow its name.
    public static func run(arguments: [String], progress: CommandProgressHandler? = nil) -> CommandOutput {
        run(arguments: arguments, mode: progress.map { .handler($0) } ?? .none, environment: [:])
    }

    /// Runs the command and shows progress as SPEC section 14.5 describes: a live line in a terminal, plain lines
    /// when output is going to a file or pipe, JSON Lines with `--json`. `environment` is where `NO_COLOR` and
    /// `TERM` are read from.
    public static func run(arguments: [String], environment: [String: String]) -> CommandOutput {
        run(arguments: arguments, mode: .display(environment: environment), environment: environment)
    }

    private static func run(arguments: [String], mode: ProgressMode, environment: [String: String]) -> CommandOutput {
        // Every argument is checked before any is acted on, so a typo never runs half a command.
        let line: ParsedCommandLine
        switch CommandParser.parse(arguments) {
        case .failure(let problem):
            return .failure(CommandError(problem), json: problem.jsonRequested)
        case .success(let parsed):
            line = parsed
        }

        guard let command = line.command else { return runGlobal(line, environment: environment) }
        if line.has(.help) {
            return CommandOutput(stdout: helpText(for: command.scope), status: ExitStatus.success)
        }
        switch command {
        case .check:
            return CheckCommand.run(operands: line.operands, json: line.has(.json))
        case .make:
            switch MakeOptions.resolve(line) {
            case .failure(let problem): return .failure(CommandError(problem), json: problem.jsonRequested)
            case .success(let options): return MakeCommand.run(options, environment: environment, progress: mode)
            }
        case .encoders:
            return EncodersCommand.run(line, environment: environment)
        case .preview:
            return PreviewCommand.run(line)
        }
    }

    /// The options that stand on their own: help, version, repo, skill, update.
    private static func runGlobal(_ line: ParsedCommandLine, environment: [String: String]) -> CommandOutput {
        // `--json` goes only with `--update`; every other global option stands alone.
        let json = line.has(.json)
        let options = line.options.map(\.option).filter { $0 != .json }
        guard options.count == 1, let option = options.first, !json || option == .update else {
            let problem = UsageProblem(
                message: json && options.count == 1 ? "That option does not apply here." : "Use one option at a time.",
                suggestion: nil, scope: .global, jsonRequested: json
            )
            return .failure(CommandError(problem), json: json)
        }
        switch option {
        case .help:
            return CommandOutput(stdout: helpText(for: .global), status: ExitStatus.success)
        case .version:
            return CommandOutput(stdout: "song2vid \(version)\n", status: ExitStatus.success)
        case .repo:
            return CommandOutput(stdout: repositoryURL + "\n", status: ExitStatus.success)
        case .skill:
            return SkillCommand.run()
        case .update:
            return UpdateCommand.run(json: json, environment: environment)
        default:
            // The other options belong to commands, so the parser never lets them get here.
            return CommandOutput(status: ExitStatus.usage)
        }
    }

    static func helpText(for scope: CommandScope) -> String {
        switch scope {
        case .global: globalHelpText
        case .check: checkHelpText
        case .make: makeHelpText
        case .encoders: encodersHelpText
        case .preview: previewHelpText
        }
    }

    static let globalHelpText = """
    song2vid turns one song and one image into an MP4 video.

    Usage:
      song2vid check <audio> <image> [-j]
      song2vid check <file> [-j]
      song2vid make  <audio> <image> [-o <file.mp4>] [-s <shape>] [-r <resolution>] [-c <h,v>] [-C <codec>] [-w] [-n] [-j] [-q] [-E]
      song2vid encoders [-j]
      song2vid preview <image> -o <file.png> [-w] [-j] [-E]
      song2vid -h | --help       Show this help. After a command, help for that command.
      song2vid -v | --version    Print the version.
      song2vid -S | --skill      Print the agent skill: how an agent makes a video with Song2Vid.
      song2vid -R | --repo       Print the project address.
      song2vid -u | --update [-j]
                                 Say whether a newer Song2Vid is out. It downloads and changes nothing.

    Commands:
      check    Read a song and an image, or one file alone, and report what Song2Vid would make from them.
               Run 'song2vid check --help' for details.
      make     Make the video from a song and an image. Never replaces a file unless told to.
               Run 'song2vid make --help' for details.
      encoders Report which Codecs this computer can make.
               Run 'song2vid encoders --help' for details.
      preview  Save an oriented, scaled PNG from an image.
               Run 'song2vid preview --help' for details.

    Examples:
      song2vid check song.mp3 cover.png
      song2vid check song.mp3 cover.png --json
      song2vid make song.mp3 cover.png
      song2vid make song.mp3 cover.png -s 1:1 -r 480p -o preview.mp4 --json
      song2vid --version
      song2vid --update --json

    Exit statuses:
      0  Success.
      1  An input file does not exist.
      2  Usage error: an option or command that song2vid does not know, or a missing file.
      3  An input file can't be read or isn't usable, or the chosen Codec is unavailable.
      4  The output can't be written.
      5  Making the video or preview failed, or --update could not reach GitHub.
      130  Cancelled by a signal or by stdin with --cancel-on-eof.

    """

    static let checkHelpText = """
    song2vid check reads a song and an image and reports what Song2Vid would make from them.
    It writes nothing, and it never changes your files.

    Usage:
      song2vid check <audio> <image> [-j]
      song2vid check <file> [-j]

    It reports the song's length, sample rate and channels, the image's size after its
    orientation tag, and for every Frame Shape and Resolution the video's size, how the
    image is placed (fit or crop) and whether it would be enlarged. Original has one size,
    or is too small when a side of the image is under 16 pixels.

    With one file, it reports only that file: the song's facts for a song, or the image's size and the
    output sizes for an image. The kind comes from what is inside the file. A file that is neither is
    audio_unreadable when its name ends in a song type, and image_unreadable otherwise.

    Options:
      -j | --json    Write one JSON line (api_version "1") instead of text.
      -h | --help    Show this help.

    Examples:
      song2vid check song.mp3 cover.png
      song2vid check song.mp3 cover.png --json
      song2vid check -j song.wav photo.heic
      song2vid check song.mp3
      song2vid check cover.png --json

    Exit statuses:
      0  Success.
      1  An input file does not exist (audio_not_found, image_not_found).
      2  Usage error (usage).
      3  An input file can't be read or isn't usable (audio_unreadable, image_unreadable).

    A missing single file is audio_not_found when its name ends in a song type, and image_not_found otherwise.

    With --json, errors are a JSON line on stdout too, with the error code, and stderr is empty.

    """

    static let makeHelpText = """
    song2vid make turns one song and one image into an MP4 video: the image for the whole length of the song.
    It never changes your song or image, and it never replaces a file unless you say so with --overwrite.

    Usage:
      song2vid make <audio> <image> [-o <file.mp4>] [-s <shape>] [-r <resolution>] [-c <h,v>] [-C <codec>] [-w] [-n] [-j] [-q] [-E]

    Everything is checked before anything is made. The video is built in a temporary file beside the output
    and moved into place when it is complete, so a half-made video never has the final name.

    Options:
      -o | --out <file.mp4>       Where to save. Default: the song's name with .mp4, in the current folder.
                                  The name must end in .mp4.
      -s | --shape <shape>        16:9 (default), 9:16, 1:1, 4:3 or original.
      -r | --resolution <size>    480p, 1080p (default) or 2160p. Not with the original shape.
      -c | --crop <h,v>           Which part of the image a crop keeps, as two fractions from 0 to 1.
                                  Default 0.5,0.5 (centred). Only with the 1:1 and 4:3 shapes.
      -C | --codec <codec>         h264 (default) or hevc. Run 'song2vid encoders' to check availability.
      -E | --cancel-on-eof         Cancel at end-of-file on stdin or on a line containing only cancel.
      -w | --overwrite            Replace the output if it exists. Without it, an existing file is an error.
      -n | --dry-run              Check everything and report what would be made. Writes nothing.
      -j | --json                 Write JSON Lines (api_version "1") instead of text.
      -q | --quiet                No progress output. The result and errors still print.
      -h | --help                 Show this help.

    Short options can't be joined: write -w -n, not -wn.

    Examples:
      song2vid make song.mp3 cover.png
      song2vid make song.mp3 cover.png -s 1:1 -r 480p -c 0.5,0.2 -o preview.mp4
      song2vid make song.mp3 cover.png --dry-run --json
      song2vid make song.mp3 cover.png -C hevc -o video.mp4 --overwrite

    Exit statuses:
      0  Success (also --dry-run).
      1  An input file does not exist (audio_not_found, image_not_found).
      2  Usage error (usage).
      3  An input or Codec can't be used (audio_unreadable, image_unreadable, image_too_small, codec_unavailable).
      4  The output can't be written (output_exists, output_not_writable, output_not_mp4, disk_full).
      5  Making the video failed after it started (export_failed).
      130  Cancelled by a signal or by stdin with --cancel-on-eof (cancelled). The temporary file is deleted.

    With --json, errors are a JSON line on stdout too, with the error code, and stderr is empty.

    """

    static let encodersHelpText = """
    song2vid encoders reports whether this computer can produce H.264 and HEVC.
    It reads and writes no files.

    Usage:
      song2vid encoders [-j]

    Options:
      -j | --json    Write one JSON line (api_version "1") instead of text.
      -h | --help    Show this help.

    Examples:
      song2vid encoders
      song2vid encoders --json

    Exit statuses:
      0  Success, even if a Codec is unavailable.
      2  Usage error (usage).

    """

    static let previewHelpText = """
    song2vid preview saves an image as a PNG with its orientation applied and transparency filled with
    black. The PNG fits within 2048 by 2048 pixels. Smaller images keep their size.

    Usage:
      song2vid preview <image> -o <file.png> [-w] [-j] [-E]

    Options:
      -o | --out <file.png>       Where to save the PNG (required).
      -w | --overwrite            Replace the output if it exists.
      -E | --cancel-on-eof         Cancel at end-of-file on stdin or on a line containing only cancel.
      -j | --json                 Write one JSON line (api_version "1") instead of text.
      -h | --help                 Show this help.

    Examples:
      song2vid preview photo.heic -o cover.png
      song2vid preview photo.jpg --out cover.png --overwrite --json

    Exit statuses:
      0  Success.
      1  The image does not exist (image_not_found).
      2  Usage error (usage).
      3  The image can't be read (image_unreadable).
      4  The output can't be written (output_exists, output_not_writable, disk_full).
      5  Writing the image failed (export_failed).
      130  Cancelled (cancelled). The temporary file is deleted.

    """
}
