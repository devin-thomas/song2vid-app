import Foundation

/// What the command reports when it can't do what was asked (SPEC section 14.6).
/// The messages are fixed text or the SPEC section 7 wording: none of them contains a path or anything typed.
struct CommandError: Error, Equatable, Sendable {
    /// The error codes. The codes for the commands that come later are added with them.
    enum Code: String, Sendable {
        case usage
        case audioNotFound = "audio_not_found"
        case imageNotFound = "image_not_found"
        case audioUnreadable = "audio_unreadable"
        case imageUnreadable = "image_unreadable"
        case imageTooSmall = "image_too_small"
        case outputExists = "output_exists"
        case outputNotWritable = "output_not_writable"
        case outputNotMP4 = "output_not_mp4"
        case diskFull = "disk_full"
        case exportFailed = "export_failed"
        case network
        case cancelled
    }

    let code: Code
    let message: String

    /// The exit status for this error's code.
    var status: Int32 {
        switch code {
        case .audioNotFound, .imageNotFound: Song2VidCommand.ExitStatus.notFound
        case .usage: Song2VidCommand.ExitStatus.usage
        case .audioUnreadable, .imageUnreadable, .imageTooSmall: Song2VidCommand.ExitStatus.unreadable
        case .outputExists, .outputNotWritable, .outputNotMP4, .diskFull: Song2VidCommand.ExitStatus.outputFailed
        case .exportFailed, .network: Song2VidCommand.ExitStatus.exportFailed
        case .cancelled: Song2VidCommand.ExitStatus.cancelled
        }
    }

    static let audioNotFound = CommandError(code: .audioNotFound, message: "The audio file was not found.")
    static let imageNotFound = CommandError(code: .imageNotFound, message: "The image file was not found.")
    static let audioUnreadable = CommandError(code: .audioUnreadable, message: MediaError.unreadableAudio.message)
    static let imageUnreadable = CommandError(code: .imageUnreadable, message: MediaError.unreadableImage.message)
    static let imageTooSmall = CommandError(code: .imageTooSmall, message: FrameError.imageTooSmall.message)
    static let outputExists = CommandError(
        code: .outputExists, message: "The output file already exists. Use --overwrite to replace it."
    )
    static let outputNotMP4 = CommandError(code: .outputNotMP4, message: "The output file name must end in .mp4.")
    static let outputFolderNotFound = CommandError(code: .outputNotWritable, message: "The output folder was not found.")
    static let outputFolderNotWritable = CommandError(code: .outputNotWritable, message: "Song2Vid can't write to the output folder.")
    static let outputIsAFolder = CommandError(code: .outputNotWritable, message: "The output can't be a folder.")
    static let outputIsAnInput = CommandError(code: .outputNotWritable, message: "The output can't be one of the input files.")
    static let cancelled = CommandError(code: .cancelled, message: "Cancelled.")

    /// An export that did not finish, with the SPEC section 6.5 wording where it exists.
    init(exportFailure failure: ExportError) {
        switch failure {
        case .unreadableAudio: self = .audioUnreadable
        case .unreadableImage: self = .imageUnreadable
        case .cannotSaveToFolder: self = .outputFolderNotWritable
        case .diskFull: self.init(code: .diskFull, message: "Not enough disk space.")
        case .audioReadFailed, .encodingFailed: self.init(code: .exportFailed, message: failure.message + ".")
        }
    }

    /// A usage problem as an error: the message, a known suggestion if there is one, and where to get help.
    init(_ problem: UsageProblem) {
        var text = "\(problem.message) Run '\(problem.scope.helpCommand)'."
        if let suggestion = problem.suggestion { text += " Did you mean \(suggestion)?" }
        self.init(code: .usage, message: text)
    }

    init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}

extension CommandOutput {
    /// An error as the command reports it: one line on stderr, or under `--json` one `error` line on stdout and nothing on stderr.
    static func failure(_ error: CommandError, json: Bool) -> CommandOutput {
        if json {
            let line = JSONValue.line(type: "error", [
                (.error, .object([(.code, .string(error.code.rawValue)), (.message, .string(error.message))])),
            ])
            return CommandOutput(stdout: line.line, status: error.status)
        }
        return CommandOutput(stderr: error.message + "\n", status: error.status)
    }
}
