import Foundation
import Testing
@testable import Song2VidCore

/// A stand-in for the video exporter. It records the request it was given, reports the progress it is told to, and
/// either ends with a chosen outcome or waits until the task running it is cancelled.
final class FakeExporter: VideoExporting, @unchecked Sendable {
    enum Behavior {
        case finish(ExportOutcome)
        /// Reports these fractions, then waits for a cancel.
        case waitForCancel(progress: [Double])
    }

    private let lock = NSLock()
    private var _requests: [ExportRequest] = []
    private var _started = 0
    var behavior: Behavior

    init(_ behavior: Behavior = .finish(.completed(URL(fileURLWithPath: "/out/My Song.mp4")))) {
        self.behavior = behavior
    }

    var requests: [ExportRequest] { lock.withLock { _requests } }
    var startedCount: Int { lock.withLock { _started } }

    func export(_ request: ExportRequest, progress: @escaping @Sendable (Double) -> Void) async -> ExportOutcome {
        lock.withLock {
            _requests.append(request)
            _started += 1
        }
        switch behavior {
        case .finish(let outcome):
            progress(0.5)
            return outcome
        case .waitForCancel(let fractions):
            for fraction in fractions { progress(fraction) }
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
            return .cancelled
        }
    }
}

@MainActor
func readyModel(
    exporter: FakeExporter, audio: LoadedAudio = song("My Song.mp3"), image: LoadedImage = picture("cover.jpg", 4000, 3000),
    defaults: UserDefaults = .standard, hevc: Bool = true
) async -> MainWindowModel {
    var stub = StubInspector()
    stub.audio[audio.url.lastPathComponent] = audio
    stub.images[image.url.lastPathComponent] = image
    let m = MainWindowModel(inspector: stub, exporter: exporter, codecDefaults: defaults, isCodecAvailable: { $0 == .h264 || hevc })
    await m.chooseAudio(at: audio.url)
    await m.chooseImage(at: image.url)
    return m
}

/// Waits (briefly) until `condition` holds, since progress reaches the model from a background queue.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<400 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

private let destination = URL(fileURLWithPath: "/out/My Song.mp4")

/// Seam 3 from the window's side: what Make Video does to the window (SPEC section 6).
@MainActor
@Suite("Main window: making a video")
struct MainWindowMakeVideoTests {
    @Test func theSaveDialogStartsWithTheSongsNameAndAnMp4Extension() async {
        let m = await readyModel(exporter: FakeExporter())
        #expect(m.defaultSaveName == "My Song.mp4")
    }

    @Test func thereIsNoDefaultNameWithoutASong() {
        #expect(model().defaultSaveName == nil)
    }

    @Test func theSaveDialogStartsInTheFolderOfTheLastSaveOtherwiseNowhereInParticular() async {
        let exporter = FakeExporter(.finish(.completed(URL(fileURLWithPath: "/Volumes/Music/out/My Song.mp4"))))
        let m = await readyModel(exporter: exporter)
        #expect(m.lastSaveFolder == nil)
        await m.makeVideo(to: URL(fileURLWithPath: "/Volumes/Music/out/My Song.mp4"))
        #expect(m.lastSaveFolder?.path == "/Volumes/Music/out")
    }

    @Test func makingAVideoHandsTheExporterTheChosenFilesFrameAndDestination() async throws {
        let exporter = FakeExporter()
        let m = await readyModel(exporter: exporter)
        m.frameShape = .fourByThree
        m.resolution = .p2160
        m.dragCrop(from: .center, byFramePixels: -100, 0)
        let expectedFrame = try #require(m.frame)

        await m.makeVideo(to: destination)

        let request = try #require(exporter.requests.first)
        #expect(request.audioURL == m.audio?.url)
        #expect(request.imageURL == m.image?.url)
        #expect(request.frame == expectedFrame)
        #expect(request.destinationURL == destination)
    }

    @Test func nothingIsMadeWhileASongOrImageIsMissing() async {
        let exporter = FakeExporter()
        let m = MainWindowModel(inspector: StubInspector(), exporter: exporter)
        await m.makeVideo(to: destination)
        #expect(exporter.startedCount == 0)
        #expect(m.exportState == .idle)
    }

    @Test func aFinishedVideoSaysSavedAndKeepsItsLocationForShowInFinder() async {
        let saved = URL(fileURLWithPath: "/out/My Song.mp4")
        let m = await readyModel(exporter: FakeExporter(.finish(.completed(saved))))
        await m.makeVideo(to: saved)
        #expect(m.exportState == .saved(saved))
        #expect(m.savedVideoMessage == "Video saved.")
        #expect(m.savedVideoURL == saved)
        #expect(!m.isExporting)
        #expect(m.notice == nil)
    }

    @Test func theControlsUnlockAndAnotherVideoCanStartStraightAfterTheFirst() async {
        let exporter = FakeExporter()
        let m = await readyModel(exporter: exporter)
        await m.makeVideo(to: destination)
        #expect(m.canMakeVideo)
        #expect(!m.controlsLocked)
        await m.makeVideo(to: URL(fileURLWithPath: "/out/Second.mp4"))
        #expect(exporter.startedCount == 2)
        #expect(exporter.requests.last?.destinationURL == URL(fileURLWithPath: "/out/Second.mp4"))
        #expect(m.exportState == .saved(URL(fileURLWithPath: "/out/My Song.mp4")))
    }

    @Test func startingAnotherVideoClearsTheEarlierSavedMessage() async {
        let exporter = FakeExporter()
        let m = await readyModel(exporter: exporter)
        await m.makeVideo(to: destination)
        #expect(m.savedVideoMessage != nil)
        exporter.behavior = .waitForCancel(progress: [])
        let running = Task { await m.makeVideo(to: destination) }
        #expect(await eventually { m.isExporting })
        #expect(m.savedVideoMessage == nil)
        #expect(m.savedVideoURL == nil)
        m.cancelExport()
        await running.value
    }

    @Test func aFailureShowsItsPlainMessageAndLeavesTheWindowReadyAgain() async {
        let m = await readyModel(exporter: FakeExporter(.finish(.failed(.cannotSaveToFolder))))
        await m.makeVideo(to: destination)
        #expect(m.notice == "Couldn't save to that folder")
        #expect(m.exportState == .idle)
        #expect(m.savedVideoMessage == nil)
        #expect(m.canMakeVideo)
        #expect(m.lastSaveFolder == nil)
    }

    @Test func aLaterSuccessClearsAnEarlierFailureMessage() async {
        let exporter = FakeExporter(.finish(.failed(.diskFull)))
        let m = await readyModel(exporter: exporter)
        await m.makeVideo(to: destination)
        #expect(m.notice == "Not enough disk space")
        exporter.behavior = .finish(.completed(destination))
        await m.makeVideo(to: destination)
        #expect(m.notice == nil)
    }
}

/// While a video is being made (SPEC section 6.2).
@MainActor
@Suite("Main window: while a video is being made")
struct MainWindowExportInProgressTests {
    /// A window whose exporter reports 25% and then waits, with the export running.
    func busyWindow() async -> (model: MainWindowModel, running: Task<Void, Never>) {
        let m = await readyModel(exporter: FakeExporter(.waitForCancel(progress: [0.25])))
        let running = Task { await m.makeVideo(to: destination) }
        _ = await eventually { m.exportState == .making(progress: 0.25) }
        return (m, running)
    }

    @Test func progressShowsAsAPercentage() async {
        let (m, running) = await busyWindow()
        #expect(m.isExporting)
        #expect(m.progressFraction == 0.25)
        #expect(m.progressLabel == "Making video… 25%")
        m.cancelExport()
        await running.value
    }

    @Test func untilTheFirstProgressArrivesTheWindowSaysPreparing() async {
        let m = await readyModel(exporter: FakeExporter(.waitForCancel(progress: [])))
        let running = Task { await m.makeVideo(to: destination) }
        #expect(await eventually { m.isExporting })
        #expect(m.isPreparing)
        #expect(m.progressFraction == nil)
        #expect(m.progressLabel == "Preparing…")
        m.cancelExport()
        await running.value
        #expect(!m.isPreparing)
        #expect(m.progressLabel == nil)
    }

    @Test func oncePreparingIsOverTheWindowShowsThePercentage() async {
        let (m, running) = await busyWindow()
        #expect(!m.isPreparing)
        #expect(m.progressLabel == "Making video… 25%")
        m.cancelExport()
        await running.value
    }

    @Test func progressNeverGoesBackwards() async {
        let m = await readyModel(exporter: FakeExporter(.waitForCancel(progress: [0.6, 0.4])))
        let running = Task { await m.makeVideo(to: destination) }
        #expect(await eventually { m.progressFraction == 0.6 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(m.progressFraction == 0.6)
        m.cancelExport()
        await running.value
    }

    @Test func theOtherControlsAreLocked() async {
        let (m, running) = await busyWindow()
        #expect(m.controlsLocked)
        #expect(!m.canMakeVideo)
        #expect(!m.canAdjustCrop)
        m.cancelExport()
        await running.value
        #expect(!m.controlsLocked)
    }

    @Test func choosingAFileOrMovingTheCropDoesNothingMidExport() async {
        let (m, running) = await busyWindow()
        let before = (m.audio, m.image, m.cropPosition)
        await m.chooseAudio(at: URL(fileURLWithPath: "/media/My Song.mp3"))
        m.nudgeCrop(.left)
        m.resetCropToCenter()
        m.dragCrop(from: .center, byFramePixels: 50, 50)
        #expect(m.audio == before.0)
        #expect(m.image == before.1)
        #expect(m.cropPosition == before.2)
        m.cancelExport()
        await running.value
    }

    @Test func aSecondMakeVideoIsIgnoredWhileOneRuns() async {
        let exporter = FakeExporter(.waitForCancel(progress: [0.1]))
        let m = await readyModel(exporter: exporter)
        let running = Task { await m.makeVideo(to: destination) }
        #expect(await eventually { m.isExporting })
        await m.makeVideo(to: URL(fileURLWithPath: "/out/Again.mp4"))
        #expect(exporter.startedCount == 1)
        m.cancelExport()
        await running.value
    }

    @Test func cancelEndsTheExportQuietlyWithNoMessageAndNoSavedVideo() async {
        let (m, running) = await busyWindow()
        m.cancelExport()
        await running.value
        #expect(m.exportState == .idle)
        #expect(m.notice == nil)
        #expect(m.savedVideoURL == nil)
        #expect(m.canMakeVideo)
        #expect(m.lastSaveFolder == nil)
    }

    @Test func aVideoCanBeMadeStraightAfterACancel() async {
        let exporter = FakeExporter(.waitForCancel(progress: []))
        let m = await readyModel(exporter: exporter)
        let running = Task { await m.makeVideo(to: destination) }
        #expect(await eventually { m.isExporting })
        m.cancelExport()
        await running.value
        exporter.behavior = .finish(.completed(destination))
        await m.makeVideo(to: destination)
        #expect(m.exportState == .saved(destination))
    }

    @Test func dropsAreRefusedWithTheWaitMessageAndChangeNothing() async {
        let (m, running) = await busyWindow()
        let audioBefore = m.audio
        await m.drop([URL(fileURLWithPath: "/media/My Song.mp3")])
        #expect(m.notice == "Wait for the current video to finish.")
        #expect(m.audio == audioBefore)
        #expect(m.pendingReplacement == nil)
        m.cancelExport()
        await running.value
    }

    @Test func theWaitMessageGoesAwayOnceTheVideoIsDone() async {
        let (m, running) = await busyWindow()
        await m.drop([URL(fileURLWithPath: "/media/My Song.mp3")])
        #expect(m.notice == "Wait for the current video to finish.")
        m.cancelExport()
        await running.value
        #expect(m.notice == nil)
    }

    @Test func noDropGetsTheHighlightWhileAVideoIsBeingMade() async {
        let (m, running) = await busyWindow()
        #expect(!m.acceptsDrop(of: [DroppedFile(url: URL(fileURLWithPath: "/media/a.mp3"), kind: .audio)]))
        m.cancelExport()
        await running.value
        #expect(m.acceptsDrop(of: [DroppedFile(url: URL(fileURLWithPath: "/media/a.mp3"), kind: .audio)]))
    }
}
