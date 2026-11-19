import AVFoundation
import Testing
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Generates the tones and images the integration tests export. Nothing here reads real media.
enum TestMedia {
    /// A fresh empty folder that the caller removes when done.
    static func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("song2vid-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The audio file formats the tests can generate (SPEC section 7 lists what Song2Vid must read).
    enum AudioKind: String, CaseIterable, Sendable {
        case wav, aiff, caf, aac, alac

        var fileExtension: String {
            switch self {
            case .wav: "wav"
            case .aiff: "aiff"
            case .caf: "caf"
            case .aac, .alac: "m4a"
            }
        }

        func settings(sampleRate: Double, channels: Int) -> [String: Any] {
            var settings: [String: Any] = [AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels]
            switch self {
            case .wav, .caf:
                settings[AVFormatIDKey] = kAudioFormatLinearPCM
                settings[AVLinearPCMBitDepthKey] = 16
                settings[AVLinearPCMIsFloatKey] = false
            case .aiff:
                settings[AVFormatIDKey] = kAudioFormatLinearPCM
                settings[AVLinearPCMBitDepthKey] = 16
                settings[AVLinearPCMIsFloatKey] = false
                settings[AVLinearPCMIsBigEndianKey] = true
            case .aac:
                settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            case .alac:
                settings[AVFormatIDKey] = kAudioFormatAppleLossless
            }
            return settings
        }
    }

    /// A sine tone, written in the given format. More than two channels get a standard surround layout
    /// (3 is front left, right and centre; 6 is 5.1), because macOS needs one to mix them down.
    @discardableResult
    static func writeTone(
        to url: URL,
        seconds: Double = 3,
        sampleRate: Double = 44_100,
        channels: Int = 2,
        kind: AudioKind = .wav
    ) throws -> URL {
        var settings = kind.settings(sampleRate: sampleRate, channels: channels)
        let format: AVAudioFormat
        if channels > 2 {
            let tag: AudioChannelLayoutTag = switch channels {
            case 3: kAudioChannelLayoutTag_MPEG_3_0_A
            case 6: kAudioChannelLayoutTag_MPEG_5_1_A
            default: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)
            }
            let layout = try #require(AVAudioChannelLayout(layoutTag: tag))
            format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, interleaved: false, channelLayout: layout)
            settings[AVChannelLayoutKey] = Data(bytes: layout.layout, count: MemoryLayout<AudioChannelLayout>.size)
        } else {
            format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels)))
        }
        let frames = AVAudioFrameCount((seconds * sampleRate).rounded())
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<channels {
            let samples = try #require(buffer.floatChannelData)[channel]
            for frame in 0..<Int(frames) {
                samples[frame] = Float(0.3 * sin(2 * Double.pi * 440 * Double(frame) / sampleRate))
            }
        }
        let file = try AVAudioFile(
            forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false
        )
        try file.write(from: buffer)
        return url
    }

    /// An image with a red left half and a blue right half, so tests can tell where it was drawn.
    /// `orientation` is the EXIF orientation tag written into the file (1 is upright).
    @discardableResult
    static func writeImage(
        to url: URL,
        width: Int,
        height: Int,
        type: UTType = .png,
        orientation: Int = 1,
        transparent: Bool = false
    ) throws -> URL {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let alpha = transparent ? CGImageAlphaInfo.premultipliedFirst : CGImageAlphaInfo.noneSkipFirst
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        // A transparent image is left empty: every pixel has zero alpha.
        if !transparent {
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return url
    }

    /// The first frame of the MP4 as an RGB bitmap, for checking what was drawn.
    static func firstFrame(of video: URL) async throws -> FramePixels {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        let image = try await generator.image(at: .zero).image
        return try FramePixels(image)
    }
}

/// A decoded frame that can be sampled by position, with (0, 0) at the top-left corner.
struct FramePixels {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) throws {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// The red, green and blue values (0 to 255) at a pixel.
    func rgb(x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let offset = (y * width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }
}
