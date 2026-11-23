import Foundation
import Testing

/// Seam 5: nothing private reaches the output of `song2vid make`, in any mode (SPEC section 14.5), and its JSON uses
/// only the documented keys. Same method as the `check` leak test: a fake value in the environment, a folder name with a
/// marker, a marker inside files that are not media, and `OS_ACTIVITY_DT_MODE` set so macOS frameworks copy their own
/// log lines (which can hold a full file path) onto standard error.
@Suite("song2vid make keeps private text out of its output")
struct CommandMakeLeakTests {
    static let plantedValue = "planted-fake-environment-value"
    static let contentMarker = "planted-file-content-marker"

    /// Every way a `make` run can end, with the arguments for it.
    private func runs(in workspace: CommandWorkspace) throws -> [(name: String, arguments: [String])] {
        let audio = try workspace.tone()
        let image = try workspace.picture(width: 1000, height: 800)
        try Data(Self.contentMarker.utf8).write(to: workspace.url("fake-song.mp3"))
        try Data(Self.contentMarker.utf8).write(to: workspace.url("fake-picture.png"))
        try workspace.picture("tiny.png", width: 10, height: 10)
        try Data(Self.contentMarker.utf8).write(to: workspace.url("taken.mp4"))
        let fast = ["-s", "1:1", "-r", "480p"]
        return [
            ("success", ["make", audio, image, "-o", workspace.path("made.mp4")] + fast),
            ("success, default name", ["make", audio, image] + fast),
            ("dry run", ["make", audio, image, "-n", "-o", workspace.path("planned.mp4")]),
            ("quiet", ["make", audio, image, "-q", "-w", "-o", workspace.path("made-quiet.mp4")] + fast),
            ("audio not found", ["make", workspace.path("missing.wav"), image]),
            ("image not found", ["make", audio, workspace.path("missing.png")]),
            ("audio unreadable", ["make", workspace.path("fake-song.mp3"), image]),
            ("image unreadable", ["make", audio, workspace.path("fake-picture.png")]),
            ("folder as audio", ["make", workspace.folder.path, image]),
            ("image too small", ["make", audio, workspace.path("tiny.png"), "-s", "original"]),
            ("output exists", ["make", audio, image, "-o", workspace.path("taken.mp4")]),
            ("output not mp4", ["make", audio, image, "-o", workspace.path("out.mov")]),
            ("output folder missing", ["make", audio, image, "-o", workspace.path("nowhere/out.mp4")]),
            ("unknown option", ["make", audio, image, "--\(Self.plantedValue)"]),
            ("bad shape", ["make", audio, image, "-s", Self.plantedValue]),
            ("wrong number of files", ["make", audio]),
            ("help", ["make", "--help"]),
        ]
    }

    private func environment(_ workspace: CommandWorkspace) -> [String: String] {
        [
            "PATH": "/usr/bin:/bin",
            "S2V_PLANTED": Self.plantedValue,
            "TMPDIR": workspace.folder.path + "/",
            "OS_ACTIVITY_DT_MODE": "YES",
        ]
    }

    @Test("No output contains the planted value, a folder path or file contents, as text or as JSON")
    func nothingPrivateIsPrinted() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let forbidden = [
            Self.plantedValue, Self.contentMarker, CommandWorkspace.folderMarker,
            workspace.folder.path, workspace.folder.resolvingSymlinksInPath().path,
            "/Users/", "/var/", "/private/", "/tmp/",
        ]
        for (name, arguments) in try runs(in: workspace) {
            for json in [false, true] {
                // A run that made a file would make it again (and then find it taken) on the second pass.
                let pass = json ? arguments.map { $0.hasSuffix(".mp4") && $0.contains("made") ? $0.replacingOccurrences(of: ".mp4", with: "-json.mp4") : $0 } : arguments
                let result = try CommandProcess.run(pass + (json ? ["--json"] : []), environment: environment(workspace), currentDirectory: workspace.folder)
                let combined = result.stdout + result.stderr
                for text in forbidden {
                    #expect(!combined.contains(text), "\(name) (json: \(json)) printed \(text)")
                }
                if json || name == "help" || name == "dry run" || name == "quiet" {
                    #expect(result.stderr.isEmpty, "\(name) (json: \(json)) wrote to stderr: \(result.stderr)")
                } else if name.hasPrefix("success") {
                    #expect(JSONOutputLine.plainProgressLinesOnly(result.stderr.split(separator: "\n")), "\(name) wrote to stderr: \(result.stderr)")
                }
            }
        }
    }

    @Test("Every JSON line uses only keys from the fixed list, and each make key is used")
    func jsonKeysAreFromTheAllowlist() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        // The keys make adds to check's (S2V-015 copies the list to the docs page). Written out here, not read from the code.
        let makeKeys: Set<String> = ["api_version", "type", "command", "output", "name", "width", "height", "duration_seconds", "bytes",
                                     "placement", "enlarged", "dry_run", "error", "code", "message", "codec", "encoder", "encoder_fallback"]
        func keys(in value: Any) -> Set<String> {
            switch value {
            case let object as [String: Any]: Set(object.keys).union(object.values.flatMap { keys(in: $0) })
            case let array as [Any]: Set(array.flatMap { keys(in: $0) })
            default: []
            }
        }
        var seen: Set<String> = []
        for (_, arguments) in try runs(in: workspace) where arguments.last != "--help" {
            // Each run once, under its own output name so none finds another's file.
            let named = arguments.map { $0.hasSuffix("made.mp4") ? $0.replacingOccurrences(of: "made.mp4", with: "keys.mp4") : $0 }
            let result = try CommandProcess.run(named + ["--json"], environment: environment(workspace), currentDirectory: workspace.folder)
            if arguments.contains("-q") { continue }
            let line = try JSONOutputLine.final(result.stdout)
            let used = keys(in: line.object)
            #expect(used.isSubset(of: makeKeys), "unexpected keys \(used.subtracting(makeKeys))")
            seen.formUnion(used)
        }
        #expect(seen == makeKeys)
    }

    // MARK: Help

    @Test("make --help describes the command, every option in both spellings, examples and every exit status", arguments: ["--help", "-h"])
    func help(option: String) throws {
        let result = try CommandProcess.run(["make", option])
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        for part in [
            "Usage:", "song2vid make <audio> <image>", "Examples:", "Exit statuses:",
            "-o", "--out", "-s", "--shape", "-r", "--resolution", "-c", "--crop", "-w", "--overwrite", "-n", "--dry-run",
            "-C", "--codec", "-E", "--cancel-on-eof", "-j", "--json", "-q", "--quiet", "-h", "--help", "16:9", "9:16", "1:1", "4:3", "original", "480p", "1080p", "2160p",
            "audio_not_found", "image_not_found", "usage", "audio_unreadable", "image_unreadable", "image_too_small",
            "output_exists", "output_not_writable", "output_not_mp4", "disk_full", "export_failed", "cancelled",
        ] {
            #expect(result.stdout.contains(part), "make help is missing \(part)")
        }
        for status in ["0  ", "1  ", "2  ", "3  ", "4  ", "5  ", "130  "] {
            #expect(result.stdout.contains("\n  \(status)"), "make help is missing the status line \(status)")
        }
    }

    @Test("The global help lists make, its usage and the statuses 4, 5 and 130")
    func globalHelpListsMake() throws {
        let result = try CommandProcess.run(["--help"])
        #expect(result.status == 0)
        #expect(result.stdout.contains("song2vid make"))
        #expect(result.stdout.contains("make --help"))
        for status in ["0  ", "1  ", "2  ", "3  ", "4  ", "5  ", "130  "] {
            #expect(result.stdout.contains("\n  \(status)"), "global help is missing the status line \(status)")
        }
    }

    @Test("Help wins over everything else after make", arguments: [
        ["make", "-h", "nothing"], ["make", "nothing", "-s", "bad", "--help"], ["make", "--json", "-h"],
    ] as [[String]])
    func helpWins(arguments: [String]) throws {
        let result = try CommandProcess.run(arguments)
        #expect(result.status == 0)
        #expect(result.stdout.contains("Usage:"))
    }
}
