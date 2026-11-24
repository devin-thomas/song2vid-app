import Foundation
import Testing

/// Seam 5: `song2vid check <file>` with a single file (SPEC section 24.8), run as a separate process on generated media.
/// The expected keys and codes come from section 24.8 and the two-file `check` of section 14.3, not from the code under test.
@Suite("song2vid check with one file")
struct CommandCheckOneFileTests {
    private func compact(_ value: Any?) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: try #require(value), options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: An audio file alone

    @Test("A song alone reports only the audio keys, with the same values as the two-file check")
    func audioAloneJSON() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        // 2.5 s at 22,050 Hz mono is 55,125 frames, so the length is exactly 2.5.
        let audio = try workspace.tone("short song.wav", seconds: 2.5, sampleRate: 22_050, channels: 1)
        let image = try workspace.picture(width: 640, height: 360)

        let result = try CommandProcess.run(["check", audio, "--json"])
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        let line = try JSONOutputLine(result.stdout)
        #expect(Set(line.object.keys) == ["api_version", "type", "command", "audio"])
        #expect(line["api_version"] as? String == "1")
        #expect(line["type"] as? String == "result")
        #expect(line["command"] as? String == "check")
        let song = try #require(line.child("audio"))
        #expect(song["name"] as? String == "short song.wav")
        #expect(song["duration_seconds"] as? Double == 2.5)
        #expect(song["sample_rate"] as? Int == 22_050)
        #expect(song["channels"] as? Int == 1)

        let both = try JSONOutputLine(try CommandProcess.run(["check", audio, image, "--json"]).stdout)
        #expect(try compact(line["audio"]) == compact(both["audio"]))
    }

    @Test("A song alone in text shows the audio facts and nothing about an image or output sizes")
    func audioAloneText() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone("song.wav", seconds: 125, sampleRate: 8_000, channels: 2)
        let image = try workspace.picture(width: 640, height: 360)

        let result = try CommandProcess.run(["check", audio])
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == """
        Audio
          File:         song.wav
          Length:       2:05 (125.0 seconds)
          Sample rate:  8000 Hz
          Channels:     2 (stereo)

        """)
        // The same lines head the two-file report.
        let both = try CommandProcess.run(["check", audio, image])
        #expect(both.stdout.hasPrefix(result.stdout))
    }

    // MARK: An image alone

    @Test("An image alone reports only the image keys and the whole output-size table")
    func imageAloneJSON() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone()
        let image = try workspace.picture("front.png", width: 1000, height: 800)

        let result = try CommandProcess.run(["check", image, "-j"])
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        let line = try JSONOutputLine(result.stdout)
        #expect(Set(line.object.keys) == ["api_version", "type", "command", "image", "frames"])
        #expect(line["command"] as? String == "check")
        let picture = try #require(line.child("image"))
        #expect(picture["name"] as? String == "front.png")
        #expect(picture["width"] as? Int == 1000)
        #expect(picture["height"] as? Int == 800)

        // 12 shape and resolution pairs plus Original, with the SPEC section 5 sizes.
        #expect(line.frames.count == CommandCheckTests.specTable.count + 1)
        for row in CommandCheckTests.specTable {
            let match = line.frames.first { $0["shape"] as? String == row.shape && $0["resolution"] as? String == row.resolution }
            #expect(match?["width"] as? Int == row.width, "\(row.shape) \(row.resolution) width")
            #expect(match?["height"] as? Int == row.height, "\(row.shape) \(row.resolution) height")
            #expect(match?["placement"] as? String == row.placement, "\(row.shape) \(row.resolution) placement")
        }

        let both = try JSONOutputLine(try CommandProcess.run(["check", audio, image, "--json"]).stdout)
        #expect(try compact(line["image"]) == compact(both["image"]))
        #expect(try compact(line["frames"]) == compact(both["frames"]))
    }

    @Test("An image alone in text shows the image facts and the output sizes, and nothing about audio")
    func imageAloneText() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone()
        // Orientation 6 turns a 600x400 picture on its side, so it is 400 wide and 600 high.
        let image = try workspace.picture("turned.png", width: 600, height: 400, orientation: 6)

        let result = try CommandProcess.run(["check", image])
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("Image\n  File:         turned.png\n  Size:         400×600 pixels\n\nOutput sizes\n"))
        #expect(!result.stdout.contains("Audio"))
        #expect(!result.stdout.contains("Sample rate"))
        // The same lines end the two-file report.
        let both = try CommandProcess.run(["check", audio, image])
        #expect(both.stdout.hasSuffix(result.stdout))
    }

    // MARK: The type comes from the contents

    @Test("A picture named like a song is read as a picture, and a song named like a picture as a song")
    func contentsDecideTheKind() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        try FileManager.default.copyItem(atPath: try workspace.picture("real.png", width: 320, height: 200), toPath: workspace.path("looks-like-a-song.mp3"))
        try FileManager.default.copyItem(atPath: try workspace.tone("real.wav"), toPath: workspace.path("looks-like-a-picture.png"))

        let picture = try JSONOutputLine(try CommandProcess.run(["check", workspace.path("looks-like-a-song.mp3"), "-j"]).stdout)
        #expect(picture.child("image")?["name"] as? String == "looks-like-a-song.mp3")
        #expect(picture.child("image")?["width"] as? Int == 320)
        #expect(picture["audio"] == nil)

        let song = try JSONOutputLine(try CommandProcess.run(["check", workspace.path("looks-like-a-picture.png"), "-j"]).stdout)
        #expect(song.child("audio")?["name"] as? String == "looks-like-a-picture.png")
        #expect(song["image"] == nil)
        #expect(song["frames"] == nil)
    }

    // MARK: An unreadable or missing file alone

    struct Failure: CustomTestStringConvertible, Sendable {
        /// What to create: a file of this name holding text that is not media, nothing at all, or a folder.
        enum Kind: Sendable { case notMedia, missing, folder }
        let name: String
        let kind: Kind
        let status: Int32
        let code: String
        let message: String
        var testDescription: String { "\(name) (\(kind)) -> \(status) \(code)" }
    }

    static let failures = [
        // Not media: the kind comes from the name, so a song type is audio_unreadable and anything else image_unreadable.
        Failure(name: "not-a-song.mp3", kind: .notMedia, status: 3, code: "audio_unreadable", message: "Song2Vid can't read this audio file."),
        Failure(name: "not-a-song.m4a", kind: .notMedia, status: 3, code: "audio_unreadable", message: "Song2Vid can't read this audio file."),
        Failure(name: "not-a-picture.png", kind: .notMedia, status: 3, code: "image_unreadable", message: "Song2Vid can't read this image file."),
        Failure(name: "notes.txt", kind: .notMedia, status: 3, code: "image_unreadable", message: "Song2Vid can't read this image file."),
        Failure(name: "no-extension", kind: .notMedia, status: 3, code: "image_unreadable", message: "Song2Vid can't read this image file."),
        Failure(name: "a-folder", kind: .folder, status: 3, code: "image_unreadable", message: "Song2Vid can't read this image file."),
        Failure(name: "a-folder.wav", kind: .folder, status: 3, code: "audio_unreadable", message: "Song2Vid can't read this audio file."),
        // Missing: the same rule picks the code.
        Failure(name: "gone.wav", kind: .missing, status: 1, code: "audio_not_found", message: "The audio file was not found."),
        Failure(name: "gone.png", kind: .missing, status: 1, code: "image_not_found", message: "The image file was not found."),
        Failure(name: "gone", kind: .missing, status: 1, code: "image_not_found", message: "The image file was not found."),
    ]

    private func path(_ failure: Failure, in workspace: CommandWorkspace) throws -> String {
        switch failure.kind {
        case .notMedia: return try workspace.notMedia(failure.name)
        case .missing: return workspace.path(failure.name)
        case .folder:
            try FileManager.default.createDirectory(at: workspace.url(failure.name), withIntermediateDirectories: true)
            return workspace.path(failure.name)
        }
    }

    @Test("A file alone that is unreadable or missing gives its status and one line on stderr", arguments: failures)
    func textError(failure: Failure) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let result = try CommandProcess.run(["check", try path(failure, in: workspace)])
        #expect(result.status == failure.status)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr == failure.message + "\n")
    }

    @Test("Under --json the same failure is one error line on stdout, and stderr is empty", arguments: failures)
    func jsonError(failure: Failure) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let result = try CommandProcess.run(["check", try path(failure, in: workspace), "--json"])
        #expect(result.status == failure.status)
        #expect(result.stderr.isEmpty)
        let line = try JSONOutputLine(result.stdout)
        #expect(line["api_version"] as? String == "1")
        #expect(line["type"] as? String == "error")
        #expect(line.child("error")?["code"] as? String == failure.code)
        #expect(line.child("error")?["message"] as? String == failure.message)
    }

    @Test("The error never names the file, its folder or its contents")
    func errorsStayPrivate() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let file = try workspace.notMedia("secret-name.mp3")
        for arguments in [["check", file], ["check", file, "-j"], ["check", workspace.path("secret-gone.png")]] {
            let result = try CommandProcess.run(arguments)
            let combined = result.stdout + result.stderr
            for text in ["secret-name", "secret-gone", CommandWorkspace.folderMarker, "plain text"] {
                #expect(!combined.contains(text), "\(arguments) printed \(text)")
            }
        }
    }

    @Test("Two-file check is unchanged by the one-file form: a missing second file is still image_not_found")
    func twoFilesAreStillTwoFiles() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let result = try CommandProcess.run(["check", try workspace.tone(), workspace.path("gone.wav"), "-j"])
        #expect(result.status == 1)
        #expect(try JSONOutputLine(result.stdout).child("error")?["code"] as? String == "image_not_found")
    }
}
