import CoreMedia
import Foundation
import VideoToolbox

/// One group of pictures of the still frame, already H.264 encoded: a key frame followed by frames that
/// repeat it.
///
/// Every video frame in the song is the same picture, so the video is encoded once, for one group, and
/// that group is written again and again with new timestamps. Encoding cost is then the same for a
/// 30-second song and a 4-minute one, and it does not depend on how busy the hardware encoder is.
struct EncodedStill: @unchecked Sendable {
    /// Key frames come every `groupLength` frames, about every ten seconds.
    static let groupLength = 10 * VideoExporter.framesPerSecond

    /// The compressed frames of one group, in order. The first is a key frame; each later one only
    /// refers back to earlier frames of the group, so any prefix of the group can end the video.
    let samples: [CMSampleBuffer]
    let formatDescription: CMFormatDescription

    /// Encodes `min(frameCount, groupLength)` frames of the picture.
    /// - Parameter isCancelled: Checked between frames.
    init(still: StillFrame, size: PixelSize, frameCount: Int, isCancelled: () -> Bool) throws(ExportError) {
        let count = min(frameCount, Self.groupLength)
        let collector = Collector()

        var created: VTCompressionSession?
        let specification: [CFString: Any] = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true]
        guard VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault, width: Int32(size.width), height: Int32(size.height),
            codecType: kCMVideoCodecType_H264, encoderSpecification: specification as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
            compressionSessionOut: &created
        ) == noErr, let session = created else { throw .encodingFailed }
        defer { VTCompressionSessionInvalidate(session) }

        let properties: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: false,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_AutoLevel,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_ExpectedFrameRate: VideoExporter.framesPerSecond,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: Self.groupLength,
            // The picture is still, so the quality setting is spent on making that one picture sharp.
            kVTCompressionPropertyKey_Quality: 0.75,
            kVTCompressionPropertyKey_ColorPrimaries: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kVTCompressionPropertyKey_TransferFunction: kCVImageBufferTransferFunction_ITU_R_709_2,
            kVTCompressionPropertyKey_YCbCrMatrix: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
        ]
        guard VTSessionSetProperties(session, propertyDictionary: properties as CFDictionary) == noErr,
              VTCompressionSessionPrepareToEncodeFrames(session) == noErr
        else { throw .encodingFailed }

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(VideoExporter.framesPerSecond))
        for index in 0..<count {
            if isCancelled() { throw .encodingFailed }
            let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(VideoExporter.framesPerSecond))
            let frameProperties: CFDictionary? = index == 0
                ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
                : nil
            let status = VTCompressionSessionEncodeFrame(
                session, imageBuffer: still.pixelBuffer, presentationTimeStamp: time, duration: frameDuration,
                frameProperties: frameProperties, infoFlagsOut: nil
            ) { status, _, buffer in
                collector.add(status: status, buffer: buffer)
            }
            guard status == noErr else { throw .encodingFailed }
        }
        guard VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) == noErr else {
            throw .encodingFailed
        }

        let (collected, failed) = collector.result()
        guard !failed, collected.count == count, let first = collected.first,
              let format = CMSampleBufferGetFormatDescription(first)
        else { throw .encodingFailed }
        samples = collected
        formatDescription = format
    }

    /// The frame at position `index` of the whole video: the matching frame of the group, restamped.
    func frame(at index: Int) -> CMSampleBuffer? {
        let timescale = CMTimeScale(VideoExporter.framesPerSecond)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: timescale),
            presentationTimeStamp: CMTime(value: CMTimeValue(index), timescale: timescale),
            decodeTimeStamp: CMTime(value: CMTimeValue(index), timescale: timescale)
        )
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: samples[index % samples.count],
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy
        )
        return status == noErr ? copy : nil
    }

    /// Gathers the encoder's output, which arrives on the encoder's own thread.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var buffers: [CMSampleBuffer] = []
        private var failed = false

        func add(status: OSStatus, buffer: CMSampleBuffer?) {
            lock.lock()
            defer { lock.unlock() }
            if status == noErr, let buffer { buffers.append(buffer) } else { failed = true }
        }

        func result() -> ([CMSampleBuffer], Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (buffers, failed)
        }
    }
}
