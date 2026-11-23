import Foundation

// The command line's grammar (SPEC section 14.2), as data. Each option is one row in `OptionSpec.all`:
// its short form, long form, the places it is allowed and whether it takes a value. Adding a command or an
// option means adding a case and a row; the parser below does not change.

/// The commands that come first on the command line.
enum CommandName: String, CaseIterable, Sendable {
    case check
    case make
    case encoders
    case preview

    /// Where the options after this command are read.
    var scope: CommandScope {
        switch self {
        case .check: .check
        case .make: .make
        case .encoders: .encoders
        case .preview: .preview
        }
    }
}

/// Where an option is being read: with no command (the global options), or after a command's name.
enum CommandScope: Hashable, Sendable {
    case global
    case check
    case make
    case encoders
    case preview

    /// The command that prints help for this scope, as the usage errors name it.
    var helpCommand: String {
        switch self {
        case .global: "song2vid --help"
        case .check: "song2vid check --help"
        case .make: "song2vid make --help"
        case .encoders: "song2vid encoders --help"
        case .preview: "song2vid preview --help"
        }
    }
}

/// The options the command knows.
enum CommandOption: CaseIterable, Sendable {
    case help, version, repo, skill, update, json
    case shape, resolution, crop, out, overwrite, dryRun, quiet, codec, cancelOnEOF
}

/// One option: how it is spelled, where it applies and whether a value follows it.
struct OptionSpec: Sendable {
    let option: CommandOption
    let short: String
    let long: String
    let scopes: Set<CommandScope>
    let takesValue: Bool

    /// Every option the command knows (SPEC section 14.2).
    static let all: [OptionSpec] = [
        OptionSpec(option: .help, short: "-h", long: "--help", scopes: [.global, .check, .make, .encoders, .preview], takesValue: false),
        OptionSpec(option: .version, short: "-v", long: "--version", scopes: [.global], takesValue: false),
        OptionSpec(option: .repo, short: "-R", long: "--repo", scopes: [.global], takesValue: false),
        OptionSpec(option: .skill, short: "-S", long: "--skill", scopes: [.global], takesValue: false),
        OptionSpec(option: .update, short: "-u", long: "--update", scopes: [.global], takesValue: false),
        OptionSpec(option: .json, short: "-j", long: "--json", scopes: [.global, .check, .make, .encoders, .preview], takesValue: false),
        OptionSpec(option: .shape, short: "-s", long: "--shape", scopes: [.make], takesValue: true),
        OptionSpec(option: .resolution, short: "-r", long: "--resolution", scopes: [.make], takesValue: true),
        OptionSpec(option: .crop, short: "-c", long: "--crop", scopes: [.make], takesValue: true),
        OptionSpec(option: .out, short: "-o", long: "--out", scopes: [.make, .preview], takesValue: true),
        OptionSpec(option: .overwrite, short: "-w", long: "--overwrite", scopes: [.make, .preview], takesValue: false),
        OptionSpec(option: .dryRun, short: "-n", long: "--dry-run", scopes: [.make], takesValue: false),
        OptionSpec(option: .codec, short: "-C", long: "--codec", scopes: [.make], takesValue: true),
        OptionSpec(option: .cancelOnEOF, short: "-E", long: "--cancel-on-eof", scopes: [.make, .preview], takesValue: false),
        OptionSpec(option: .quiet, short: "-q", long: "--quiet", scopes: [.make], takesValue: false),
    ]

    func isSpelled(_ argument: String) -> Bool { argument == short || argument == long }
}

/// An option as the person gave it.
struct ParsedOption: Equatable, Sendable {
    let option: CommandOption
    let value: String?
}

/// A command line that follows the grammar.
struct ParsedCommandLine: Sendable {
    /// Nil when only global options were given.
    let command: CommandName?
    let options: [ParsedOption]
    /// The words that are not options: the files after a command.
    let operands: [String]

    func has(_ option: CommandOption) -> Bool { options.contains { $0.option == option } }

    /// The value given to an option that takes one, if it was given.
    func value(of option: CommandOption) -> String? { options.first { $0.option == option }?.value }
}

/// A command line that breaks the grammar. The message is fixed text: nothing the person typed is in it.
struct UsageProblem: Error, Sendable {
    let message: String
    /// A known option name close to what was typed, never the typed text itself.
    let suggestion: String?
    let scope: CommandScope
    /// True when `--json` was given in a place where it applies, so the problem is reported as a JSON line.
    let jsonRequested: Bool
}

enum CommandParser {
    /// Reads the arguments that follow the command's own name.
    /// Short options are never combined (`-wn` is not `-w -n`), and an option's value is the next argument
    /// or follows `=` in the long form.
    static func parse(_ arguments: [String]) -> Result<ParsedCommandLine, UsageProblem> {
        guard let first = arguments.first else {
            return .failure(UsageProblem(message: "Missing command.", suggestion: nil, scope: .global, jsonRequested: false))
        }
        var command: CommandName?
        var rest = arguments[...]
        if !first.hasPrefix("-") {
            guard let named = CommandName(rawValue: first) else {
                return .failure(UsageProblem(message: "Unknown command.", suggestion: nil, scope: .global, jsonRequested: false))
            }
            command = named
            rest = rest.dropFirst()
        }
        let scope = command?.scope ?? .global
        let inScope = OptionSpec.all.filter { $0.scopes.contains(scope) }
        let wantsJSON = rest.contains { argument in
            OptionSpec.all.contains { $0.option == .json && $0.scopes.contains(scope) && $0.isSpelled(argument) }
        }
        func problem(_ message: String, suggestion: String? = nil) -> Result<ParsedCommandLine, UsageProblem> {
            .failure(UsageProblem(message: message, suggestion: suggestion, scope: scope, jsonRequested: wantsJSON))
        }

        var options: [ParsedOption] = []
        var operands: [String] = []
        var remaining = rest[...]
        while let argument = remaining.popFirst() {
            guard argument.hasPrefix("-") else {
                // A word with no command in front of it is a command that does not exist.
                if command == nil { return problem("Unknown command.") }
                operands.append(argument)
                continue
            }
            let (name, attached) = splitAttachedValue(argument)
            if let spec = OptionSpec.all.first(where: { $0.isSpelled(argument) || ($0.takesValue && attached != nil && $0.long == name) }) {
                guard spec.scopes.contains(scope) else { return problem("That option does not apply here.") }
                guard spec.takesValue else {
                    options.append(ParsedOption(option: spec.option, value: nil))
                    continue
                }
                // The next word is the value unless it is another option, so `-o -w` is a missing value, not a file
                // called `-w`. (A value that starts with a dash can be attached: `--out=-name.mp4`.)
                let next = remaining.first.flatMap { $0.hasPrefix("-") ? nil : $0 }
                guard let value = attached ?? next else { return problem("An option is missing its value.") }
                if attached == nil { remaining.removeFirst() }
                guard !options.contains(where: { $0.option == spec.option }) else {
                    return problem("An option can be given only once.")
                }
                options.append(ParsedOption(option: spec.option, value: value))
            } else {
                return problem("Unknown option.", suggestion: suggestion(for: argument, among: inScope))
            }
        }
        return .success(ParsedCommandLine(command: command, options: options, operands: operands))
    }

    /// `--out=file` is `--out` with the value `file`. Anything else has no attached value.
    private static func splitAttachedValue(_ argument: String) -> (name: String, value: String?) {
        guard argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") else { return (argument, nil) }
        return (String(argument[..<equals]), String(argument[argument.index(after: equals)...]))
    }

    /// The one known long option within two edits of what was typed, if there is exactly one.
    private static func suggestion(for argument: String, among specs: [OptionSpec]) -> String? {
        guard argument.hasPrefix("--") else { return nil }
        let close = specs.map(\.long).filter { editDistance($0, argument) <= 2 }
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
}
