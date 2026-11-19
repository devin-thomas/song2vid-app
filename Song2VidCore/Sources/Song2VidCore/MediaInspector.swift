import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

/// A song the person has chosen.
public struct LoadedAudio: Equatable, Sendable {
    public let url: URL
    /// Length in seconds.
    public let duration: Double

    public init(url: URL, duration: Double) {
        self.url = url
        self.duration = duration
    }

    public var name: String { url.lastPathComponent }
}

/// An image the person has chosen. `size` is in pixels after applying the image's orientation tag.
public struct LoadedImage: Equatable, Sendable {
    public let url: URL
    public let size: PixelSize

    public init(url: URL, size: PixelSize) {
        self.url = url
        self.size = size
    }

    public var name: String { url.lastPathComponent }
}

/// Why a chosen file can't be used (SPEC section 7).
public enum MediaError: Error, Equatable, Sendable {
    case unreadableAudio
    case unreadableImage

    /// The text to show the person.
    public var message: String {
        switch self {
        case .unreadableAudio: "Song2Vid can't read this audio file."
        case .unreadableImage: "Song2Vid can't read this image file."
        }
    }
}

/// A decoded copy of the image for drawing the preview, with its orientation already applied.
public struct PreviewImage: @unchecked Sendable {
    public let cgImage: CGImage

    public init(cgImage: CGImage) {
        self.cgImage = cgImage
    }
}

/// Reads the facts the window needs from a chosen file.
public protocol MediaInspecting: Sendable {
    func inspectAudio(at url: URL) async throws -> LoadedAudio
    func inspectImage(at url: URL) async throws -> LoadedImage
    /// A picture to draw in the preview, or nil if there isn't one.
    func previewImage(at url: URL) async -> PreviewImage?
}

extension MediaInspecting {
    public func previewImage(at url: URL) async -> PreviewImage? { nil }
}

/// The real inspector: AVFoundation for audio, ImageIO for images.
public struct SystemMediaInspector: MediaInspecting {
    public init() {}

    public func inspectAudio(at url: URL) async throws -> LoadedAudio {
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            let duration = try await asset.load(.duration).seconds
            guard !tracks.isEmpty, duration.isFinite, duration > 0 else { throw MediaError.unreadableAudio }
            return LoadedAudio(url: url, duration: duration)
        } catch {
            throw MediaError.unreadableAudio
        }
    }

    public func inspectImage(at url: URL) async throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              Self.thumbnail(of: source, longSide: 32) != nil
        else { throw MediaError.unreadableImage }

        // Orientation tags 5 to 8 turn the picture on its side.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let size = (5...8).contains(orientation)
            ? PixelSize(width: height, height: width)
            : PixelSize(width: width, height: height)
        return LoadedImage(url: url, size: size)
    }

    public func previewImage(at url: URL) async -> PreviewImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = Self.thumbnail(of: source, longSide: 2400)
        else { return nil }
        return PreviewImage(cgImage: image)
    }

    /// Decodes the image at no more than `longSide` pixels, with its orientation applied.
    private static func thumbnail(of source: CGImageSource, longSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
