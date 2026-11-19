import Foundation
import Testing
@testable import Song2VidCore

/// A stand-in for reading real files: it answers from a table, or fails for anything not in it.
struct StubInspector: MediaInspecting {
    var audio: [String: LoadedAudio] = [:]
    var images: [String: LoadedImage] = [:]

    func inspectAudio(at url: URL) async throws -> LoadedAudio {
        guard let found = audio[url.lastPathComponent] else { throw MediaError.unreadableAudio }
        return found
    }

    func inspectImage(at url: URL) async throws -> LoadedImage {
        guard let found = images[url.lastPathComponent] else { throw MediaError.unreadableImage }
        return found
    }
}

func song(_ name: String = "song.mp3", seconds: Double = 185) -> LoadedAudio {
    LoadedAudio(url: URL(fileURLWithPath: "/media/\(name)"), duration: seconds)
}

func picture(_ name: String = "cover.jpg", _ width: Int = 3000, _ height: Int = 1000) -> LoadedImage {
    LoadedImage(url: URL(fileURLWithPath: "/media/\(name)"), size: PixelSize(width: width, height: height))
}

@MainActor
func model(audio: [LoadedAudio] = [], images: [LoadedImage] = []) -> MainWindowModel {
    var stub = StubInspector()
    for a in audio { stub.audio[a.url.lastPathComponent] = a }
    for i in images { stub.images[i.url.lastPathComponent] = i }
    return MainWindowModel(inspector: stub)
}

@MainActor
@Suite("Main window: choices and labels")
struct MainWindowChoiceTests {
    @Test func startsWith16By9At1080pAndNothingLoaded() {
        let m = model()
        #expect(m.frameShape == .sixteenByNine)
        #expect(m.resolution == .p1080)
        #expect(m.audio == nil)
        #expect(m.image == nil)
        #expect(m.cropPosition == .center)
    }

    @Test func emptyPreviewAsksForAnImageAndHasNoCropOrNote() {
        let m = model()
        #expect(m.previewPrompt == "Choose an image")
        #expect(m.frame == nil)
        #expect(m.enlargeNote == nil)
        #expect(m.canAdjustCrop == false)
    }

    @Test func emptyPreviewStillShowsTheChosenFrameShape() {
        let m = model()
        m.frameShape = .nineBySixteen
        m.resolution = .p480
        #expect(m.previewFrameSize == PixelSize(width: 480, height: 854))
        m.frameShape = .fourByThree
        #expect(m.previewFrameSize == PixelSize(width: 640, height: 480))
    }

    @Test func chosenAudioShowsNameAndLengthAsMinutesAndSeconds() async {
        let m = model(audio: [song("night.mp3", seconds: 185)])
        await m.chooseAudio(at: URL(fileURLWithPath: "/media/night.mp3"))
        #expect(m.audioSummary == "night.mp3, 3:05")
    }

    @Test func lengthRoundsToTheNearestSecondAndPadsSeconds() async {
        let m = model(audio: [song("a.mp3", seconds: 59.6), song("b.mp3", seconds: 62.2)])
        await m.chooseAudio(at: URL(fileURLWithPath: "/media/a.mp3"))
        #expect(m.audioSummary == "a.mp3, 1:00")
        await m.chooseAudio(at: URL(fileURLWithPath: "/media/b.mp3"))
        #expect(m.audioSummary == "b.mp3, 1:02")
    }

    @Test func chosenImageShowsNameAndPixelSize() async {
        let m = model(images: [picture("cover.jpg", 3000, 1000)])
        await m.chooseImage(at: URL(fileURLWithPath: "/media/cover.jpg"))
        #expect(m.imageSummary == "cover.jpg, 3000×1000 pixels")
        #expect(m.previewPrompt == nil)
    }

    @Test func makeVideoNeedsBothFiles() async {
        let m = model(audio: [song()], images: [picture()])
        #expect(m.canMakeVideo == false)
        await m.chooseAudio(at: URL(fileURLWithPath: "/media/song.mp3"))
        #expect(m.canMakeVideo == false)
        await m.chooseImage(at: URL(fileURLWithPath: "/media/cover.jpg"))
        #expect(m.canMakeVideo == true)
    }

    @Test func makeVideoStaysOffWhenOriginalCantBeMadeFromATinyImage() async {
        let m = model(audio: [song()], images: [picture("tiny.png", 10, 40)])
        await m.chooseAudio(at: URL(fileURLWithPath: "/media/song.mp3"))
        await m.chooseImage(at: URL(fileURLWithPath: "/media/tiny.png"))
        #expect(m.canMakeVideo == true)
        m.frameShape = .original
        #expect(m.canMakeVideo == false)
        #expect(m.frameProblem == FrameError.imageTooSmall.message)
        m.frameShape = .oneByOne
        #expect(m.frameProblem == nil)
        #expect(m.canMakeVideo == true)
    }

    @Test func unreadableFilesGiveAMessageAndKeepWhatWasThere() async {
        let m = model(audio: [song()], images: [picture()])
        await m.chooseAudio(at: URL(fileURLWithPath: "/media/song.mp3"))
        await m.chooseImage(at: URL(fileURLWithPath: "/media/cover.jpg"))

        await m.chooseAudio(at: URL(fileURLWithPath: "/media/notes.txt"))
        #expect(m.notice == "Song2Vid can't read this audio file.")
        #expect(m.audio == song())

        await m.chooseImage(at: URL(fileURLWithPath: "/media/notes.txt"))
        #expect(m.notice == "Song2Vid can't read this image file.")
        #expect(m.image == picture())
    }

    @Test func aSuccessfulChoiceClearsTheMessage() async {
        let m = model(audio: [song()])
        await m.chooseAudio(at: URL(fileURLWithPath: "/media/notes.txt"))
        #expect(m.notice != nil)
        await m.chooseAudio(at: URL(fileURLWithPath: "/media/song.mp3"))
        #expect(m.notice == nil)
    }

    @Test func resolutionPickerIsHiddenForOriginalWhichShowsItsOutputSize() async {
        let m = model(images: [picture("cover.jpg", 1600, 900)])
        await m.chooseImage(at: URL(fileURLWithPath: "/media/cover.jpg"))
        #expect(m.showsResolutionPicker == true)
        #expect(m.outputSizeLabel == nil)
        m.frameShape = .original
        #expect(m.showsResolutionPicker == false)
        #expect(m.outputSizeLabel == "Output: 1600×900")
    }

    @Test func originalOutputSizeFollowsTheSpecRules() async {
        // 4000x3000 is over the limit: scaled by 0.72 to 2880x2160.
        let m = model(images: [picture("big.jpg", 4000, 3000)])
        await m.chooseImage(at: URL(fileURLWithPath: "/media/big.jpg"))
        m.frameShape = .original
        #expect(m.outputSizeLabel == "Output: 2880×2160")
    }

    @Test func enlargeNoteNamesTheOutputSizeWhenTheImageIsScaledUp() async {
        let m = model(images: [picture("small.jpg", 640, 360)])
        await m.chooseImage(at: URL(fileURLWithPath: "/media/small.jpg"))
        #expect(m.enlargeNote == "This image is smaller than 1920×1080 and will be enlarged, so it may look soft.")
        m.resolution = .p480
        #expect(m.enlargeNote == "This image is smaller than 854×480 and will be enlarged, so it may look soft.")
        m.resolution = .p2160
        #expect(m.enlargeNote == "This image is smaller than 3840×2160 and will be enlarged, so it may look soft.")
        m.frameShape = .original
        #expect(m.enlargeNote == nil)
    }

    @Test func noEnlargeNoteForALargeImage() async {
        let m = model(images: [picture("big.jpg", 4000, 3000)])
        await m.chooseImage(at: URL(fileURLWithPath: "/media/big.jpg"))
        #expect(m.enlargeNote == nil)
    }

    @Test func previewPlacementMatchesTheFrameRules() async throws {
        let m = model(images: [picture("wide.jpg", 3000, 1000)])
        await m.chooseImage(at: URL(fileURLWithPath: "/media/wide.jpg"))
        m.frameShape = .nineBySixteen
        // The whole image fits across the 1080 width, centred: 1080x360 in a 1080x1920 frame.
        #expect(m.frame?.size == PixelSize(width: 1080, height: 1920))
        #expect(m.frame?.imagePlacement == ImagePlacement(x: 0, y: 780, width: 1080, height: 360))
    }
}
