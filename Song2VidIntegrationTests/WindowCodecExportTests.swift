import AVFoundation
import Foundation
import Testing
import Song2VidCore

/// Seam 3 from the window's side (SPEC sections 23 and 25): the window's own model, with the real file readers and the
/// real exporter, makes the video in the Codec the picker holds, and a new window on the same defaults starts on it.
@MainActor
@Suite("Window: Codec picker with the real exporter", .serialized)
struct WindowCodecExportTests {
    /// A defaults domain of its own, so the test never touches the real one.
    private func scratchDefaults() -> (defaults: UserDefaults, remove: () -> Void) {
        let name = "song2vid-window-codec-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    /// Opens a window on `defaults`, as the app does at launch, and chooses the song and image like Choose Audio and Choose Image.
    private func openWindow(_ defaults: UserDefaults, workspace: CommandWorkspace) async throws -> MainWindowModel {
        let model = MainWindowModel(codecDefaults: defaults)
        await model.chooseAudio(at: URL(fileURLWithPath: try workspace.tone(seconds: 2.37)))
        await model.chooseImage(at: URL(fileURLWithPath: try workspace.picture(width: 641, height: 481)))
        try #require(model.canMakeVideo)
        return model
    }

    private func sampleType(of video: URL) async throws -> (video: FourCharCode, audio: FourCharCode, seconds: Double) {
        let asset = AVURLAsset(url: video)
        let videoFormat = try #require(try await asset.loadTracks(withMediaType: .video).first?.load(.formatDescriptions).first)
        let audioFormat = try #require(try await asset.loadTracks(withMediaType: .audio).first?.load(.formatDescriptions).first)
        return (
            CMFormatDescriptionGetMediaSubType(videoFormat), CMFormatDescriptionGetMediaSubType(audioFormat),
            try await asset.load(.duration).seconds
        )
    }

    /// With `SONG2VID_TEST_KEEP_DIR` set, a copy of the video is kept there so a person can run ffprobe on it.
    private func keep(_ video: URL, as name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["SONG2VID_TEST_KEEP_DIR"] else { return }
        let target = URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(name)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: video, to: target)
    }

    @Test("A fresh window starts on H.264 and makes an H.264 video named as such")
    func freshWindowMakesH264() async throws {
        let scratch = scratchDefaults()
        defer { scratch.remove() }
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let model = try await openWindow(scratch.defaults, workspace: workspace)
        #expect(model.codec == .h264)
        model.resolution = .p480

        let output = workspace.url("h264.mp4")
        await model.makeVideo(to: output)
        #expect(model.exportState == .saved(output))
        #expect(model.savedCodecMessage == "Made as H.264.")
        let made = try await sampleType(of: output)
        #expect(made.video == kCMVideoCodecType_H264)
        #expect(made.audio == kAudioFormatMPEG4AAC)
        #expect(abs(made.seconds - 2.37) <= 0.1)
        try keep(output, as: "window-h264.mp4")
    }

    @Test("Choosing HEVC in the window makes an hvc1 HEVC video, and the next window starts on HEVC")
    func hevcFromTheWindowIsRememberedByTheNextWindow() async throws {
        // The same suite also runs on Macs that cannot open an HEVC encoder.
        guard CodecSupport.isAvailable(.hevc) else { return }
        let scratch = scratchDefaults()
        defer { scratch.remove() }
        let workspace = try CommandWorkspace()
        defer { workspace.remove() }
        let model = try await openWindow(scratch.defaults, workspace: workspace)
        model.codec = .hevc
        model.resolution = .p480

        let output = workspace.url("hevc.mp4")
        await model.makeVideo(to: output)
        #expect(model.exportState == .saved(output))
        #expect(model.savedCodecMessage == "Made as HEVC.")
        let made = try await sampleType(of: output)
        // `kCMVideoCodecType_HEVC` is the 'hvc1' sample tag.
        #expect(made.video == kCMVideoCodecType_HEVC)
        #expect(made.audio == kAudioFormatMPEG4AAC)
        #expect(abs(made.seconds - 2.37) <= 0.1)
        try keep(output, as: "window-hevc.mp4")

        // Quit and open again: a new window on the same defaults.
        #expect(MainWindowModel(codecDefaults: scratch.defaults).codec == .hevc)
        // And a window on a fresh domain is back on H.264.
        let fresh = scratchDefaults()
        defer { fresh.remove() }
        #expect(MainWindowModel(codecDefaults: fresh.defaults).codec == .h264)
    }
}
