import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@Suite("Song2Vid 1.2 command contract")
struct CommandContract12Tests {
    @Test("The Mac advertises both Apple Codecs, and an unavailable HEVC session stops make before writing")
    func encoders() throws {
        let detected = try CommandProcess.run(["encoders", "--json"])
        #expect(detected.status == 0)
        #expect(detected.stderr.isEmpty)
        let line = try JSONOutputLine(detected.stdout)
        #expect(line["api_version"] as? String == "1")
        #expect(line["type"] as? String == "result")
        #expect(line["command"] as? String == "encoders")
        let codecs = try #require(line.child("codecs") as? [String: [String: Any]])
        #expect(Set(codecs.keys) == ["h264", "hevc"])
        for codec in codecs.values {
            let available = try #require(codec["available"] as? Bool)
            if available {
                #expect(codec["encoder"] as? String == "apple")
            } else {
                #expect(codec["encoder"] is NSNull)
            }
        }
        #expect(codecs["h264"]?["available"] as? Bool == true)

        let text = try CommandProcess.run(["encoders"])
        #expect(text.status == 0)
        #expect(text.stderr.isEmpty)
        #expect(text.stdout.hasPrefix("H.264: Apple encoder\nHEVC: "))

        var environment = ProcessInfo.processInfo.environment
        environment["SONG2VID_TEST_DISABLE_HEVC"] = "1"
        let unavailable = try CommandProcess.run(["encoders", "-j"], environment: environment)
        #expect(unavailable.status == 0)
        let availability = try #require(try JSONOutputLine(unavailable.stdout).child("codecs")?["hevc"] as? [String: Any])
        #expect(availability["available"] as? Bool == false)
        #expect(availability["encoder"] is NSNull)

        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let song = try workspace.tone()
        let picture = try workspace.picture(width: 640, height: 480)
        let before = try workspace.listing()
        for options in [[], ["--dry-run"]] {
            let result = try CommandProcess.run(
                ["make", song, picture, "-C", "hevc", "-o", workspace.path("out.mp4"), "-j"] + options,
                environment: environment
            )
            #expect(result.status == 3)
            #expect(result.stderr.isEmpty)
            #expect(try JSONOutputLine.final(result.stdout).child("error")?["code"] as? String == "codec_unavailable")
            #expect(try workspace.listing() == before)
        }
    }

    @Test("HEVC MP4s have the correct size, duration, hvc1 sample description and AAC audio", arguments: [
        ("16:9", 854, 480), ("9:16", 480, 854), ("1:1", 480, 480), ("4:3", 640, 480), ("original", 640, 480),
    ])
    func hevc(shape: String, width: Int, height: Int) async throws {
        let detected = try CommandProcess.run(["encoders", "-j"])
        let codec = try #require(try JSONOutputLine(detected.stdout).child("codecs")?["hevc"] as? [String: Any])
        // The same suite also runs on Macs that cannot open an HEVC encoder.
        if codec["available"] as? Bool == false { return }
        #expect(codec["encoder"] as? String == "apple")

        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let song = try workspace.tone(seconds: 2.37)
        let picture = try workspace.picture(width: 641, height: 481)
        let output = workspace.url("out.mp4")
        let args = ["make", song, picture, "--codec=hevc", "-s", shape, "-o", output.path, "--json"]
            + (shape == "original" ? [] : ["-r", "480p"])
        let result = try CommandProcess.run(args)
        try #require(result.status == 0, "\(result.stdout)\(result.stderr)")
        #expect(result.stderr.isEmpty)
        try verifyLegacyMakeLines(result.stdout)
        let final = try JSONOutputLine.final(result.stdout)
        #expect(final["codec"] as? String == "hevc")
        #expect(final["encoder"] as? String == "apple")
        #expect(final["encoder_fallback"] as? Bool == false)

        let asset = AVURLAsset(url: output)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let videoTrack = try #require(videos.first)
        let audioTrack = try #require(audio.first)
        let videoFormat = try #require(try await videoTrack.load(.formatDescriptions).first)
        let audioFormat = try #require(try await audioTrack.load(.formatDescriptions).first)
        let size = CMVideoFormatDescriptionGetDimensions(videoFormat)
        #expect(Int(size.width) == width)
        #expect(Int(size.height) == height)
        #expect(CMFormatDescriptionGetMediaSubType(videoFormat) == kCMVideoCodecType_HEVC)
        #expect(CMFormatDescriptionGetMediaSubType(audioFormat) == kAudioFormatMPEG4AAC)
        #expect(abs(try await asset.load(.duration).seconds - 2.37) <= 0.1)
    }

    @Test("A 1.1 consumer can still read H.264 plans, videos and errors")
    func defaultCodecAndLegacyJSON() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let song = try workspace.tone()
        let picture = try workspace.picture(width: 640, height: 480)
        let output = workspace.path("out.mp4")
        let args = ["make", song, picture, "-o", output, "-r", "480p", "-j"]
        let plan = try CommandProcess.run(args + ["-n"])
        #expect(plan.status == 0)
        #expect(!FileManager.default.fileExists(atPath: output))
        let planned = try JSONOutputLine(plan.stdout)
        #expect(planned["codec"] as? String == "h264")
        #expect(planned["encoder"] as? String == "apple")
        #expect(planned["encoder_fallback"] as? Bool == false)
        let made = try CommandProcess.run(args)
        #expect(made.status == 0)
        let refused = try CommandProcess.run(args)
        #expect(refused.status == 4)
        for run in [plan, made, refused] {
            #expect(run.stderr.isEmpty)
            try verifyLegacyMakeLines(run.stdout)
        }
        let invalid = try CommandProcess.run(["make", song, picture, "-C", "av1", "-j"])
        #expect(invalid.status == 2)
        #expect(try JSONOutputLine(invalid.stdout).child("error")?["code"] as? String == "usage")
    }

    /// Read each 1.1 field even when the producer includes a field the 1.1 consumer has never seen.
    private func verifyLegacyMakeLines(_ output: String) throws {
        for raw in output.split(separator: "\n") {
            let line = try JSONOutputLine(String(raw) + "\n")
            #expect(line["api_version"] as? String == "1")
            switch line["type"] as? String {
            case "progress":
                let stage = try #require(line["stage"] as? String)
                #expect(["checking", "preparing", "encoding", "finishing"].contains(stage))
                #expect(line["elapsed_seconds"] is Double)
                for key in ["percent", "remaining_seconds"] { #expect(line[key] is NSNull || line[key] is Double) }
                if stage == "encoding" || stage == "finishing" {
                    #expect(line["encoder"] as? String == "apple")
                } else {
                    #expect(line["encoder"] == nil)
                }
            case "result":
                #expect(line["command"] as? String == "make")
                #expect(line["placement"] is String)
                #expect(line["enlarged"] is Bool)
                let dryRun = try #require(line["dry_run"] as? Bool)
                let file = try #require(line.child("output"))
                #expect(file["name"] as? String == "out.mp4")
                #expect(file["width"] is Int)
                #expect(file["height"] is Int)
                #expect(file["duration_seconds"] is Double)
                #expect(dryRun ? file["bytes"] is NSNull : file["bytes"] is Int)
            case "error":
                let error = try #require(line.child("error"))
                #expect(error["code"] is String)
                #expect(error["message"] is String)
            default:
                Issue.record("Unknown 1.1 line type")
            }
        }
        _ = try JSONOutputLine.final(output)
    }

    @Test("Preview scales and rotates JPEG and HEIC and overwrites only on request", arguments: [UTType.jpeg, .heic])
    func preview(type: UTType) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let input = workspace.url(type == .jpeg ? "photo.jpg" : "photo.heic")
        try TestMedia.writeImage(to: input, width: 3000, height: 1500, type: type, orientation: 6)
        let output = workspace.url("cover.png")
        let args = ["preview", input.path, "-o", output.path, "-j"]
        let result = try CommandProcess.run(args)
        try #require(result.status == 0, "\(result.stdout)\(result.stderr)")
        #expect(result.stderr.isEmpty)
        let line = try JSONOutputLine(result.stdout)
        #expect(line["command"] as? String == "preview")
        #expect(line.child("source") as? [String: Int] == ["width": 1500, "height": 3000])
        #expect(line.child("output")?["name"] as? String == "cover.png")
        #expect(line.child("output")?["width"] as? Int == 1024)
        #expect(line.child("output")?["height"] as? Int == 2048)
        let (image, pixels) = try readPNG(output)
        #expect(image.width == 1024 && image.height == 2048)
        let above = pixels.rgb(x: 512, y: 512)
        let below = pixels.rgb(x: 512, y: 1536)
        #expect(above.r > 180 && above.b < 70)
        #expect(below.r < 70 && below.b > 180)

        let marker = Data("existing output".utf8)
        try marker.write(to: output)
        let refused = try CommandProcess.run(args)
        #expect(refused.status == 4)
        #expect(try JSONOutputLine(refused.stdout).child("error")?["code"] as? String == "output_exists")
        #expect(try Data(contentsOf: output) == marker)
        let accepted = try CommandProcess.run(args + ["-w"])
        #expect(accepted.status == 0)
        _ = try readPNG(output)
        #expect(try workspace.listing() == ["cover.png", input.lastPathComponent].sorted())
    }

    @Test("Preview flattens transparent pixels against black, does not enlarge, and can cancel on closed stdin")
    func previewTransparencyAndCancellation() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let input = workspace.url("transparent.png")
        try TestMedia.writeImage(to: input, width: 60, height: 40, transparent: true)
        let output = workspace.url("out.png")
        let args = ["preview", input.path, "--out", output.path, "--json"]
        let cancelled = try CommandProcess.run(args + ["-E"])
        #expect(cancelled.status == 130)
        #expect(try JSONOutputLine(cancelled.stdout).child("error")?["code"] as? String == "cancelled")
        #expect(try workspace.listing() == ["transparent.png"])

        let result = try CommandProcess.run(args)
        #expect(result.status == 0)
        let (image, pixels) = try readPNG(output)
        #expect(image.width == 60 && image.height == 40)
        #expect(image.alphaInfo == .none || image.alphaInfo == .noneSkipLast || image.alphaInfo == .noneSkipFirst)
        #expect(pixels.rgb(x: 30, y: 20) == (0, 0, 0))
    }

    @Test("Preview uses the shared image and output error codes")
    func previewErrors() throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let invalidImage = try workspace.notMedia("invalid.jpg")
        let picture = try workspace.picture(width: 640, height: 480)
        let before = try workspace.listing()
        for (image, output, status, code) in [
            (workspace.path("missing.jpg"), workspace.path("out.png"), 1, "image_not_found"),
            (invalidImage, workspace.path("out.png"), 3, "image_unreadable"),
            (picture, workspace.path("out.jpg"), 2, "usage"),
            (picture, workspace.path("missing/out.png"), 4, "output_not_writable"),
            (picture, picture, 4, "output_not_writable"),
        ] {
            let result = try CommandProcess.run(["preview", image, "-o", output, "-j", "-w"])
            #expect(result.status == Int32(status))
            #expect(result.stderr.isEmpty)
            #expect(try JSONOutputLine(result.stdout).child("error")?["code"] as? String == code)
            #expect(!result.stdout.contains(CommandWorkspace.folderMarker))
            #expect(try workspace.listing() == before)
        }
    }

    private func readPNG(_ url: URL) throws -> (CGImage, FramePixels) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image, try FramePixels(image))
    }

    @Test("Make cancels within two seconds of stdin EOF or a cancel line", arguments: [true, false])
    func cancelMake(eof: Bool) throws {
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let song = try workspace.longSong()
        let image = try workspace.picture(width: 600, height: 600)
        let before = try workspace.listing()
        let running = try CommandProcess.Running(
            ["make", song, image, "-o", workspace.path("out.mp4"), "-r", "480p", "-j", eof ? "--cancel-on-eof" : "-E"],
            keepStdinOpen: true
        )
        Thread.sleep(forTimeInterval: 1)
        try #require(running.isRunning)
        let clock = ContinuousClock()
        let requested = clock.now
        if eof {
            try running.closeStdin()
        } else {
            try running.writeStdin(Data("ignore cancel\ncan".utf8))
            try running.writeStdin(Data("cel\r\n".utf8))
        }
        let deadline = requested.advanced(by: .seconds(2))
        while running.isRunning, clock.now < deadline { Thread.sleep(forTimeInterval: 0.01) }
        let timely = !running.isRunning && clock.now <= deadline
        if !timely { running.send(SIGTERM) }
        let result = running.finish()
        #expect(timely)
        #expect(result.status == 130)
        #expect(result.stderr.isEmpty)
        #expect(try JSONOutputLine.final(result.stdout).child("error")?["code"] as? String == "cancelled")
        #expect(try workspace.listing() == before)
    }

    @Test("New command help and invalid arguments", arguments: ["encoders", "preview"])
    func help(command: String) throws {
        for flag in ["--help", "-h"] {
            let result = try CommandProcess.run([command, flag])
            #expect(result.status == 0)
            for heading in ["Usage:", "Options:", "Examples:", "Exit statuses:"] { #expect(result.stdout.contains(heading)) }
        }
        let invalid = try CommandProcess.run(command == "preview" ? [command, "-j"] : [command, "unused", "-j"])
        #expect(invalid.status == 2)
        #expect(try JSONOutputLine(invalid.stdout).child("error")?["code"] as? String == "usage")
    }
}
