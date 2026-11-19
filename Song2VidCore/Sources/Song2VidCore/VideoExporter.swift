import AVFoundation
import Foundation

/// Makes the MP4: one still frame, held for the whole song, with the song as AAC audio (SPEC section 6.3).
///
/// There is no UI in here. Call `export`, show the progress it reports, and cancel by cancelling the task
/// that is running it.
public enum VideoExporter {
    /// The video frame rate (SPEC section 6.3).
    public static let framesPerSecond = 30

    /// Writes the video to `request.destinationURL`.
    ///
    /// - Parameter progress: Called with a fraction from 0 to 1, from a background queue, never going
    ///   backwards. It reports 1 only once the file is in place.
    /// - Returns: How the export ended. Cancelling the calling task cancels the export; the result is then
    ///   `.cancelled`. Unless the result is `.completed`, no file is left behind and a file already at the
    ///   destination is untouched.
    public static func export(
        _ request: ExportRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> ExportOutcome {
        if Task.isCancelled { return .cancelled }

        let audio: AudioInfo
        let target: AudioTarget
        let feeder: AudioFeeder
        let encoded: EncodedStill
        // One video frame per 1/30 s, enough to cover the whole audio.
        var frameCount = 1
        do {
            audio = try AudioInfo.read(from: request.audioURL)
            target = try AudioTarget(for: audio)
            feeder = try AudioFeeder(url: request.audioURL, target: target)
            frameCount = max(1, Int((audio.duration * Double(framesPerSecond)).rounded(.up)))
            if Task.isCancelled { return .cancelled }
            let decoded = try decodeImage(at: request.imageURL)
            let still = try StillFrame(image: decoded.image, frame: request.frame)
            encoded = try EncodedStill(
                still: still, size: request.frame.size, frameCount: frameCount, isCancelled: { Task.isCancelled }
            )
        } catch {
            return Task.isCancelled ? .cancelled : .failed(error)
        }
        if Task.isCancelled { return .cancelled }

        let folder = request.destinationURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return .failed(.cannotSaveToFolder) }
        if FileManager.default.fileExists(atPath: request.destinationURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return .failed(.cannotSaveToFolder)
        }
        guard canWrite(to: request.destinationURL) else { return .failed(.cannotSaveToFolder) }

        let session: ExportSession
        do {
            session = try ExportSession(
                request: request, feeder: feeder, target: target, audio: audio, encoded: encoded,
                frameCount: frameCount, progress: progress
            )
        } catch {
            return .failed(error)
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                session.start(continuation)
            }
        } onCancel: {
            session.cancel()
        }
    }
}

/// True if a video can be saved at `destination`. In a sandboxed app the person's choice in the save dialog opens up
/// that one file but not its folder, so the folder can't be asked whether it is writable: the file is tried instead.
private func canWrite(to destination: URL) -> Bool {
    let manager = FileManager.default
    if manager.isWritableFile(atPath: destination.deletingLastPathComponent().path) { return true }
    if manager.fileExists(atPath: destination.path) { return manager.isWritableFile(atPath: destination.path) }
    guard manager.createFile(atPath: destination.path, contents: nil) else { return false }
    try? manager.removeItem(at: destination)
    return true
}

/// One export in flight. The writer is fed from two queues (audio and video), and any of those, the
/// caller's cancel, or the writer's completion can end it, so the ending is guarded by a lock and happens once.
private final class ExportSession: @unchecked Sendable {
    private let request: ExportRequest
    private let audio: AudioInfo
    private let encoded: EncodedStill
    private let progress: @Sendable (Double) -> Void

    /// The video is written beside the destination under a hidden name, then moved into place, so a
    /// cancelled or failed export leaves nothing (and never damages a file the person agreed to replace).
    private let partialURL: URL
    private let writer: AVAssetWriter
    private let feeder: AudioFeeder
    private let audioInput: AVAssetWriterInput
    private let videoInput: AVAssetWriterInput

    private let lock = NSLock()
    private var continuation: CheckedContinuation<ExportOutcome, Never>?
    private var outcome: ExportOutcome?
    private var isFinished = false
    private var isCommitting = false
    private var unfinishedInputs = 2
    private var reportedProgress = 0.0

    private let frameCount: Int

    init(
        request: ExportRequest, feeder: AudioFeeder, target: AudioTarget, audio: AudioInfo, encoded: EncodedStill,
        frameCount: Int, progress: @escaping @Sendable (Double) -> Void
    ) throws(ExportError) {
        self.request = request
        self.feeder = feeder
        self.audio = audio
        self.encoded = encoded
        self.frameCount = frameCount
        self.progress = progress

        let folder = request.destinationURL.deletingLastPathComponent()
        // Beside the destination when the folder is writable (so the final move stays on one volume). A sandboxed
        // app may only write the chosen file itself, so the work is done in the temporary folder instead.
        let partialFolder = request.scratchFolder
            ?? (FileManager.default.isWritableFile(atPath: folder.path) ? folder : FileManager.default.temporaryDirectory)
        partialURL = partialFolder.appendingPathComponent(".\(UUID().uuidString).song2vid-partial")

        guard let writer = try? AVAssetWriter(outputURL: partialURL, fileType: .mp4) else {
            throw .cannotSaveToFolder
        }
        writer.shouldOptimizeForNetworkUse = true
        self.writer = writer

        // The writer raises an Objective-C exception, which nothing can catch, if it is handed settings its
        // encoder can't use. It is asked first, so an unexpected configuration becomes an error instead.
        guard writer.canApply(outputSettings: target.outputSettings, forMediaType: .audio) else {
            throw .encodingFailed
        }
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: target.outputSettings)
        audioInput.expectsMediaDataInRealTime = false

        // The frames are already H.264, so the writer only packages them.
        videoInput = AVAssetWriterInput(
            mediaType: .video, outputSettings: nil, sourceFormatHint: encoded.formatDescription
        )
        videoInput.expectsMediaDataInRealTime = false
    }

    // MARK: Starting and ending

    func start(_ continuation: CheckedContinuation<ExportOutcome, Never>) {
        lock.lock()
        self.continuation = continuation
        let ready = outcome != nil
        lock.unlock()
        if ready { deliver(); return }

        guard writer.canAdd(audioInput), writer.canAdd(videoInput) else { finish(.failed(.encodingFailed)); return }
        writer.add(videoInput)
        writer.add(audioInput)
        guard writer.startWriting() else { finish(.failed(classify(writer.error, default: .cannotSaveToFolder))); return }
        writer.startSession(atSourceTime: .zero)

        audioInput.requestMediaDataWhenReady(on: audioQueue) { [self] in pumpAudio() }
        videoInput.requestMediaDataWhenReady(on: videoQueue) { [self] in pumpVideo() }
    }

    private let audioQueue = DispatchQueue(label: "song2vid.export.audio")
    private let videoQueue = DispatchQueue(label: "song2vid.export.video")
    /// Only touched from `videoQueue`.
    private var nextFrame = 0

    /// Appends decoded audio while the writer wants more.
    private func pumpAudio() {
        while audioInput.isReadyForMoreMediaData {
            if isEnded { return }
            let next: CMSampleBuffer?
            do {
                next = try feeder.nextSampleBuffer()
            } catch {
                finish(.failed(error))
                return
            }
            guard let buffer = next else {
                audioInput.markAsFinished()
                inputFinished()
                return
            }
            if !audioInput.append(buffer) {
                finish(.failed(classify(writer.error, default: .encodingFailed)))
                return
            }
        }
    }

    /// Appends the encoded group again at each frame time while the writer wants more.
    private func pumpVideo() {
        while videoInput.isReadyForMoreMediaData {
            if isEnded { return }
            if nextFrame == frameCount {
                videoInput.markAsFinished()
                inputFinished()
                return
            }
            guard let frame = encoded.frame(at: nextFrame) else {
                finish(.failed(.encodingFailed))
                return
            }
            if !videoInput.append(frame) {
                finish(.failed(classify(writer.error, default: .encodingFailed)))
                return
            }
            nextFrame += 1
            report(Double(nextFrame) / Double(frameCount) * 0.99)
        }
    }

    func cancel() {
        lock.lock()
        let committing = isCommitting
        lock.unlock()
        // Once the file is complete and being moved into place there is nothing left to cancel.
        if !committing { finish(.cancelled) }
    }

    private var isEnded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isFinished
    }

    private func report(_ fraction: Double) {
        lock.lock()
        let isNew = !isFinished && fraction - reportedProgress >= 0.005
        if isNew { reportedProgress = fraction }
        lock.unlock()
        if isNew { progress(fraction) }
    }

    /// Called when the audio or video input has been fully written. When both have, the file is closed.
    private func inputFinished() {
        lock.lock()
        unfinishedInputs -= 1
        let allDone = unfinishedInputs == 0 && !isFinished
        if allDone { isCommitting = true }
        lock.unlock()
        guard allDone else { return }

        writer.endSession(atSourceTime: CMTime(seconds: audio.duration, preferredTimescale: 48_000))
        writer.finishWriting { [self] in writerFinished() }
    }

    /// The file is closed. Move it into place, replacing what was there.
    private func writerFinished() {
        guard writer.status == .completed else {
            lock.lock(); isCommitting = false; lock.unlock()
            finish(.failed(classify(writer.error, default: .encodingFailed)))
            return
        }
        do {
            try moveIntoPlace()
        } catch {
            lock.lock(); isCommitting = false; lock.unlock()
            finish(.failed(classify(error, default: .cannotSaveToFolder)))
            return
        }
        // An overwrite in place copies the video, so the finished file and the backup are still in the work folder.
        removePartialFiles()
        progress(1)
        finish(.completed(request.destinationURL))
    }

    /// Puts the finished video at the destination. If this fails, the destination is as it was before: a file that was
    /// there is intact, and a half-copied one is not left behind (SPEC section 6.5).
    private func moveIntoPlace() throws {
        let manager = FileManager.default
        let destination = request.destinationURL
        guard manager.fileExists(atPath: destination.path) else {
            do {
                try manager.moveItem(at: partialURL, to: destination)
            } catch {
                // Moving to another volume copies, and a copy that fails partway can leave its start behind.
                try? manager.removeItem(at: destination)
                throw error
            }
            return
        }
        // The swap is all or nothing, but it needs to work beside the destination and on its volume. It can't
        // in a sandboxed app (which may write only the chosen file) or when the video was built on another volume.
        do {
            _ = try manager.replaceItemAt(destination, withItemAt: partialURL)
            return
        } catch {}
        // Instead, the file is written over in place, after keeping a copy of what it held to put back if that fails.
        let backup = URL(fileURLWithPath: partialURL.path + ".previous")
        try manager.copyItem(at: destination, to: backup)
        do {
            try Self.copyContents(of: partialURL, over: destination)
        } catch {
            try? Self.copyContents(of: backup, over: destination)
            throw error
        }
    }

    /// Replaces the contents of `destination` with those of `source`, keeping the file itself.
    private static func copyContents(of source: URL, over destination: URL) throws {
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let writer = try FileHandle(forWritingTo: destination)
        defer { try? writer.close() }
        try writer.truncate(atOffset: 0)
        while let chunk = try reader.read(upToCount: 1 << 20), !chunk.isEmpty {
            try writer.write(contentsOf: chunk)
        }
        try writer.synchronize()
    }

    /// Ends the export once. Anything but a completed file is torn down and the partial file removed.
    private func finish(_ result: ExportOutcome) {
        lock.lock()
        guard !isFinished else { lock.unlock(); return }
        isFinished = true
        outcome = result
        lock.unlock()

        if case .completed = result {
            deliver()
            return
        }
        // The writer crashes if it is cancelled while a queue is appending to it. The flag set above stops
        // both queues from appending again, so once each has finished what it was doing, it is safe.
        // This hops to another queue because `finish` can be called from one of those two.
        DispatchQueue.global().async { [self] in
            audioQueue.sync {}
            videoQueue.sync {
                if writer.status == .writing || writer.status == .unknown { writer.cancelWriting() }
                removePartialFiles()
            }
            deliver()
        }
    }

    /// Deletes the half-written file, and the scratch files the writer puts beside it, which it can leave
    /// behind when it fails, for example when the disk is full.
    private func removePartialFiles() {
        let folder = partialURL.deletingLastPathComponent()
        let prefix = partialURL.lastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private func deliver() {
        lock.lock()
        let pending = continuation
        continuation = nil
        let result = outcome
        lock.unlock()
        if let pending, let result { pending.resume(returning: result) }
    }

    /// Turns a system error into the message the person sees.
    private func classify(_ error: Error?, default fallback: ExportError) -> ExportError {
        var current = error as NSError?
        while let nsError = current {
            switch (nsError.domain, nsError.code) {
            case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError),
                 (NSPOSIXErrorDomain, Int(ENOSPC)),
                 (AVFoundationErrorDomain, AVError.diskFull.rawValue):
                return .diskFull
            case (NSCocoaErrorDomain, NSFileWriteNoPermissionError),
                 (NSCocoaErrorDomain, NSFileWriteVolumeReadOnlyError),
                 (NSCocoaErrorDomain, NSFileNoSuchFileError),
                 (NSPOSIXErrorDomain, Int(EACCES)),
                 (NSPOSIXErrorDomain, Int(EPERM)),
                 (NSPOSIXErrorDomain, Int(EROFS)):
                return .cannotSaveToFolder
            default:
                current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            }
        }
        return fallback
    }
}
