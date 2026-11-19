import AVFoundation
import CoreMedia
import Foundation

// Audio is decoded with AVAudioFile and AVAudioConverter, not AVAssetReader: the reader's decode path goes
// through the system audio server and can stall for 90 seconds when no audio hardware is available (a
// Mac mini with no display or speakers, a remote session). AVAudioFile decodes in-process, at hundreds of
// times real time.

extension AudioInfo {
    /// Checks that macOS can read the file's audio (SPEC section 7) and measures it.
    ///
    /// The length is counted from the decoded audio, so it is exact even for MP3s whose header only
    /// estimates it. Decoding is fast (minutes of audio per second) but call this off the main thread.
    public static func read(from url: URL) throws(ExportError) -> AudioInfo {
        let file = try openAudio(at: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AudioFeeder.chunkFrames) else {
            throw .unreadableAudio
        }
        var frames: Int64 = 0
        while true {
            do {
                try file.read(into: buffer, frameCount: AudioFeeder.chunkFrames)
            } catch {
                // Reading at the very end of some formats reports an error rather than zero frames.
                if file.framePosition >= file.length && frames > 0 { break }
                throw .unreadableAudio
            }
            if buffer.frameLength == 0 { break }
            frames += Int64(buffer.frameLength)
        }
        guard frames > 0 else { throw .unreadableAudio }
        return AudioInfo(
            duration: Double(frames) / format.sampleRate,
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount)
        )
    }
}

private func openAudio(at url: URL) throws(ExportError) -> AVAudioFile {
    guard let file = try? AVAudioFile(forReading: url),
          file.processingFormat.sampleRate > 0, file.processingFormat.channelCount > 0
    else { throw .unreadableAudio }
    return file
}

/// Decodes the audio and hands it to the writer as sample buffers, converted to the sample rate and channel count
/// of the `AudioTarget` (higher rates are resampled, extra channels mixed down). Used from one queue at a time.
final class AudioFeeder: @unchecked Sendable {
    static let chunkFrames: AVAudioFrameCount = 16_384

    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let input: AVAudioPCMBuffer
    private let output: AVAudioPCMBuffer
    private let format: AVAudioFormat
    private var framesEmitted: Int64 = 0
    private var inputExhausted = false
    private var finished = false
    private var readFailed = false

    init(url: URL, target: AudioTarget) throws(ExportError) {
        file = try openAudio(at: url)
        let layout = AVAudioChannelLayout(layoutTag: target.channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo)
        var description = AudioStreamBasicDescription(
            mSampleRate: target.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * target.channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * target.channels),
            mChannelsPerFrame: UInt32(target.channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        guard let layout,
              let format = AVAudioFormat(streamDescription: &description, channelLayout: layout),
              let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: Self.chunkFrames),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.chunkFrames)
        else { throw .unreadableAudio }
        self.format = format
        self.converter = converter
        self.input = input
        self.output = output
    }

    /// The next stretch of audio, or nil at the end. Throws `.audioReadFailed` if decoding breaks partway.
    func nextSampleBuffer() throws(ExportError) -> CMSampleBuffer? {
        if finished { return nil }
        output.frameLength = 0
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { [self] _, inputStatus in
            if inputExhausted {
                inputStatus.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: input, frameCount: Self.chunkFrames)
            } catch {
                if file.framePosition < file.length { readFailed = true }
                input.frameLength = 0
            }
            if input.frameLength == 0 {
                inputExhausted = true
                inputStatus.pointee = .endOfStream
                return nil
            }
            inputStatus.pointee = .haveData
            return input
        }
        if readFailed || status == .error { throw .audioReadFailed }
        if status == .endOfStream { finished = true }
        guard output.frameLength > 0 else { return nil }

        let buffer = try makeSampleBuffer()
        framesEmitted += Int64(output.frameLength)
        return buffer
    }

    private func makeSampleBuffer() throws(ExportError) -> CMSampleBuffer {
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: format.streamDescription, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else { throw .encodingFailed }

        var sampleBuffer: CMSampleBuffer?
        guard CMAudioSampleBufferCreateWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil,
            refcon: nil, formatDescription: formatDescription, sampleCount: CMItemCount(output.frameLength),
            presentationTimeStamp: CMTime(value: framesEmitted, timescale: CMTimeScale(format.sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else { throw .encodingFailed }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0, bufferList: output.audioBufferList
        ) == noErr else { throw .encodingFailed }
        return sampleBuffer
    }
}
