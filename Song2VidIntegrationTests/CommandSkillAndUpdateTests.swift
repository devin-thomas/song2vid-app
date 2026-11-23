import Foundation
import Testing

/// Seam 5 (SPEC section 18): `--skill` and `--update` on the built command, as a separate process.
@Suite("song2vid --skill and --update")
struct CommandSkillAndUpdateTests {
    /// The skill in the repo, found from this source file's own location.
    private static var skillFile: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("skills/song2vid/SKILL.md")
    }

    @Test("--skill prints skills/song2vid/SKILL.md byte for byte, with the long and short spelling")
    func skillMatchesTheFile() throws {
        let expected = try Data(contentsOf: Self.skillFile)
        #expect(expected.count > 1000)
        for option in ["--skill", "-S"] {
            let process = Process()
            process.executableURL = CommandProcess.executableURL
            process.arguments = [option]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = Pipe()
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            #expect(data == expected, "\(option) output differs from SKILL.md")
        }
    }

    @Test("--skill works through a link on the PATH, as the Agent Guide installs the command")
    func skillThroughALink() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let link = workspace.url("song2vid")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: CommandProcess.executableURL)
        let process = Process()
        process.executableURL = link
        process.arguments = ["--skill"]
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(data == (try Data(contentsOf: Self.skillFile)))
    }

    @Test("The skill gives both routes, the rules and every error code")
    func skillContent() throws {
        let text = try String(contentsOf: Self.skillFile, encoding: .utf8)
        #expect(text.hasPrefix("---\nname: song2vid\ndescription: "))
        for part in [
            "Route 1: the command", "Route 2: the app's window", "Open Anyway", "--overwrite", "command -v song2vid",
            "~/.local/bin", "Choose Audio", "Choose Image", "Frame Shape", "Resolution", "Make Video", "Reset to Center",
            "audio_not_found", "image_not_found", "usage", "audio_unreadable", "image_unreadable", "image_too_small",
            "output_exists", "output_not_writable", "output_not_mp4", "disk_full", "export_failed", "network", "cancelled",
            "progress", "remaining_seconds", "--update",
        ] {
            #expect(text.contains(part), "the skill is missing \(part)")
        }
        // Every option the command takes is in the options table.
        for option in ["-s", "-r", "-c", "-o", "-w", "-n", "-j", "-q"] { #expect(text.contains("| `\(option)`")) }
        #expect(!text.contains("/Users/"))
    }

    // MARK: --update, against a local stand-in for the release lookup

    private func update(_ arguments: [String], stub: String?) throws -> CommandProcess.Result {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        var environment = ["PATH": "/usr/bin:/bin"]
        if let stub {
            try Data(stub.utf8).write(to: workspace.url("latest.json"))
            environment["SONG2VID_UPDATE_URL"] = workspace.url("latest.json").absoluteString
        } else {
            environment["SONG2VID_UPDATE_URL"] = workspace.url("nothing-here.json").absoluteString
        }
        return try CommandProcess.run(arguments, environment: environment)
    }

    @Test("Up to date, newer available and no network, as text")
    func updateText() throws {
        let same = try update(["--update"], stub: #"{"tag_name":"v1.2.0"}"#)
        #expect(same.status == 0)
        #expect(same.stdout == "Song2Vid 1.2.0 is up to date.\n")
        #expect(same.stderr.isEmpty)

        let newer = try update(["-u"], stub: #"{"tag_name":"v1.3.0"}"#)
        #expect(newer.status == 0)
        #expect(newer.stdout == "Song2Vid 1.3.0 is available (you have 1.2.0). Download it from https://song2vid.pages.dev.\n")

        let offline = try update(["--update"], stub: nil)
        #expect(offline.status == 5)
        #expect(offline.stdout.isEmpty)
        #expect(offline.stderr == "Couldn't check for updates. Check the internet connection and try again.\n")
        #expect(!offline.stderr.contains(CommandWorkspace.folderMarker))
    }

    @Test("--json gives one result or error line and an empty stderr")
    func updateJSON() throws {
        let newer = try update(["--update", "--json"], stub: #"{"tag_name":"v1.3.0"}"#)
        #expect(newer.status == 0)
        #expect(newer.stderr.isEmpty)
        let line = try JSONOutputLine(newer.stdout)
        #expect(line["type"] as? String == "result")
        #expect(line["command"] as? String == "update")
        #expect(line["current"] as? String == "1.2.0")
        #expect(line["latest"] as? String == "1.3.0")
        #expect(line["update_available"] as? Bool == true)
        #expect(line["download_page"] as? String == "https://song2vid.pages.dev")

        let same = try update(["-u", "-j"], stub: #"{"tag_name":"1.2.0"}"#)
        #expect(try JSONOutputLine(same.stdout)["update_available"] as? Bool == false)

        let offline = try update(["--update", "--json"], stub: nil)
        #expect(offline.status == 5)
        #expect(offline.stderr.isEmpty)
        let error = try #require(try JSONOutputLine(offline.stdout).child("error"))
        #expect(error["code"] as? String == "network")
        #expect(!offline.stdout.contains(CommandWorkspace.folderMarker))
    }

    @Test("--update and --skill stand alone: other options are a usage error, and unknown text is not echoed")
    func standAlone() throws {
        for arguments in [["--update", "--version"], ["--skill", "--update"], ["--update", "--skill"]] {
            let result = try CommandProcess.run(arguments)
            #expect(result.status == 2, "\(arguments)")
            #expect(result.stdout.isEmpty)
            #expect(result.stderr.hasSuffix("\n") && result.stderr.split(separator: "\n").count == 1)
        }
        // --json goes only with --update; elsewhere it is a usage error, as one JSON line.
        for arguments in [["--skill", "--json"], ["--json"], ["--version", "-j"]] {
            let result = try CommandProcess.run(arguments)
            #expect(result.status == 2, "\(arguments)")
            #expect(result.stderr.isEmpty)
            let error = try #require(try JSONOutputLine(result.stdout).child("error"))
            #expect(error["code"] as? String == "usage")
        }
    }

    @Test("--help lists --skill and --update with their short forms")
    func help() throws {
        let result = try CommandProcess.run(["--help"])
        for part in ["-S | --skill", "-u | --update", "song2vid --update --json"] { #expect(result.stdout.contains(part), "\(part)") }
    }
}
