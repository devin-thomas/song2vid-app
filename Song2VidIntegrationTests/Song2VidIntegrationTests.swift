import AVFoundation
import Foundation
import Testing
import UniformTypeIdentifiers
import Song2VidCore

/// Seam 3 (SPEC section 11): files and placement in, an MP4 or an error out.
/// Expected sizes and messages come from SPEC sections 5, 6 and 7, not from the code under test.
@Suite("Video export", .serialized)
struct VideoExportTests {
    /// A temporary folder holding generated inputs, and a separate folder for the output.
    struct Workspace {
        let root: URL
        var inputs: URL { root.appendingPathComponent("inputs", isDirectory: true) }
        var outputs: URL { root.appendingPathComponent("outputs", isDirectory: true) }
        /// A folder to build the video in, as the sandboxed app does with the temporary folder.
        var scratch: URL { root.appendingPathComponent("scratch", isDirectory: true) }
        var destination: URL { outputs.appendingPathComponent("out.mp4") }

        init() throws {
            root = try TestMedia.makeFolder()
            try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        }

        func remove() {
            // A read-only folder from a test can't be deleted until it is made writable again.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outputs.path)
            try? FileManager.default.removeItem(at: root)
        }

        /// What is in the scratch folder, hidden files included.
        func scratchNames() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: scratch.path).sorted()
        }

        /// What is in the output folder, hidden files included.
        func outputNames() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: outputs.path).sorted()
        }
    }

    /// The image used when a test doesn't care about it: 600x400, so Original keeps it as it is.
    static let imageSize = PixelSize(width: 600, height: 400)

    private func request(
        _ workspace: Workspace,
        audio: URL? = nil,
        image: URL? = nil,
        shape: FrameShape = .sixteenByNine,
        resolution: Resolution = .p480,
        imageSize: PixelSize = VideoExportTests.imageSize,
        destination: URL? = nil,
        scratchFolder: URL? = nil
    ) throws -> ExportRequest {
        let audioURL = try audio ?? TestMedia.writeTone(to: workspace.inputs.appendingPathComponent("tone.wav"))
        let imageURL = try image ?? TestMedia.writeImage(
            to: workspace.inputs.appendingPathComponent("picture.png"), width: imageSize.width, height: imageSize.height
        )
        let frame = try OutputFrame(imageSize: imageSize, frameShape: shape, resolution: resolution)
        return ExportRequest(
            audioURL: audioURL, imageURL: imageURL, frame: frame, destinationURL: destination ?? workspace.destination,
            scratchFolder: scratchFolder
        )
    }

    // MARK: Size, length, tracks (SPEC section 11)

    struct SizeCase: Sendable, CustomTestStringConvertible {
        let shape: FrameShape
        let resolution: Resolution
        let width: Int
        let height: Int
        var testDescription: String { "\(shape) at \(resolution) is \(width)x\(height)" }
    }

    /// Each Frame Shape at 480p, and 2160p for two of them. The test image is 600x400, which Original keeps.
    static let sizeCases: [SizeCase] = [
        SizeCase(shape: .sixteenByNine, resolution: .p480, width: 854, height: 480),
        SizeCase(shape: .nineBySixteen, resolution: .p480, width: 480, height: 854),
        SizeCase(shape: .oneByOne, resolution: .p480, width: 480, height: 480),
        SizeCase(shape: .fourByThree, resolution: .p480, width: 640, height: 480),
        SizeCase(shape: .original, resolution: .p480, width: 600, height: 400),
        SizeCase(shape: .sixteenByNine, resolution: .p2160, width: 3840, height: 2160),
        SizeCase(shape: .fourByThree, resolution: .p2160, width: 2880, height: 2160),
    ]

    @Test(arguments: sizeCases)
    func writesAnMP4OfTheRightSizeAndLengthWithBothTracks(testCase: SizeCase) async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }

        let outcome = await VideoExporter.export(
            try request(workspace, shape: testCase.shape, resolution: testCase.resolution), progress: { _ in }
        )

        #expect(outcome == .completed(workspace.destination))
        let video = try await Inspection(workspace.destination)
        #expect(video.videoSize == CGSize(width: testCase.width, height: testCase.height))
        #expect(abs(video.videoDuration - 3) <= 0.1)
        #expect(abs(video.audioDuration - 3) <= 0.1)
        #expect(video.videoCodec == kCMVideoCodecType_H264)
        #expect(video.audioCodec == kAudioFormatMPEG4AAC)
        #expect(abs(video.frameRate - 30) < 0.5)
        // Nothing but the video is left in the folder.
        #expect(try workspace.outputNames() == ["out.mp4"])
    }

    @Test func keepsTheLengthAcrossSeveralGroupsOfFrames() async throws {
        // 25 seconds is two and a half groups of identical frames, so this covers the joins between them.
        let workspace = try Workspace()
        defer { workspace.remove() }
        let audio = try TestMedia.writeTone(to: workspace.inputs.appendingPathComponent("long.wav"), seconds: 25)

        let outcome = await VideoExporter.export(try request(workspace, audio: audio), progress: { _ in })

        #expect(outcome == .completed(workspace.destination))
        let video = try await Inspection(workspace.destination)
        #expect(abs(video.videoDuration - 25) <= 0.1)
        #expect(abs(video.audioDuration - 25) <= 0.1)
        #expect(try await video.decodesEveryFrame(count: 750))
    }

    // MARK: Audio (SPEC section 6.3 and 7)

    /// What goes in, and what SPEC section 6.3 says comes out: the source's sample rate up to 48 kHz and
    /// its channels up to two. Higher rates become 48 kHz, and more channels become stereo.
    struct AudioCase: Sendable, CustomTestStringConvertible {
        let kind: TestMedia.AudioKind
        let sampleRate: Double
        let channels: Int
        let expectedRate: Double
        let expectedChannels: Int

        init(_ kind: TestMedia.AudioKind, _ sampleRate: Double, _ channels: Int, expectedRate: Double? = nil, expectedChannels: Int? = nil) {
            self.kind = kind
            self.sampleRate = sampleRate
            self.channels = channels
            self.expectedRate = expectedRate ?? sampleRate
            self.expectedChannels = expectedChannels ?? min(channels, 2)
        }

        var testDescription: String {
            "\(kind.rawValue) \(Int(sampleRate)) Hz, \(channels) channel(s) becomes \(Int(expectedRate)) Hz, \(expectedChannels)"
        }
    }

    static let audioCases: [AudioCase] = [
        AudioCase(.wav, 44_100, 2),
        AudioCase(.wav, 48_000, 1),
        AudioCase(.wav, 8_000, 1),
        AudioCase(.wav, 22_050, 2),
        AudioCase(.aiff, 44_100, 2),
        AudioCase(.caf, 48_000, 2),
        AudioCase(.aac, 44_100, 2),
        AudioCase(.alac, 44_100, 2),
        // Above 48 kHz the AAC encoder can't take the rate (SPEC section 6.3).
        AudioCase(.wav, 96_000, 2, expectedRate: 48_000),
        AudioCase(.wav, 96_000, 1, expectedRate: 48_000),
        AudioCase(.aiff, 88_200, 2, expectedRate: 48_000),
        AudioCase(.caf, 64_000, 2, expectedRate: 48_000),
        // AAC has only a fixed list of rates, so an unusual one goes to the next rate up, or down to 48 kHz.
        AudioCase(.wav, 37_800, 2, expectedRate: 44_100),
        AudioCase(.wav, 10_000, 1, expectedRate: 11_025),
        AudioCase(.wav, 50_000, 2, expectedRate: 48_000),
        // More than two channels are mixed down to stereo.
        AudioCase(.caf, 48_000, 6),
        AudioCase(.caf, 44_100, 3),
        AudioCase(.caf, 96_000, 6, expectedRate: 48_000),
        AudioCase(.caf, 48_000, 8),
    ]

    @Test(arguments: audioCases)
    func readsTheSupportedAudioFormatsAndKeepsRateAndChannels(testCase: AudioCase) async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let audio = try TestMedia.writeTone(
            to: workspace.inputs.appendingPathComponent("tone.\(testCase.kind.fileExtension)"),
            sampleRate: testCase.sampleRate, channels: testCase.channels, kind: testCase.kind
        )

        let outcome = await VideoExporter.export(try request(workspace, audio: audio), progress: { _ in })

        #expect(outcome == .completed(workspace.destination))
        let video = try await Inspection(workspace.destination)
        #expect(video.sampleRate == testCase.expectedRate)
        #expect(video.channels == testCase.expectedChannels)
        #expect(video.audioCodec == kAudioFormatMPEG4AAC)
        #expect(abs(video.audioDuration - 3) <= 0.1)
        #expect(abs(video.videoDuration - 3) <= 0.1)
        #expect(try workspace.outputNames() == ["out.mp4"])
    }

    @Test func aHighSampleRateSourceStillGetsAudioAt256KilobitsPerSecond() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let audio = try TestMedia.writeTone(
            to: workspace.inputs.appendingPathComponent("hires.wav"), sampleRate: 96_000, channels: 2
        )

        let outcome = await VideoExporter.export(try request(workspace, audio: audio), progress: { _ in })

        #expect(outcome == .completed(workspace.destination))
        let video = try await Inspection(workspace.destination)
        #expect(abs(Double(video.audioBitRate) - 256_000) < 256_000 * 0.05)
    }

    @Test func writesStereoAudioAt256KilobitsPerSecond() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }

        let outcome = await VideoExporter.export(try request(workspace), progress: { _ in })

        #expect(outcome == .completed(workspace.destination))
        let video = try await Inspection(workspace.destination)
        #expect(abs(Double(video.audioBitRate) - 256_000) < 256_000 * 0.05)
    }

    @Test func reportsTheAudioLengthAndFormatForTheWindow() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let audio = try TestMedia.writeTone(
            to: workspace.inputs.appendingPathComponent("tone.wav"), seconds: 2.5, sampleRate: 48_000, channels: 1
        )

        let info = try AudioInfo.read(from: audio)

        #expect(abs(info.duration - 2.5) <= 0.01)
        #expect(info.sampleRate == 48_000)
        #expect(info.channelCount == 1)
    }

    // MARK: Image (SPEC section 7)

    @Test(arguments: [UTType.png, .jpeg, .tiff, .gif, .bmp, .heic])
    func readsTheSupportedImageFormats(type: UTType) async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let image = try TestMedia.writeImage(
            to: workspace.inputs.appendingPathComponent("picture"), width: 600, height: 400, type: type
        )

        let outcome = await VideoExporter.export(try request(workspace, image: image, shape: .original), progress: { _ in })

        #expect(outcome == .completed(workspace.destination))
        #expect(try ImageInfo.read(from: image).size == PixelSize(width: 600, height: 400))
        #expect(try await Inspection(workspace.destination).videoSize == CGSize(width: 600, height: 400))
    }

    @Test func appliesTheOrientationTag() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        // Tag 6: the stored 600x400 picture is shown turned a quarter turn clockwise, so it is 400x600 and
        // its red left half is on top.
        let image = try TestMedia.writeImage(
            to: workspace.inputs.appendingPathComponent("turned.jpg"), width: 600, height: 400, type: .jpeg, orientation: 6
        )
        #expect(try ImageInfo.read(from: image).size == PixelSize(width: 400, height: 600))

        let outcome = await VideoExporter.export(
            try request(workspace, image: image, shape: .original, imageSize: PixelSize(width: 400, height: 600)),
            progress: { _ in }
        )

        #expect(outcome == .completed(workspace.destination))
        let frame = try await TestMedia.firstFrame(of: workspace.destination)
        #expect(frame.width == 400 && frame.height == 600)
        #expect(frame.isRed(x: 200, y: 100))
        #expect(frame.isBlue(x: 200, y: 500))
    }

    // MARK: Placement (what is drawn)

    @Test func fitWithBarsCentresTheWholeImageBetweenBlackBars() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }

        // 600x400 fitted into 854x480 is 720x480, from x = 67 to x = 787.
        let outcome = await VideoExporter.export(try request(workspace, shape: .sixteenByNine), progress: { _ in })

        #expect(outcome == .completed(workspace.destination))
        let frame = try await TestMedia.firstFrame(of: workspace.destination)
        #expect(frame.isBlack(x: 20, y: 240))
        #expect(frame.isBlack(x: 840, y: 240))
        #expect(frame.isRed(x: 150, y: 240))
        #expect(frame.isBlue(x: 700, y: 240))
    }

    @Test func cropKeepsTheChosenPartOfTheImage() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        // 600x400 filling 480x480 is 720x480 and 240 pixels of the width are discarded. Kept at the far left
        // (position 0), the image's left 480 of 720 shows: red to x = 360, then blue.
        let frame = try OutputFrame(
            imageSize: Self.imageSize, frameShape: .oneByOne, resolution: .p480,
            cropPosition: CropPosition(horizontal: 0, vertical: 0.5)
        )
        let image = try TestMedia.writeImage(to: workspace.inputs.appendingPathComponent("p.png"), width: 600, height: 400)
        let audio = try TestMedia.writeTone(to: workspace.inputs.appendingPathComponent("t.wav"))

        let outcome = await VideoExporter.export(
            ExportRequest(audioURL: audio, imageURL: image, frame: frame, destinationURL: workspace.destination),
            progress: { _ in }
        )

        #expect(outcome == .completed(workspace.destination))
        let pixels = try await TestMedia.firstFrame(of: workspace.destination)
        #expect(pixels.isRed(x: 300, y: 240))
        #expect(pixels.isBlue(x: 420, y: 240))
    }

    @Test func transparentAreasBecomeBlack() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let image = try TestMedia.writeImage(
            to: workspace.inputs.appendingPathComponent("clear.png"), width: 600, height: 400, transparent: true
        )

        let outcome = await VideoExporter.export(try request(workspace, image: image), progress: { _ in })

        #expect(outcome == .completed(workspace.destination))
        let frame = try await TestMedia.firstFrame(of: workspace.destination)
        #expect(frame.isBlack(x: 427, y: 240))
    }

    // MARK: Progress and cancel (SPEC section 6.2 and 6.5)

    @Test func reportsProgressThatNeverGoesBackAndEndsAtOne() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let log = ProgressLog()

        let outcome = await VideoExporter.export(try request(workspace), progress: { log.add($0) })

        #expect(outcome == .completed(workspace.destination))
        let values = log.values
        #expect(values.count >= 2)
        #expect(values == values.sorted())
        #expect(values.allSatisfy { (0...1).contains($0) })
        #expect(values.last == 1)
        // The file is in place before 100% is reported.
        #expect(values.dropLast().allSatisfy { $0 < 1 })
    }

    @Test func cancelRemovesTheFile() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let job = try request(workspace, shape: .sixteenByNine, resolution: .p2160)
        let box = TaskBox()

        let task = Task {
            await VideoExporter.export(job, progress: { _ in box.cancel() })
        }
        box.set(task)
        let outcome = await task.value

        #expect(outcome == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: workspace.destination.path))
        #expect(try workspace.outputNames() == [])
    }

    @Test func cancellingBeforeTheStartLeavesNothing() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let job = try request(workspace)

        let task = Task { await VideoExporter.export(job, progress: { _ in }) }
        task.cancel()
        let outcome = await task.value

        #expect(outcome == .cancelled)
        #expect(try workspace.outputNames() == [])
    }

    @Test func cancelLeavesAnExistingFileAtTheDestinationUntouched() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let existing = Data("the person's earlier video".utf8)
        try existing.write(to: workspace.destination)
        let job = try request(workspace)
        let box = TaskBox()

        let task = Task { await VideoExporter.export(job, progress: { _ in box.cancel() }) }
        box.set(task)
        let outcome = await task.value

        #expect(outcome == .cancelled)
        #expect(try Data(contentsOf: workspace.destination) == existing)
        #expect(try workspace.outputNames() == ["out.mp4"])
    }

    @Test func replacesAnExistingFileOnceTheNewVideoIsComplete() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        try Data("old".utf8).write(to: workspace.destination)

        let outcome = await VideoExporter.export(try request(workspace), progress: { _ in })

        #expect(outcome == .completed(workspace.destination))
        #expect(try await Inspection(workspace.destination).videoSize == CGSize(width: 854, height: 480))
        #expect(try workspace.outputNames() == ["out.mp4"])
    }

    // MARK: Building in another folder (the sandboxed app's path, SPEC section 6.1 and 6.5)

    // A sandboxed app may write only the file the person chose, not its folder, so the video is built in the
    // temporary folder and moved into place. The tests ask for that path by naming a scratch folder. What only
    // the real sandboxed app can show (that the move is allowed) is checked by hand.

    @Test func aVideoBuiltInAnotherFolderEndsUpAtTheDestinationAndLeavesNothingBehind() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }

        let outcome = await VideoExporter.export(
            try request(workspace, scratchFolder: workspace.scratch), progress: { _ in }
        )

        #expect(outcome == .completed(workspace.destination))
        #expect(try await Inspection(workspace.destination).videoSize == CGSize(width: 854, height: 480))
        #expect(try workspace.outputNames() == ["out.mp4"])
        #expect(try workspace.scratchNames() == [])
    }

    @Test func aVideoBuiltInAnotherFolderReplacesAnExistingFile() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        try Data("old".utf8).write(to: workspace.destination)

        let outcome = await VideoExporter.export(
            try request(workspace, scratchFolder: workspace.scratch), progress: { _ in }
        )

        #expect(outcome == .completed(workspace.destination))
        #expect(try await Inspection(workspace.destination).videoSize == CGSize(width: 854, height: 480))
        #expect(try workspace.outputNames() == ["out.mp4"])
        #expect(try workspace.scratchNames() == [])
    }

    @Test func cancellingAVideoBuiltInAnotherFolderLeavesNothingAnywhere() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let existing = Data("the person's earlier video".utf8)
        try existing.write(to: workspace.destination)
        let job = try request(workspace, resolution: .p2160, scratchFolder: workspace.scratch)
        let box = TaskBox()

        let task = Task { await VideoExporter.export(job, progress: { _ in box.cancel() }) }
        box.set(task)
        let outcome = await task.value

        #expect(outcome == .cancelled)
        #expect(try Data(contentsOf: workspace.destination) == existing)
        #expect(try workspace.outputNames() == ["out.mp4"])
        #expect(try workspace.scratchNames() == [])
    }

    @Test func aFailureWhileBuildingInAnotherFolderLeavesNothingAnywhere() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        // The scratch disk is the full one, so the video can't even be built.
        let disk = try TinyDisk()
        defer { disk.detach() }
        let audio = try TestMedia.writeTone(to: workspace.inputs.appendingPathComponent("long.wav"), seconds: 150)

        let outcome = await VideoExporter.export(
            try request(workspace, audio: audio, scratchFolder: disk.mountPoint), progress: { _ in }
        )

        #expect(outcome == .failed(.diskFull))
        #expect(try workspace.outputNames() == [])
        #expect(try disk.visibleNames() == [])
    }

    @Test func aVideoBuiltOnOneVolumeReplacesAFileOnAnotherVolume() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        // The system's swap-in-place can't cross volumes, so the file is written over instead.
        let disk = try TinyDisk()
        defer { disk.detach() }
        let destination = disk.mountPoint.appendingPathComponent("out.mp4")
        try Data("old".utf8).write(to: destination)

        let outcome = await VideoExporter.export(
            try request(workspace, destination: destination, scratchFolder: workspace.scratch), progress: { _ in }
        )

        #expect(outcome == .completed(destination))
        #expect(try await Inspection(destination).videoSize == CGSize(width: 854, height: 480))
        #expect(try disk.visibleNames() == ["out.mp4"])
        #expect(try workspace.scratchNames() == [])
    }

    @Test func aMoveThatRunsOutOfSpaceDoesNotLeaveAHalfWrittenVideo() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        // The video is built on the Mac's disk and then moved to a disk that is too small for it, so the
        // move fails partway through (SPEC section 6.5: the half-written file is deleted).
        let disk = try TinyDisk()
        defer { disk.detach() }
        let audio = try TestMedia.writeTone(to: workspace.inputs.appendingPathComponent("long.wav"), seconds: 150)
        let destination = disk.mountPoint.appendingPathComponent("out.mp4")

        let outcome = await VideoExporter.export(
            try request(workspace, audio: audio, destination: destination, scratchFolder: workspace.scratch),
            progress: { _ in }
        )

        #expect(outcome == .failed(.diskFull))
        #expect(try disk.visibleNames() == [])
        #expect(try workspace.scratchNames() == [])
    }

    @Test func aMoveThatRunsOutOfSpaceKeepsTheFileItWasToReplace() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let disk = try TinyDisk()
        defer { disk.detach() }
        let audio = try TestMedia.writeTone(to: workspace.inputs.appendingPathComponent("long.wav"), seconds: 150)
        let destination = disk.mountPoint.appendingPathComponent("out.mp4")
        let existing = Data("the person's earlier video".utf8)
        try existing.write(to: destination)

        let outcome = await VideoExporter.export(
            try request(workspace, audio: audio, destination: destination, scratchFolder: workspace.scratch),
            progress: { _ in }
        )

        #expect(outcome == .failed(.diskFull))
        #expect(try Data(contentsOf: destination) == existing)
        #expect(try disk.visibleNames() == ["out.mp4"])
        #expect(try workspace.scratchNames() == [])
    }

    // MARK: Errors (SPEC section 6.5 and 7)

    @Test func unreadableAudioGivesTheSection7Message() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let notAudio = workspace.inputs.appendingPathComponent("notes.mp3")
        try Data("this is not audio".utf8).write(to: notAudio)

        let outcome = await VideoExporter.export(try request(workspace, audio: notAudio), progress: { _ in })

        #expect(outcome == .failed(.unreadableAudio))
        #expect(ExportError.unreadableAudio.message == "Song2Vid can't read this audio file.")
        #expect(throws: ExportError.unreadableAudio) { try AudioInfo.read(from: notAudio) }
        #expect(try workspace.outputNames() == [])
    }

    @Test func aFileWithNoAudioTrackGivesTheSection7Message() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        // A picture is a file macOS can open, but it has no audio in it.
        let picture = try TestMedia.writeImage(
            to: workspace.inputs.appendingPathComponent("not-a-song.png"), width: 100, height: 100
        )

        let outcome = await VideoExporter.export(try request(workspace, audio: picture), progress: { _ in })

        #expect(outcome == .failed(.unreadableAudio))
        #expect(try workspace.outputNames() == [])
    }

    @Test func unreadableImageGivesTheSection7Message() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let notImage = workspace.inputs.appendingPathComponent("notes.png")
        try Data("this is not an image".utf8).write(to: notImage)

        let outcome = await VideoExporter.export(try request(workspace, image: notImage), progress: { _ in })

        #expect(outcome == .failed(.unreadableImage))
        #expect(ExportError.unreadableImage.message == "Song2Vid can't read this image file.")
        #expect(throws: ExportError.unreadableImage) { try ImageInfo.read(from: notImage) }
        #expect(try workspace.outputNames() == [])
    }

    @Test func aFailureLeavesAnExistingFileAtTheDestinationUntouched() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let existing = Data("the person's earlier video".utf8)
        try existing.write(to: workspace.destination)
        let notImage = workspace.inputs.appendingPathComponent("notes.png")
        try Data("this is not an image".utf8).write(to: notImage)

        let outcome = await VideoExporter.export(try request(workspace, image: notImage), progress: { _ in })

        #expect(outcome == .failed(.unreadableImage))
        #expect(try Data(contentsOf: workspace.destination) == existing)
    }

    @Test func aFolderThatDoesNotExistGivesTheCouldntSaveMessage() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let missing = workspace.root.appendingPathComponent("gone", isDirectory: true).appendingPathComponent("out.mp4")

        let outcome = await VideoExporter.export(try request(workspace, destination: missing), progress: { _ in })

        #expect(outcome == .failed(.cannotSaveToFolder))
        #expect(ExportError.cannotSaveToFolder.message == "Couldn't save to that folder")
    }

    @Test func aFolderThatCantBeWrittenToGivesTheCouldntSaveMessage() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let job = try request(workspace)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: workspace.outputs.path)

        let outcome = await VideoExporter.export(job, progress: { _ in })

        #expect(outcome == .failed(.cannotSaveToFolder))
        #expect(try workspace.outputNames() == [])
    }

    @Test func aFullDiskGivesTheDiskSpaceMessageAndLeavesNothingBehind() async throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        // A 2 MB disk image is mounted for the test. A few minutes of audio is more than it can hold.
        let disk = try TinyDisk()
        defer { disk.detach() }
        let audio = try TestMedia.writeTone(to: workspace.inputs.appendingPathComponent("long.wav"), seconds: 150)
        let destination = disk.mountPoint.appendingPathComponent("out.mp4")

        let outcome = await VideoExporter.export(
            try request(workspace, audio: audio, destination: destination), progress: { _ in }
        )

        #expect(outcome == .failed(.diskFull))
        #expect(ExportError.diskFull.message == "Not enough disk space")
        #expect(try disk.visibleNames() == [])
    }
}

// MARK: - Helpers

/// What is in a finished MP4, read back with AVFoundation, independently of the exporter.
struct Inspection {
    let videoSize: CGSize
    let videoDuration: Double
    let audioDuration: Double
    let videoCodec: FourCharCode?
    let audioCodec: FourCharCode?
    let frameRate: Float
    let sampleRate: Double
    let channels: Int
    let audioBitRate: Float
    private let asset: AVURLAsset

    init(_ url: URL) async throws {
        asset = AVURLAsset(url: url)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let audio = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        videoSize = try await video.load(.naturalSize)
        videoDuration = try await video.load(.timeRange).duration.seconds
        audioDuration = try await audio.load(.timeRange).duration.seconds
        frameRate = try await video.load(.nominalFrameRate)
        audioBitRate = try await audio.load(.estimatedDataRate)
        let videoFormat = try await video.load(.formatDescriptions).first
        let audioFormat = try await audio.load(.formatDescriptions).first
        videoCodec = videoFormat.map { CMFormatDescriptionGetMediaSubType($0) }
        audioCodec = audioFormat.map { CMFormatDescriptionGetMediaSubType($0) }
        let basic = audioFormat.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        sampleRate = basic?.mSampleRate ?? 0
        channels = Int(basic?.mChannelsPerFrame ?? 0)
    }

    /// Reads and decodes every video frame, which fails if a join between groups of frames is broken.
    func decodesEveryFrame(count: Int) async throws -> Bool {
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        guard reader.startReading() else { return false }
        var frames = 0
        while output.copyNextSampleBuffer() != nil { frames += 1 }
        return reader.status == .completed && frames == count
    }
}

extension FramePixels {
    func isRed(x: Int, y: Int) -> Bool { let c = rgb(x: x, y: y); return c.r > 200 && c.g < 60 && c.b < 60 }
    func isBlue(x: Int, y: Int) -> Bool { let c = rgb(x: x, y: y); return c.b > 200 && c.r < 60 && c.g < 60 }
    func isBlack(x: Int, y: Int) -> Bool { let c = rgb(x: x, y: y); return c.r < 20 && c.g < 20 && c.b < 20 }
}

/// Progress values as the exporter reports them, from its own queue.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Double] = []

    func add(_ value: Double) {
        lock.lock()
        recorded.append(value)
        lock.unlock()
    }

    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

/// Lets a progress callback cancel the task that is running the export, however the two are ordered.
final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<ExportOutcome, Never>?
    private var cancelRequested = false

    func set(_ task: Task<ExportOutcome, Never>) {
        lock.lock()
        self.task = task
        let pending = cancelRequested
        lock.unlock()
        if pending { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelRequested = true
        let current = task
        lock.unlock()
        current?.cancel()
    }
}

/// A small disk image mounted for one test, to run the disk out of space.
struct TinyDisk {
    let mountPoint: URL
    private let image: URL

    init() throws {
        let name = "S2VTEST\(UInt32.random(in: 0..<1_000_000))"
        image = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).dmg")
        let output = try Self.hdiutil(["create", "-size", "2m", "-fs", "MS-DOS", "-volname", name, "-attach", image.path])
        let line = try #require(output.split(separator: "\n").first { $0.contains("/Volumes/") })
        let path = try #require(line.range(of: "/Volumes/").map { String(line[$0.lowerBound...]) })
        mountPoint = URL(fileURLWithPath: path.trimmingCharacters(in: .whitespaces), isDirectory: true)
    }

    /// What is on the disk, apart from the folder macOS adds by itself.
    func visibleNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: mountPoint.path).filter { $0 != ".fseventsd" }.sorted()
    }

    func detach() {
        _ = try? Self.hdiutil(["detach", "-force", mountPoint.path])
        try? FileManager.default.removeItem(at: image)
    }

    @discardableResult
    private static func hdiutil(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return String(decoding: data, as: UTF8.self)
    }
}
