import Foundation
import Testing

/// Seam 5 (SPEC section 18): the command's arguments in; stdout, stderr and the exit status out.
/// Expected text and statuses come from SPEC sections 14.2 and 14.6, not from the code under test.
@Suite("song2vid global options")
struct CommandGlobalOptionsTests {
    static let usageError = "Unknown option. Run 'song2vid --help'.\n"

    @Test("The command is part of the built app", .tags(.command))
    func commandExists() {
        #expect(FileManager.default.isExecutableFile(atPath: CommandProcess.executableURL.path))
    }

    @Test("Version prints the name and 1.2.0, then exits 0", arguments: ["--version", "-v"])
    func version(option: String) throws {
        let result = try CommandProcess.run([option])
        #expect(result.stdout == "song2vid 1.2.0\n")
        #expect(result.stderr.isEmpty)
        #expect(result.status == 0)
    }

    @Test("Repo prints the repository address, then exits 0", arguments: ["--repo", "-R"])
    func repo(option: String) throws {
        let result = try CommandProcess.run([option])
        #expect(result.stdout == "https://github.com/devin-thomas/song2vid-app\n")
        #expect(result.stderr.isEmpty)
        #expect(result.status == 0)
    }

    @Test("Help describes the command, its usage, examples and exit statuses", arguments: ["--help", "-h"])
    func help(option: String) throws {
        let result = try CommandProcess.run([option])
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        for part in ["Usage:", "Examples:", "Exit statuses:", "--help", "--version", "--repo", "-h", "-v", "-R"] {
            #expect(result.stdout.contains(part), "help is missing \(part)")
        }
        // The statuses table lists the ones the command can return today.
        #expect(result.stdout.contains("0  "))
        #expect(result.stdout.contains("2  "))
    }

    @Test("An unknown option is a usage error that does not echo it", arguments: [
        "--frobnicate", "-Z", "-vh", "--", "-U", "-X",
    ])
    func unknownOption(option: String) throws {
        let result = try CommandProcess.run([option])
        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        // The whole message is fixed text, so nothing the person typed can be in it.
        #expect(result.stderr == Self.usageError)
    }

    @Test("An unknown command is a usage error that does not echo it")
    func unknownCommand() throws {
        let result = try CommandProcess.run(["frobnicate-the-widget"])
        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == "Unknown command. Run 'song2vid --help'.\n")
        #expect(!result.stderr.contains("widget"))
    }

    @Test("No arguments is a usage error")
    func noArguments() throws {
        let result = try CommandProcess.run([])
        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == "Missing command. Run 'song2vid --help'.\n")
    }

    @Test("Global options can't be combined")
    func twoOptions() throws {
        let result = try CommandProcess.run(["--version", "--help"])
        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == "Use one option at a time. Run 'song2vid --help'.\n")
    }

    @Test("A near miss suggests the known name without echoing what was typed", arguments: [
        ("--versoin", "--version"), ("--hlep", "--help"), ("--version=2", "--version"), ("--repoo", "--repo"),
    ])
    func didYouMean(typed: String, suggested: String) throws {
        let result = try CommandProcess.run([typed])
        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == Self.usageError.dropLast() + " Did you mean \(suggested)?\n")
    }

    @Test("The command reads nothing from its folder or environment into its output")
    func outputHasNoFolderOrEnvironmentValue() throws {
        let plant = "planted-fake-secret-value"
        let environment = ["PATH": "/usr/bin:/bin", "S2V_FAKE_VALUE": plant]
        for arguments in [["--version"], ["--help"], ["--repo"], ["--nope"]] {
            let result = try CommandProcess.run(arguments, environment: environment)
            #expect(!result.stdout.contains(plant) && !result.stderr.contains(plant))
            #expect(!result.stdout.contains("/Users/") && !result.stderr.contains("/Users/"))
            #expect(!result.stdout.contains(NSTemporaryDirectory()) && !result.stderr.contains(NSTemporaryDirectory()))
        }
    }
}

extension Tag {
    @Tag static var command: Self
}
