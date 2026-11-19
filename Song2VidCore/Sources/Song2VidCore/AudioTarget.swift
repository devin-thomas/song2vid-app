import AudioToolbox
import AVFoundation
import Foundation

/// What the AAC track is written with (SPEC section 6.3), worked out from what the source is.
///
/// The AAC encoder takes only a fixed list of sample rates, tops out at 48 kHz here, and can't reach 256 kbps
/// below 44.1 kHz. Handing the writer anything else makes it raise an Objective-C exception, which would end
/// the app, so the settings are always taken from what the encoder says it can do.
struct AudioTarget: Equatable {
    let sampleRate: Double
    let channels: Int
    let bitRate: Int

    /// The bit rate asked for (SPEC section 6.3), used whenever the encoder can do it.
    static let wantedBitRate = 256_000
    /// The highest sample rate written. Sources above it are converted down to it.
    static let highestSampleRate = 48_000.0

    /// - Throws: `.encodingFailed` if the encoder can't offer a usable configuration for this audio.
    init(for info: AudioInfo) throws(ExportError) {
        let rates = Self.encodableSampleRates()
        // The source's rate if AAC has it; otherwise the next one up (so no high frequencies are lost),
        // never above the limit.
        let wanted = min(info.sampleRate, Self.highestSampleRate)
        guard let rate = rates.first(where: { $0 >= wanted && $0 <= Self.highestSampleRate })
                ?? rates.last(where: { $0 <= Self.highestSampleRate })
        else { throw .encodingFailed }
        sampleRate = rate
        // Mono stays mono and everything else is stereo (more than two channels are mixed down).
        channels = info.channelCount == 1 ? 1 : 2

        let possible = Self.encodableBitRates(sampleRate: rate, channels: channels)
        guard let bitRate = possible.filter({ $0 <= Self.wantedBitRate }).max() ?? possible.min() else {
            throw .encodingFailed
        }
        self.bitRate = bitRate
    }

    /// The writer input's output settings.
    var outputSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitRate,
            AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant,
        ]
    }

    /// The sample rates the AAC encoder offers, lowest first. Empty if the system won't say.
    private static func encodableSampleRates() -> [Double] {
        var description = AudioStreamBasicDescription(
            mSampleRate: 0, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: 0, mBytesPerFrame: 0, mChannelsPerFrame: 0, mBitsPerChannel: 0, mReserved: 0
        )
        let specifierSize = UInt32(MemoryLayout.size(ofValue: description))
        var size: UInt32 = 0
        guard AudioFormatGetPropertyInfo(
            kAudioFormatProperty_AvailableEncodeSampleRates, specifierSize, &description, &size
        ) == noErr, size > 0 else { return [] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioFormatGetProperty(
            kAudioFormatProperty_AvailableEncodeSampleRates, specifierSize, &description, &size, &ranges
        ) == noErr else { return [] }
        return ranges.filter { $0.mMinimum == $0.mMaximum && $0.mMinimum > 0 }.map(\.mMinimum).sorted()
    }

    /// The bit rates the AAC encoder can use at this sample rate and channel count. Empty if the system won't say.
    private static func encodableBitRates(sampleRate: Double, channels: Int) -> [Int] {
        guard let source = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels)),
              let aac = AVAudioFormat(settings: [
                  AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels,
              ]),
              let converter = AVAudioConverter(from: source, to: aac)
        else { return [] }
        return (converter.applicableEncodeBitRates ?? []).map(\.intValue)
    }
}
