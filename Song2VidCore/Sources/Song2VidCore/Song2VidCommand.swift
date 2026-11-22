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
public enum Song2VidCommand {
    /// The version of the app and the command (ADR-013: one number covers both).
    public static let version = "1.1.0"
    /// Where the project lives, printed by `--repo`.
    public static let repositoryURL = "https://github.com/devin-thomas/song2vid-app"

    /// Exit statuses (SPEC section 14.6). The statuses for the commands that come later are added with them.
    public enum ExitStatus {
        public static let success: Int32 = 0
        public static let usage: Int32 = 2
    }

    /// The global options. Short and long forms mean the same thing (SPEC section 14.2).
    private enum GlobalOption: CaseIterable {
        case help, version, repo

        var short: String {
            switch self {
            case .help: "-h"
            case .version: "-v"
            case .repo: "-R"
            }
        }

        var long: String {
            switch self {
            case .help: "--help"
            case .version: "--version"
            case .repo: "--repo"
            }
        }

        static func matching(_ argument: String) -> GlobalOption? {
            allCases.first { argument == $0.short || argument == $0.long }
        }
    }

    /// Runs the command with the arguments that follow its name.
    public static func run(arguments: [String]) -> CommandOutput {
        guard !arguments.isEmpty else {
            return usageError("Missing command.")
        }

        // Validate every argument before acting on any, so a typo never runs half a command.
        var options: [GlobalOption] = []
        for argument in arguments {
            if let option = GlobalOption.matching(argument) {
                options.append(option)
            } else if argument.hasPrefix("-") {
                // The unknown text is never echoed (SPEC section 14.2). A suggestion is a known name, not the input.
                return usageError("Unknown option.", suggestion: suggestion(for: argument))
            } else {
                return usageError("Unknown command.")
            }
        }
        guard options.count == 1, let option = options.first else {
            return usageError("Use one option at a time.")
        }

        switch option {
        case .help:
            return CommandOutput(stdout: helpText, status: ExitStatus.success)
        case .version:
            return CommandOutput(stdout: "song2vid \(version)\n", status: ExitStatus.success)
        case .repo:
            return CommandOutput(stdout: repositoryURL + "\n", status: ExitStatus.success)
        }
    }

    private static func usageError(_ message: String, suggestion: String? = nil) -> CommandOutput {
        var line = "\(message) Run 'song2vid --help'."
        if let suggestion { line += " Did you mean \(suggestion)?" }
        return CommandOutput(stderr: line + "\n", status: ExitStatus.usage)
    }

    /// The one known long option within two edits of what was typed, if there is exactly one.
    private static func suggestion(for argument: String) -> String? {
        guard argument.hasPrefix("--") else { return nil }
        let close = GlobalOption.allCases.map(\.long).filter { editDistance($0, argument) <= 2 }
        return close.count == 1 ? close[0] : nil
    }

    /// The number of single-character edits (insert, delete, replace) between two strings.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in stride(from: 1, through: a.count, by: 1) {
            var row = [i] + Array(repeating: 0, count: b.count)
            for j in stride(from: 1, through: b.count, by: 1) {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = row
        }
        return previous[b.count]
    }

    static let helpText = """
    song2vid turns one song and one image into an MP4 video.

    Usage:
      song2vid -h | --help       Show this help.
      song2vid -v | --version    Print the version.
      song2vid -R | --repo       Print the project address.

    Examples:
      song2vid --version
      song2vid --repo

    Exit statuses:
      0  Success.
      2  Usage error: an option or command that song2vid does not know.

    """
}
