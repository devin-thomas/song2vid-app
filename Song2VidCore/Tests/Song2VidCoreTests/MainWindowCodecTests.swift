import Foundation
import Testing
@testable import Song2VidCore

/// A defaults domain of its own, so a test never reads or changes the real one, removed when the test is done.
private final class ScratchDefaults {
    let name = "song2vid-codec-test-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { defaults = UserDefaults(suiteName: name)! }
    deinit { defaults.removePersistentDomain(forName: name) }

    /// A window as the app opens it: a new model on this domain.
    @MainActor
    func window(hevc: Bool = true, exporter: any VideoExporting = SystemVideoExporter()) -> MainWindowModel {
        MainWindowModel(exporter: exporter, codecDefaults: defaults, isCodecAvailable: { $0 == .h264 || hevc })
    }
}

/// SPEC sections 23 and 25: the Codec picker's rules, with the system's answer to "can this Mac make HEVC" stood in.
@MainActor
@Suite("Main window: Codec")
struct MainWindowCodecTests {
    // MARK: Remembered

    @Test func aFreshDefaultsDomainStartsOnH264() {
        let scratch = ScratchDefaults()
        #expect(scratch.window().codec == .h264)
        #expect(scratch.defaults.object(forKey: CodecPreference.key) == nil)
    }

    @Test func choosingHEVCIsRememberedByTheNextLaunch() {
        let scratch = ScratchDefaults()
        let first = scratch.window()
        first.codec = .hevc
        #expect(first.codec == .hevc)
        // A new model on the same defaults stands for quitting and opening the app again.
        #expect(scratch.window().codec == .hevc)
    }

    @Test func goingBackToH264IsRememberedToo() {
        let scratch = ScratchDefaults()
        let first = scratch.window()
        first.codec = .hevc
        first.codec = .h264
        #expect(scratch.window().codec == .h264)
    }

    @Test func theCodecIsStoredUnderOneKeyAsItsCommandName() {
        let scratch = ScratchDefaults()
        scratch.window().codec = .hevc
        #expect(scratch.defaults.string(forKey: "videoCodec") == "hevc")
    }

    @Test(arguments: ["", "HEVC", "av1", "h265"])
    func anUnrecognisedStoredValueStartsOnH264(stored: String) {
        let scratch = ScratchDefaults()
        scratch.defaults.set(stored, forKey: CodecPreference.key)
        #expect(scratch.window().codec == .h264)
    }

    @Test func changingTheCodecChangesNothingElse() async {
        let scratch = ScratchDefaults()
        let m = scratch.window()
        m.frameShape = .oneByOne
        m.resolution = .p2160
        m.codec = .hevc
        #expect(m.frameShape == .oneByOne)
        #expect(m.resolution == .p2160)
        #expect(m.cropPosition == .center)
        #expect(m.notice == nil)
    }

    @Test func theCodecIsOfferedForEveryFrameShapeIncludingOriginal() {
        let m = ScratchDefaults().window()
        for shape in FrameShape.allCases {
            m.frameShape = shape
            #expect(m.codecPickerEnabled, "the Codec picker is missing for \(shape)")
        }
        // Original hides the Resolution picker but not the Codec picker.
        #expect(!m.showsResolutionPicker)
        #expect(m.codecPickerEnabled)
    }

    // MARK: When this Mac can't make HEVC

    @Test func withoutHEVCThePickerIsDisabledWithTheNoteAndStaysOnH264() {
        let m = ScratchDefaults().window(hevc: false)
        #expect(!m.canMakeHEVC)
        #expect(!m.codecPickerEnabled)
        #expect(m.codecNote == "This computer can't make HEVC videos.")
        #expect(m.codec == .h264)
    }

    @Test func withHEVCThereIsNoNote() {
        let m = ScratchDefaults().window()
        #expect(m.codecNote == nil)
        #expect(m.codecPickerEnabled)
    }

    @Test func aRememberedHEVCStartsOnH264WhereHEVCIsMissingAndKeepsHEVCRemembered() {
        let scratch = ScratchDefaults()
        scratch.window().codec = .hevc
        let without = scratch.window(hevc: false)
        #expect(without.codec == .h264)
        #expect(scratch.defaults.string(forKey: CodecPreference.key) == "hevc")
        // The choice comes back on a computer that can make it.
        #expect(scratch.window(hevc: true).codec == .hevc)
    }

    @Test func aWindowWithoutHEVCRefusesToSelectItAndChangesNothingRemembered() {
        let scratch = ScratchDefaults()
        let m = scratch.window(hevc: false)
        m.codec = .hevc
        #expect(m.codec == .h264)
        #expect(scratch.defaults.object(forKey: CodecPreference.key) == nil)
    }

    @Test func choosingH264WhereHEVCIsMissingDoesNotForgetARememberedHEVC() {
        let scratch = ScratchDefaults()
        scratch.window().codec = .hevc
        let without = scratch.window(hevc: false)
        without.codec = .h264
        #expect(scratch.defaults.string(forKey: CodecPreference.key) == "hevc")
    }

    // MARK: Making a video

    @Test func theChosenCodecGoesToTheExport() async {
        let scratch = ScratchDefaults()
        for codec in Codec.allCases {
            let exporter = FakeExporter()
            let m = await readyModel(exporter: exporter, defaults: scratch.defaults)
            m.codec = codec
            await m.makeVideo(to: URL(fileURLWithPath: "/out/My Song.mp4"))
            #expect(exporter.requests.last?.codec == codec)
        }
    }

    @Test func aRememberedHEVCWhereHEVCIsMissingMakesH264() async {
        let scratch = ScratchDefaults()
        scratch.window().codec = .hevc
        let exporter = FakeExporter()
        let m = await readyModel(exporter: exporter, defaults: scratch.defaults, hevc: false)
        await m.makeVideo(to: URL(fileURLWithPath: "/out/My Song.mp4"))
        #expect(exporter.requests.last?.codec == .h264)
        #expect(m.savedCodecMessage == "Made as H.264.")
    }

    @Test func theCodecIsLockedWhileAVideoIsBeingMadeAndUnlocksAfterwards() async {
        let scratch = ScratchDefaults()
        let exporter = FakeExporter(.waitForCancel(progress: [0.3]))
        let m = await readyModel(exporter: exporter, defaults: scratch.defaults)
        let making = Task { await m.makeVideo(to: URL(fileURLWithPath: "/out/My Song.mp4")) }
        #expect(await eventually { m.isExporting })
        #expect(!m.codecPickerEnabled)
        m.codec = .hevc
        #expect(m.codec == .h264)
        #expect(scratch.defaults.object(forKey: CodecPreference.key) == nil)
        m.cancelExport()
        await making.value
        #expect(m.codecPickerEnabled)
        m.codec = .hevc
        #expect(m.codec == .hevc)
    }

    // MARK: The done state

    @Test func theDoneStateNamesTheCodecOfTheVideoJustMade() async {
        let scratch = ScratchDefaults()
        let saved = URL(fileURLWithPath: "/out/My Song.mp4")
        let m = await readyModel(exporter: FakeExporter(.finish(.completed(saved))), defaults: scratch.defaults)
        #expect(m.savedCodecMessage == nil)
        m.codec = .hevc
        await m.makeVideo(to: saved)
        #expect(m.savedVideoMessage == "Video saved.")
        #expect(m.savedCodecMessage == "Made as HEVC.")
        // Choosing again after the save does not rewrite what was made.
        m.codec = .h264
        #expect(m.savedCodecMessage == "Made as HEVC.")
        await m.makeVideo(to: saved)
        #expect(m.savedCodecMessage == "Made as H.264.")
    }

    @Test func aCancelledOrFailedVideoNamesNoCodec() async {
        let scratch = ScratchDefaults()
        let failing = await readyModel(exporter: FakeExporter(.finish(.failed(.encodingFailed))), defaults: scratch.defaults)
        failing.codec = .hevc
        await failing.makeVideo(to: URL(fileURLWithPath: "/out/My Song.mp4"))
        #expect(failing.savedCodecMessage == nil)
        #expect(failing.savedCodec == nil)
    }
}
