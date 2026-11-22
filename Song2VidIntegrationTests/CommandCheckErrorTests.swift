import Foundation
import Testing

/// Seam 5: what `song2vid check` does when it can't do what was asked.
/// Statuses and codes come from SPEC section 14.6, and the unreadable-file wording from SPEC section 7.
@Suite("song2vid check errors")
struct CommandCheckErrorTests {
    /// One way to fail: the inputs to build, and what must come back.
    struct Failure: CustomTestStringConvertible, Sendable {
        enum Audio: Sendable { case good, missing, notAudio, folder }
        enum Image: Sendable { case good, missing, notImage, folder }
        let audio: Audio
        let image: Image
        let status: Int32
        let code: String
        let message: String
        var testDescription: String { "audio \(audio), image \(image) -> \(status) \(code)" }
    }

    static let failures = [
        Failure(audio: .missing, image: .good, status: 1, code: "audio_not_found", message: "The audio file was not found."),
        Failure(audio: .good, image: .missing, status: 1, code: "image_not_found", message: "The image file was not found."),
        // Both missing: the audio is named first.
        Failure(audio: .missing, image: .missing, status: 1, code: "audio_not_found", message: "The audio file was not found."),
        Failure(audio: .notAudio, image: .good, status: 3, code: "audio_unreadable", message: "Song2Vid can't read this audio file."),
        Failure(audio: .good, image: .notImage, status: 3, code: "image_unreadable", message: "Song2Vid can't read this image file."),
        // A folder exists but is not a file the readers can use.
        Failure(audio: .folder, image: .good, status: 3, code: "audio_unreadable", message: "Song2Vid can't read this audio file."),
        Failure(audio: .good, image: .folder, status: 3, code: "image_unreadable", message: "Song2Vid can't read this image file."),
        // Both unreadable: the audio is named first.
        Failure(audio: .notAudio, image: .notImage, status: 3, code: "audio_unreadable", message: "Song2Vid can't read this audio file."),
        // Finding the files comes before reading them, so a missing image wins over an unreadable song.
        Failure(audio: .notAudio, image: .missing, status: 1, code: "image_not_found", message: "The image file was not found."),
    ]

    private func arguments(_ failure: Failure, in workspace: CommandWorkspace) throws -> [String] {
        let audio: String
        switch failure.audio {
        case .good: audio = try workspace.tone()
        case .missing: audio = workspace.path("no-such-song.wav")
        case .notAudio: audio = try workspace.notMedia("not-a-song.mp3")
        case .folder: audio = workspace.folder.path
        }
        let image: String
        switch failure.image {
        case .good: image = try workspace.picture(width: 300, height: 200)
        case .missing: image = workspace.path("no-such-picture.png")
        case .notImage: image = try workspace.notMedia("not-a-picture.png")
        case .folder: image = workspace.folder.path
        }
        return ["check", audio, image]
    }

    @Test("An input that is missing or unusable gives its exit status and a one-line message on stderr", arguments: failures)
    func textError(failure: Failure) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let result = try CommandProcess.run(try arguments(failure, in: workspace))
        #expect(result.status == failure.status)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == failure.message + "\n")
    }

    @Test("Under --json the same failure is one error line on stdout, and stderr is empty", arguments: failures)
    func jsonError(failure: Failure) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let result = try CommandProcess.run(try arguments(failure, in: workspace) + ["--json"])
        #expect(result.status == failure.status)
        #expect(result.stderr.isEmpty)
        let line = try JSONOutputLine(result.stdout)
        #expect(Set(line.object.keys) == ["api_version", "type", "error"])
        #expect(line["api_version"] as? String == "1")
        #expect(line["type"] as? String == "error")
        let error = try #require(line.child("error"))
        #expect(Set(error.keys) == ["code", "message"])
        #expect(error["code"] as? String == failure.code)
        #expect(error["message"] as? String == failure.message)
    }

    // MARK: Usage

    static let usageText = "Unknown option. Run 'song2vid check --help'.\n"

    @Test("An unknown option is a usage error that does not echo it", arguments: [
        "--zzz-typed-text", "-Q", "-jj", "-hj", "--", "-", "-o", "-S", "-u",
    ])
    func unknownOption(option: String) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone()
        let image = try workspace.picture(width: 300, height: 200)
        let result = try CommandProcess.run(["check", audio, image, option])
        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == Self.usageText)

        // Under --json it is the same error as a JSON line, still without the typed text.
        let json = try CommandProcess.run(["check", audio, image, option, "--json"])
        #expect(json.status == 2)
        #expect(json.stderr.isEmpty)
        let line = try JSONOutputLine(json.stdout)
        #expect(line.child("error")?["code"] as? String == "usage")
        #expect(line.child("error")?["message"] as? String == Self.usageText.trimmingCharacters(in: .newlines))
        #expect(!json.stdout.contains("zzz-typed-text"))
    }

    @Test("A near miss suggests the known name without echoing what was typed", arguments: [
        ("--jsno", "--json"), ("--hlep", "--help"), ("--jsonn", "--json"), ("--json=1", "--json"),
    ])
    func didYouMean(typed: String, suggested: String) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone()
        let image = try workspace.picture(width: 300, height: 200)
        let result = try CommandProcess.run(["check", audio, image, typed])
        #expect(result.status == 2)
        #expect(result.stderr == Self.usageText.dropLast() + " Did you mean \(suggested)?\n")
        #expect(!result.stderr.contains(typed))
    }

    @Test("Options that belong to other commands or to no command don't apply to check", arguments: [
        "--version", "-v", "--repo", "-R",
    ])
    func optionsThatDoNotApply(option: String) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone()
        let image = try workspace.picture(width: 300, height: 200)
        let result = try CommandProcess.run(["check", audio, image, option])
        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == "That option does not apply here. Run 'song2vid check --help'.\n")
    }

    @Test("--json is not a global option")
    func jsonNeedsACommand() throws {
        for option in ["--json", "-j"] {
            let result = try CommandProcess.run([option])
            #expect(result.status == 2)
            #expect(result.stdout.isEmpty)
            #expect(result.stderr == "That option does not apply here. Run 'song2vid --help'.\n")
        }
    }

    @Test("check needs exactly one audio file and one image file", arguments: [
        [], ["only-one"], ["one", "two", "three"],
    ] as [[String]])
    func wrongNumberOfFiles(files: [String]) throws {
        let result = try CommandProcess.run(["check"] + files)
        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == "check needs one audio file and one image file. Run 'song2vid check --help'.\n")
        #expect(!result.stderr.contains("only-one"))

        let json = try CommandProcess.run(["check"] + files + ["-j"])
        #expect(json.status == 2)
        #expect(json.stderr.isEmpty)
        #expect(try JSONOutputLine(json.stdout).child("error")?["code"] as? String == "usage")
    }

    @Test("Usage is checked before the files are looked at")
    func usageComesFirst() throws {
        let result = try CommandProcess.run(["check", "no-such-song", "no-such-picture", "--nope"])
        #expect(result.status == 2)
    }

    // MARK: Help

    @Test("check --help describes the command, its usage, examples and every exit status", arguments: ["--help", "-h"])
    func help(option: String) throws {
        let result = try CommandProcess.run(["check", option])
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        for part in [
            "Usage:", "song2vid check <audio> <image> [-j]", "Examples:", "Exit statuses:", "-j", "--json", "-h", "--help",
            "audio_not_found", "image_not_found", "usage", "audio_unreadable", "image_unreadable",
        ] {
            #expect(result.stdout.contains(part), "check help is missing \(part)")
        }
        for status in ["0  ", "1  ", "2  ", "3  "] {
            #expect(result.stdout.contains("\n  \(status)"), "check help is missing the status line \(status)")
        }
    }

    @Test("Help wins over missing files", arguments: [
        ["check", "--help"], ["check", "nothing", "--help"], ["check", "-h", "nothing", "nothing-else"], ["check", "--json", "-h"],
    ])
    func helpWinsOverFiles(arguments: [String]) throws {
        let result = try CommandProcess.run(arguments)
        #expect(result.status == 0)
        #expect(result.stdout.contains("Usage:"))
    }

    @Test("The global help lists check, its usage and the statuses it adds")
    func globalHelpListsCheck() throws {
        let result = try CommandProcess.run(["--help"])
        #expect(result.status == 0)
        #expect(result.stdout.contains("song2vid check <audio> <image> [-j]"))
        #expect(result.stdout.contains("check --help"))
        for status in ["0  ", "1  ", "2  ", "3  "] {
            #expect(result.stdout.contains("\n  \(status)"), "global help is missing the status line \(status)")
        }
    }
}
