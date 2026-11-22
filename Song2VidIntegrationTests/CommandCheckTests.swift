import Foundation
import Testing

/// Seam 5 (SPEC section 18): `song2vid check` run as a separate process on generated media.
/// Expected sizes come from the SPEC section 5 table and worked examples, not from the code under test.
@Suite("song2vid check")
struct CommandCheckTests {
    /// One row per Frame Shape and Resolution, as SPEC section 5 gives them: shape, resolution, size, placement.
    static let specTable: [(shape: String, resolution: String, width: Int, height: Int, placement: String)] = [
        ("16:9", "480p", 854, 480, "fit"), ("16:9", "1080p", 1920, 1080, "fit"), ("16:9", "2160p", 3840, 2160, "fit"),
        ("9:16", "480p", 480, 854, "fit"), ("9:16", "1080p", 1080, 1920, "fit"), ("9:16", "2160p", 2160, 3840, "fit"),
        ("1:1", "480p", 480, 480, "crop"), ("1:1", "1080p", 1080, 1080, "crop"), ("1:1", "2160p", 2160, 2160, "crop"),
        ("4:3", "480p", 640, 480, "crop"), ("4:3", "1080p", 1440, 1080, "crop"), ("4:3", "2160p", 2880, 2160, "crop"),
    ]

    @Test("check --json lists every Frame Shape and Resolution with the SPEC 5 sizes, placement and enlarged flags")
    func jsonFrameTable() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        // 1000x800 is enlarged exactly when the frame's short side is 1080 or 2160, worked by hand from SPEC section 5:
        // at 480p every scale is under 1 (0.48 to 0.64); at 1080p and 2160p every scale is over 1 (1.08 and up).
        let audio = try workspace.tone()
        let image = try workspace.picture(width: 1000, height: 800)

        let result = try CommandProcess.run(["check", audio, image, "--json"])
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        let line = try JSONOutputLine(result.stdout)
        #expect(line["api_version"] as? String == "1")
        #expect(line["type"] as? String == "result")
        #expect(line["command"] as? String == "check")

        let frames = line.frames
        #expect(frames.count == Self.specTable.count + 1)
        for row in Self.specTable {
            let match = frames.first { $0["shape"] as? String == row.shape && $0["resolution"] as? String == row.resolution }
            #expect(match?["width"] as? Int == row.width, "\(row.shape) \(row.resolution) width")
            #expect(match?["height"] as? Int == row.height, "\(row.shape) \(row.resolution) height")
            #expect(match?["placement"] as? String == row.placement, "\(row.shape) \(row.resolution) placement")
            #expect(match?["enlarged"] as? Bool == (row.resolution != "480p"), "\(row.shape) \(row.resolution) enlarged")
            #expect(match?["too_small"] as? Bool == false)
        }
        // Original keeps the image's own size, which is within the limit.
        let original = frames.first { $0["shape"] as? String == "original" }
        #expect(original?["width"] as? Int == 1000)
        #expect(original?["height"] as? Int == 800)
        #expect(original?["resolution"] is NSNull)
        #expect(original?["too_small"] as? Bool == false)
    }

    // MARK: What it reports about the files

    @Test("check reports the song's length, sample rate and channels, and the image's size, by file name")
    func jsonFacts() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        // 2.5 s at 22,050 Hz mono is 55,125 frames, so the length is exactly 2.5.
        let audio = try workspace.tone("short song.wav", seconds: 2.5, sampleRate: 22_050, channels: 1)
        let image = try workspace.picture("front.png", width: 640, height: 360)

        let line = try JSONOutputLine(try CommandProcess.run(["check", audio, image, "-j"]).stdout)
        let song = try #require(line.child("audio"))
        #expect(song["name"] as? String == "short song.wav")
        #expect(song["duration_seconds"] as? Double == 2.5)
        #expect(song["sample_rate"] as? Int == 22_050)
        #expect(song["channels"] as? Int == 1)
        let picture = try #require(line.child("image"))
        #expect(picture["name"] as? String == "front.png")
        #expect(picture["width"] as? Int == 640)
        #expect(picture["height"] as? Int == 360)
    }

    @Test("A file name with quotes and accents is written as valid JSON and comes back unchanged")
    func jsonEscapesNames() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let name = "s\u{F3}ng \"live\" \\ take.wav"
        let audio = try workspace.tone(name)
        let image = try workspace.picture(width: 100, height: 100)
        let line = try JSONOutputLine(try CommandProcess.run(["check", audio, image, "--json"]).stdout)
        #expect(line.child("audio")?["name"] as? String == name)
    }

    @Test("The image's size is read after its orientation tag")
    func orientationTagSwapsSides() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone()
        // Orientation 6 turns a 600x400 picture on its side, so it is 400 wide and 600 high.
        let image = try workspace.picture(width: 600, height: 400, orientation: 6)
        let line = try JSONOutputLine(try CommandProcess.run(["check", audio, image, "--json"]).stdout)
        #expect(line.child("image")?["width"] as? Int == 400)
        #expect(line.child("image")?["height"] as? Int == 600)
        let original = try #require(line.frames.first { $0["shape"] as? String == "original" })
        #expect(original["width"] as? Int == 400)
        #expect(original["height"] as? Int == 600)
    }

    struct OriginalCase: CustomTestStringConvertible, Sendable {
        let imageWidth: Int, imageHeight: Int
        let frameWidth: Int, frameHeight: Int
        let placement: String
        var testDescription: String { "\(imageWidth)x\(imageHeight) -> \(frameWidth)x\(frameHeight) \(placement)" }
    }

    /// Original, worked by hand from the SPEC section 5 rules.
    static let originalCases = [
        // The smallest image that is accepted keeps its size.
        OriginalCase(imageWidth: 16, imageHeight: 16, frameWidth: 16, frameHeight: 16, placement: "fit"),
        // Odd sides lose one pixel (rule 5).
        OriginalCase(imageWidth: 1001, imageHeight: 801, frameWidth: 1000, frameHeight: 800, placement: "fit"),
        // s = 0.96, so it is scaled to floor(4000 x 0.96) by floor(2000 x 0.96).
        OriginalCase(imageWidth: 4000, imageHeight: 2000, frameWidth: 3840, frameHeight: 1920, placement: "fit"),
        // s = 0.9948, under 1% too big: trimmed, not scaled (rule 3).
        OriginalCase(imageWidth: 3860, imageHeight: 2160, frameWidth: 3840, frameHeight: 2160, placement: "crop"),
        // Portrait: the limit is 2160x3840 and s = 0.768.
        OriginalCase(imageWidth: 1000, imageHeight: 5000, frameWidth: 768, frameHeight: 3840, placement: "fit"),
    ]

    @Test("Original follows the SPEC 5 rules for the image's own size", arguments: originalCases)
    func originalSizes(example: OriginalCase) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone()
        let picture = try workspace.picture(width: example.imageWidth, height: example.imageHeight)
        let line = try JSONOutputLine(try CommandProcess.run(["check", audio, picture, "--json"]).stdout)
        let original = try #require(line.frames.first { $0["shape"] as? String == "original" })
        #expect(original["width"] as? Int == example.frameWidth)
        #expect(original["height"] as? Int == example.frameHeight)
        #expect(original["placement"] as? String == example.placement)
        #expect(original["enlarged"] as? Bool == false)
        #expect(original["too_small"] as? Bool == false)
    }

    @Test("Original reports too small under 16 pixels, and the other shapes are still listed")
    func originalTooSmall() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone()
        let picture = try workspace.picture(width: 15, height: 40)
        let result = try CommandProcess.run(["check", audio, picture, "--json"])
        #expect(result.status == 0)
        let line = try JSONOutputLine(result.stdout)
        let original = try #require(line.frames.first { $0["shape"] as? String == "original" })
        #expect(original["too_small"] as? Bool == true)
        #expect(original["width"] is NSNull && original["height"] is NSNull && original["placement"] is NSNull)
        // 15x40 fills 1:1 at 480p from a scale of 32, so it is enlarged, and the row is still there.
        let square = try #require(line.frames.first { $0["shape"] as? String == "1:1" && $0["resolution"] as? String == "480p" })
        #expect(square["width"] as? Int == 480)
        #expect(square["enlarged"] as? Bool == true)
        #expect(square["too_small"] as? Bool == false)

        let text = try CommandProcess.run(["check", audio, picture])
        #expect(text.status == 0)
        #expect(text.stdout.contains("too small"))
    }

    @Test("A large image is not enlarged in any shape or resolution")
    func largeImageIsNeverEnlarged() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone()
        // 4000x3000 never needs a scale over 0.96 (16:9 at 2160p is 0.72; 1:1 at 2160p is 0.72; 4:3 at 2160p is 0.72).
        let picture = try workspace.picture(width: 4000, height: 3000)
        let line = try JSONOutputLine(try CommandProcess.run(["check", audio, picture, "--json"]).stdout)
        #expect(line.frames.count == 13)
        #expect(line.frames.allSatisfy { $0["enlarged"] as? Bool == false })
    }

    @Test("Text output names both files and lists every size, without a folder")
    func textOutput() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone()
        let image = try workspace.picture(width: 1000, height: 800)
        let result = try CommandProcess.run(["check", audio, image])
        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        for part in ["song.wav", "cover.png", "0:03", "44100 Hz", "2 (stereo)", "1000×800", "Fit with bars", "Crop", "will be enlarged"] {
            #expect(result.stdout.contains(part), "text output is missing \(part)")
        }
        for row in Self.specTable {
            #expect(result.stdout.contains("\(row.width)×\(row.height)"), "text output is missing \(row.width)×\(row.height)")
        }
        #expect(!result.stdout.contains(CommandWorkspace.folderMarker))
        #expect(result.stdout.hasSuffix("\n") && !result.stdout.hasSuffix("\n\n"))
    }

    @Test("-j and --json mean the same, in front of the files or after them")
    func jsonOptionSpellings() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone()
        let image = try workspace.picture(width: 800, height: 600)
        let outputs = try [["check", audio, image, "-j"], ["check", audio, image, "--json"], ["check", "-j", audio, image]]
            .map { try CommandProcess.run($0).stdout }
        #expect(outputs[0] == outputs[1] && outputs[1] == outputs[2])
        #expect(outputs[0].hasPrefix("{\"api_version\":\"1\",\"type\":\"result\""))
    }

    @Test("check writes nothing")
    func writesNothing() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let audio = try workspace.tone()
        let image = try workspace.picture(width: 800, height: 600)
        let before = try workspace.listing()
        _ = try CommandProcess.run(["check", audio, image], currentDirectory: workspace.folder)
        _ = try CommandProcess.run(["check", audio, image, "--json"], currentDirectory: workspace.folder)
        #expect(try workspace.listing() == before)
    }

    @Test("Relative paths work, and only the file names are reported")
    func relativePaths() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        try workspace.tone("here.wav")
        try workspace.picture("there.png", width: 500, height: 500)
        let result = try CommandProcess.run(["check", "./here.wav", "there.png", "--json"], currentDirectory: workspace.folder)
        #expect(result.status == 0)
        let line = try JSONOutputLine(result.stdout)
        #expect(line.child("audio")?["name"] as? String == "here.wav")
        #expect(line.child("image")?["name"] as? String == "there.png")
    }
}
