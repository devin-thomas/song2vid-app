import AVFoundation
import Foundation
import Testing

/// What an MP4 holds, read back with AVFoundation, which is independent of the code that wrote it.
struct VideoFacts {
    let width: Int
    let height: Int
    let seconds: Double
    let hasVideoTrack: Bool
    let hasAudioTrack: Bool

    init(of url: URL) async throws {
        let asset = AVURLAsset(url: url)
        seconds = try await asset.load(.duration).seconds
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        hasVideoTrack = !video.isEmpty
        hasAudioTrack = !audio.isEmpty
        let size = try await video.first?.load(.naturalSize) ?? .zero
        width = Int(size.width.rounded())
        height = Int(size.height.rounded())
    }
}

/// Seam 5 (SPEC section 18): `song2vid make` run as a separate process on generated media.
/// Expected sizes come from the SPEC section 5 table and worked examples, and lengths from the generated tone.
@Suite("song2vid make")
struct CommandMakeTests {
    /// A 1000x800 image at 480p, by hand from SPEC section 5: every scale is under 1 (0.48 to 0.8), so nothing is enlarged.
    /// 16:9 fits 854x480 (the image is 600x480 inside bars); 9:16 fits 480x854; 1:1 and 4:3 crop; Original keeps 1000x800.
    static let shapes: [(shape: String, width: Int, height: Int, placement: String)] = [
        ("16:9", 854, 480, "fit"), ("9:16", 480, 854, "fit"), ("1:1", 480, 480, "crop"), ("4:3", 640, 480, "crop"),
        ("original", 1000, 800, "fit"),
    ]

    private func inputs(_ workspace: CommandWorkspace, seconds: Double = 3) throws -> (audio: String, image: String) {
        (try workspace.tone(seconds: seconds), try workspace.picture(width: 1000, height: 800))
    }

    private func expectValidationError(
        _ result: CommandProcess.Result, _ message: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let lines = result.stderr.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(result.stdout.isEmpty, sourceLocation: sourceLocation)
        #expect(lines.suffix(2) == [Substring(message), ""], sourceLocation: sourceLocation)
        #expect(lines.dropLast(2).allSatisfy { $0.hasPrefix("Checking files (") }, sourceLocation: sourceLocation)
    }

    // MARK: Making each shape

    @Test("make writes an MP4 of the right size and length with a video track and an audio track, for each Frame Shape", arguments: shapes)
    func makesEachShape(row: (shape: String, width: Int, height: Int, placement: String)) async throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let (audio, image) = try inputs(workspace, seconds: 3)
        let options = row.shape == "original" ? ["-s", "original"] : ["-s", row.shape, "-r", "480p"]

        let result = try CommandProcess.run(["make", audio, image, "-o", workspace.path("out.mp4"), "--json"] + options)
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        let line = try JSONOutputLine.final(result.stdout)
        #expect(line["type"] as? String == "result")
        #expect(line["command"] as? String == "make")
        #expect(line["api_version"] as? String == "1")
        #expect(line["placement"] as? String == row.placement)
        #expect(line["enlarged"] as? Bool == false)
        #expect(line["dry_run"] as? Bool == false)
        let output = try #require(line.child("output"))
        #expect(output["name"] as? String == "out.mp4")
        #expect(output["width"] as? Int == row.width)
        #expect(output["height"] as? Int == row.height)

        // What is on disk, read back by AVFoundation.
        let facts = try await VideoFacts(of: workspace.url("out.mp4"))
        #expect(facts.width == row.width)
        #expect(facts.height == row.height)
        #expect(abs(facts.seconds - 3) <= 0.1)
        #expect(facts.hasVideoTrack)
        #expect(facts.hasAudioTrack)
        let size = try FileManager.default.attributesOfItem(atPath: workspace.path("out.mp4"))[.size] as? Int
        #expect(output["bytes"] as? Int == size)
        #expect((size ?? 0) > 0)
        // Only the output is new: the temporary file is gone.
        #expect(try workspace.listing() == ["cover.png", "out.mp4", "song.wav"])
    }

    @Test("make with the default options makes a 1080p 16:9 video named after the song, in the current folder")
    func defaultsAndText() async throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone("My Song.wav", seconds: 2)
        let image = try workspace.picture(width: 1000, height: 800)

        let result = try CommandProcess.run(["make", audio, image], currentDirectory: workspace.folder)
        #expect(result.status == 0)
        // Headless, progress goes to stderr as plain lines; the result is on stdout.
        #expect(JSONOutputLine.plainProgressLinesOnly(result.stderr.split(separator: "\n")))
        // 1000x800 at 1080p is enlarged (scale 1.35 into 1920x1080 fit: 1350x1080).
        for part in ["My Song.mp4", "1920×1080", "Fit with bars", "enlarged", "0:02"] {
            #expect(result.stdout.contains(part), "the text result is missing \(part)")
        }
        let facts = try await VideoFacts(of: workspace.url("My Song.mp4"))
        #expect(facts.width == 1920 && facts.height == 1080)
        #expect(abs(facts.seconds - 2) <= 0.1)
        #expect(try workspace.listing() == ["My Song.mp4", "My Song.wav", "cover.png"])
    }

    @Test("--crop picks the part of the image a crop keeps")
    func cropPosition() async throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        // Red left half, blue right half, 1600x600. At 4:3 and 480p the image is scaled by 0.8 to 1280x480 and 640 of it
        // shows: with h = 0 all of it is red, with h = 1 all of it is blue.
        let audio = try workspace.tone(seconds: 1)
        let image = try workspace.picture(width: 1600, height: 600)
        for (crop, expectRed) in [("0,0.5", true), ("1,0.5", false)] {
            let output = workspace.path("crop-\(crop.prefix(1)).mp4")
            let result = try CommandProcess.run(["make", audio, image, "-s", "4:3", "-r", "480p", "-c", crop, "-o", output])
            #expect(result.status == 0)
            let frame = try await TestMedia.firstFrame(of: URL(fileURLWithPath: output))
            let pixel = frame.rgb(x: frame.width / 2, y: frame.height / 2)
            #expect(expectRed ? (pixel.r > 200 && pixel.b < 60) : (pixel.b > 200 && pixel.r < 60), "crop \(crop) gave \(pixel)")
        }
    }

    // MARK: Dry run

    @Test("--dry-run reports what would be made and writes nothing", arguments: shapes)
    func dryRun(row: (shape: String, width: Int, height: Int, placement: String)) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let (audio, image) = try inputs(workspace, seconds: 2.5)
        let before = try workspace.listing()
        let options = row.shape == "original" ? ["-s", "original"] : ["-s", row.shape, "-r", "480p"]

        let json = try CommandProcess.run(["make", audio, image, "-n", "-o", workspace.path("planned.mp4"), "--json"] + options)
        #expect(json.status == 0)
        #expect(json.stderr.isEmpty)
        let line = try JSONOutputLine(json.stdout)
        #expect(line["type"] as? String == "result")
        #expect(line["dry_run"] as? Bool == true)
        #expect(line["placement"] as? String == row.placement)
        #expect(line["enlarged"] as? Bool == false)
        let output = try #require(line.child("output"))
        #expect(output["name"] as? String == "planned.mp4")
        #expect(output["width"] as? Int == row.width)
        #expect(output["height"] as? Int == row.height)
        #expect(output["duration_seconds"] as? Double == 2.5)
        // Nothing was written, so there is no size yet.
        #expect(output["bytes"] is NSNull)
        #expect(try workspace.listing() == before)

        let text = try CommandProcess.run(["make", audio, image, "--dry-run", "-o", workspace.path("planned.mp4")] + options)
        #expect(text.status == 0)
        #expect(text.stderr.isEmpty)
        #expect(text.stdout.contains("Would make planned.mp4"))
        #expect(text.stdout.contains("\(row.width)×\(row.height)"))
        #expect(try workspace.listing() == before)
    }

    @Test("--dry-run still finds every problem a real run would")
    func dryRunValidates() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let (audio, _) = try inputs(workspace)
        let result = try CommandProcess.run(["make", audio, workspace.path("missing.png"), "-n"])
        #expect(result.status == 1)
        #expect(result.stderr == "The image file was not found.\n")
        let existing = workspace.url("taken.mp4")
        try Data("not changed".utf8).write(to: existing)
        let image = try workspace.picture(width: 100, height: 100)
        let taken = try CommandProcess.run(["make", audio, image, "-n", "-o", existing.path])
        #expect(taken.status == 4)
        #expect(taken.stderr == "The output file already exists. Use --overwrite to replace it.\n")
        // With --overwrite a dry run is fine, and still changes nothing.
        let allowed = try CommandProcess.run(["make", audio, image, "-n", "-w", "-o", existing.path])
        #expect(allowed.status == 0)
        #expect(try Data(contentsOf: existing) == Data("not changed".utf8))
    }

    // MARK: The input files

    @Test("make leaves the song and the image exactly as they were, content and modification date", arguments: [false, true])
    func inputsAreUntouched(overwrite: Bool) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let (audio, image) = try inputs(workspace)
        let output = workspace.url("out.mp4")
        if overwrite { try Data("old video".utf8).write(to: output) }
        func snapshot() throws -> [String: (Data, Date)] {
            var result: [String: (Data, Date)] = [:]
            for path in [audio, image] {
                let attributes = try FileManager.default.attributesOfItem(atPath: path)
                result[path] = (try Data(contentsOf: URL(fileURLWithPath: path)), try #require(attributes[.modificationDate] as? Date))
            }
            return result
        }
        // Make the modification dates old, so a rewrite would show.
        let past = Date(timeIntervalSince1970: 1_000_000_000)
        for path in [audio, image] { try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: path) }
        let before = try snapshot()

        let result = try CommandProcess.run(["make", audio, image, "-o", output.path, "-s", "1:1", "-r", "480p"] + (overwrite ? ["-w"] : []))
        #expect(result.status == 0)
        let after = try snapshot()
        for path in [audio, image] {
            #expect(after[path]?.0 == before[path]?.0, "content of an input changed")
            #expect(after[path]?.1 == before[path]?.1, "modification date of an input changed")
        }
    }

    /// One way for an input to be wrong, with what must come back.
    struct InputFailure: CustomTestStringConvertible, Sendable {
        let name: String
        let audio: String
        let image: String
        let extra: [String]
        let status: Int32
        let code: String
        let message: String
        var testDescription: String { name }
    }

    static let inputFailures = [
        InputFailure(name: "audio missing", audio: "missing.wav", image: "cover.png", extra: [], status: 1, code: "audio_not_found", message: "The audio file was not found."),
        InputFailure(name: "image missing", audio: "song.wav", image: "missing.png", extra: [], status: 1, code: "image_not_found", message: "The image file was not found."),
        InputFailure(name: "audio is not audio", audio: "fake.mp3", image: "cover.png", extra: [], status: 3, code: "audio_unreadable", message: "Song2Vid can't read this audio file."),
        InputFailure(name: "image is not an image", audio: "song.wav", image: "fake.png", extra: [], status: 3, code: "image_unreadable", message: "Song2Vid can't read this image file."),
        // A missing file comes before an unreadable one, as in check.
        InputFailure(name: "missing image beats unreadable audio", audio: "fake.mp3", image: "missing.png", extra: [], status: 1, code: "image_not_found", message: "The image file was not found."),
        // Original needs 16 pixels on each side (SPEC 5 rule 6); other shapes don't.
        InputFailure(name: "image too small for original", audio: "song.wav", image: "tiny.png", extra: ["-s", "original"], status: 3, code: "image_too_small", message: "This image is too small. Original needs an image of at least 16×16 pixels."),
        // Input problems come before output problems.
        InputFailure(name: "input problem beats a bad output name", audio: "song.wav", image: "missing.png", extra: ["-o", "out.mov"], status: 1, code: "image_not_found", message: "The image file was not found."),
    ]

    @Test("An input that is missing or unusable gives its exit status and writes nothing", arguments: inputFailures)
    func inputFailure(failure: InputFailure) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        try workspace.tone()
        try workspace.picture(width: 300, height: 200)
        try workspace.picture("tiny.png", width: 15, height: 40)
        try workspace.notMedia("fake.mp3")
        try workspace.notMedia("fake.png")
        let before = try workspace.listing()
        let arguments = ["make", workspace.path(failure.audio), workspace.path(failure.image)] + failure.extra

        let text = try CommandProcess.run(arguments, currentDirectory: workspace.folder)
        #expect(text.status == failure.status)
        expectValidationError(text, failure.message)
        let json = try CommandProcess.run(arguments + ["--json"], currentDirectory: workspace.folder)
        #expect(json.status == failure.status)
        #expect(json.stderr.isEmpty)
        let error = try #require(try JSONOutputLine.final(json.stdout).child("error"))
        #expect(error["code"] as? String == failure.code)
        #expect(error["message"] as? String == failure.message)
        #expect(try workspace.listing() == before)
    }

    @Test("A tiny image is fine for the shapes that fit or crop it")
    func tinyImageForOtherShapes() async throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone(seconds: 1)
        let image = try workspace.picture(width: 15, height: 15)
        let result = try CommandProcess.run(["make", audio, image, "-s", "1:1", "-r", "480p", "-o", workspace.path("tiny.mp4"), "--json"])
        #expect(result.status == 0)
        #expect(try JSONOutputLine.final(result.stdout)["enlarged"] as? Bool == true)
        let facts = try await VideoFacts(of: workspace.url("tiny.mp4"))
        #expect(facts.width == 480 && facts.height == 480)
    }

    // MARK: The output

    @Test("The output must end in .mp4", arguments: ["out.mov", "out", "out.mp4.txt", ".mp4", "out.mp3", "folder/"])
    func outputMustBeMP4(name: String) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let (audio, image) = try inputs(workspace)
        let before = try workspace.listing()
        let result = try CommandProcess.run(["make", audio, image, "--out=\(workspace.path(name))"])
        #expect(result.status == 4)
        expectValidationError(result, "The output file name must end in .mp4.")
        let json = try CommandProcess.run(["make", audio, image, "--out=\(workspace.path(name))", "-j"])
        #expect(json.status == 4)
        #expect(json.stderr.isEmpty)
        #expect(try JSONOutputLine.final(json.stdout).child("error")?["code"] as? String == "output_not_mp4")
        #expect(try workspace.listing() == before)
    }

    @Test("A folder that doesn't exist or can't be written to is an output error, and nothing is made")
    func outputFolderProblems() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let (audio, image) = try inputs(workspace)
        let missing = try CommandProcess.run(["make", audio, image, "-o", workspace.path("no-such-folder/out.mp4"), "--json"])
        #expect(missing.status == 4)
        let missingError = try #require(try JSONOutputLine.final(missing.stdout).child("error"))
        #expect(missingError["code"] as? String == "output_not_writable")
        #expect(missingError["message"] as? String == "The output folder was not found.")

        let locked = workspace.url("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let readOnly = try CommandProcess.run(["make", audio, image, "-o", locked.appendingPathComponent("out.mp4").path])
        #expect(readOnly.status == 4)
        expectValidationError(readOnly, "Song2Vid can't write to the output folder.")
        #expect(try FileManager.default.contentsOfDirectory(atPath: locked.path).isEmpty)
    }

    @Test("An existing output is an error without --overwrite, and is left exactly as it was")
    func existingOutputRefused() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let (audio, image) = try inputs(workspace)
        let existing = workspace.url("out.mp4")
        try Data("my earlier video".utf8).write(to: existing)
        let before = try workspace.listing()

        let text = try CommandProcess.run(["make", audio, image, "-o", existing.path])
        #expect(text.status == 4)
        expectValidationError(text, "The output file already exists. Use --overwrite to replace it.")
        let json = try CommandProcess.run(["make", audio, image, "-o", existing.path, "--json"])
        #expect(json.status == 4)
        #expect(json.stderr.isEmpty)
        let error = try #require(try JSONOutputLine.final(json.stdout).child("error"))
        #expect(error["code"] as? String == "output_exists")
        #expect(error["message"] as? String == "The output file already exists. Use --overwrite to replace it.")
        #expect(try Data(contentsOf: existing) == Data("my earlier video".utf8))
        #expect(try workspace.listing() == before)
    }

    @Test("--overwrite replaces an existing output with the new video, and only then")
    func overwriteReplaces() async throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let (audio, image) = try inputs(workspace)
        let existing = workspace.url("out.mp4")
        try Data("my earlier video".utf8).write(to: existing)

        for flag in ["-w", "--overwrite"] {
            let result = try CommandProcess.run(["make", audio, image, "-o", existing.path, flag, "-s", "1:1", "-r", "480p", "-j"])
            #expect(result.status == 0)
            let facts = try await VideoFacts(of: existing)
            #expect(facts.width == 480 && facts.height == 480)
            #expect(abs(facts.seconds - 3) <= 0.1)
            #expect(try workspace.listing() == ["cover.png", "out.mp4", "song.wav"])
            // Put the old marker back so the second spelling replaces it too.
            try Data("my earlier video".utf8).write(to: existing)
        }
    }

    @Test("--overwrite never replaces a folder or the song")
    func overwriteLimits() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let (audio, image) = try inputs(workspace)
        let folder = workspace.url("already.mp4")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let refused = try CommandProcess.run(["make", audio, image, "-o", folder.path, "-w"])
        #expect(refused.status == 4)
        expectValidationError(refused, "The output can't be a folder.")
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue)

        // The default output name is the song's own name with .mp4, which is the song itself when it already ends in .mp4.
        // The input is protected even with --overwrite.
        try FileManager.default.copyItem(atPath: audio, toPath: workspace.path("track.mp4"))
        let original = try Data(contentsOf: workspace.url("track.mp4"))
        let same = try CommandProcess.run(["make", workspace.path("track.mp4"), image, "-w"], currentDirectory: workspace.folder)
        #expect(same.status == 4)
        expectValidationError(same, "The output can't be one of the input files.")
        #expect(try Data(contentsOf: workspace.url("track.mp4")) == original)
    }
}
