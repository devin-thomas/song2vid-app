import Foundation
import Testing

/// Seam 5: nothing private reaches the output of `song2vid check`, in any mode (SPEC section 14.5).
/// The test plants a fake value in the environment, puts the files in a folder whose name carries a marker,
/// and puts a marker inside a file that is not media. None may appear in stdout or stderr, text or JSON,
/// whether the run succeeds or fails.
@Suite("song2vid check keeps private text out of its output")
struct CommandCheckLeakTests {
    static let plantedValue = "planted-fake-environment-value"
    static let contentMarker = "planted-file-content-marker"

    /// Every way a `check` run can end, with the arguments for it. The runs are made twice, as text and as JSON.
    private func runs(in workspace: CommandWorkspace) throws -> [(name: String, arguments: [String])] {
        let audio = try workspace.tone()
        let image = try workspace.picture(width: 1000, height: 800)
        try Data(Self.contentMarker.utf8).write(to: workspace.url("fake-song.mp3"))
        try Data(Self.contentMarker.utf8).write(to: workspace.url("fake-picture.png"))
        return [
            ("success", ["check", audio, image]),
            ("audio not found", ["check", workspace.path("missing.wav"), image]),
            ("image not found", ["check", audio, workspace.path("missing.png")]),
            ("audio unreadable", ["check", workspace.path("fake-song.mp3"), image]),
            ("image unreadable", ["check", audio, workspace.path("fake-picture.png")]),
            ("folder as audio", ["check", workspace.folder.path, image]),
            ("unknown option", ["check", audio, image, "--\(Self.plantedValue)"]),
            ("one file, a song", ["check", audio]),
            ("one file, an image", ["check", image]),
            ("one file, unreadable", ["check", workspace.path("fake-song.mp3")]),
            ("one file, missing", ["check", workspace.path("missing.png")]),
            ("wrong number of files", ["check"]),
            ("help", ["check", "--help"]),
        ]
    }

    private func environment(_ workspace: CommandWorkspace) -> [String: String] {
        [
            "PATH": "/usr/bin:/bin",
            "S2V_PLANTED": Self.plantedValue,
            "TMPDIR": workspace.folder.path + "/",
            // Xcode sets this, and it makes macOS frameworks copy their own log lines onto stderr.
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
                let result = try CommandProcess.run(arguments + (json ? ["--json"] : []), environment: environment(workspace), currentDirectory: workspace.folder)
                let combined = result.stdout + result.stderr
                for text in forbidden {
                    #expect(!combined.contains(text), "\(name) (json: \(json)) printed \(text)")
                }
                // Under --json, stderr is empty. Without it, a successful run writes nothing to stderr.
                if json || name == "success" || name == "help" { #expect(result.stderr.isEmpty, "\(name) (json: \(json)) wrote to stderr") }
            }
        }
    }

    @Test("Every JSON line uses only keys from the fixed list")
    func jsonKeysAreFromTheAllowlist() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        // The documented keys (S2V-015 copies this list to the docs page). Written out here, not read from the code.
        let allowed: Set<String> = [
            "api_version", "type", "command", "audio", "image", "name", "duration_seconds", "sample_rate", "channels",
            "width", "height", "frames", "shape", "resolution", "placement", "enlarged", "too_small", "error", "code", "message",
        ]
        func keys(in value: Any) -> Set<String> {
            switch value {
            case let object as [String: Any]: Set(object.keys).union(object.values.flatMap { keys(in: $0) })
            case let array as [Any]: Set(array.flatMap { keys(in: $0) })
            default: []
            }
        }
        var seen: Set<String> = []
        for (_, arguments) in try runs(in: workspace) where arguments.last != "--help" {
            let result = try CommandProcess.run(arguments + ["--json"], environment: environment(workspace))
            let line = try JSONOutputLine(result.stdout)
            let used = keys(in: line.object)
            #expect(used.isSubset(of: allowed), "unexpected keys \(used.subtracting(allowed))")
            seen.formUnion(used)
        }
        // Between the success and error runs, every documented key is used.
        #expect(seen == allowed)
    }
}
