import CoreGraphics
import Foundation
import ImageIO

extension ImageInfo {
    /// Checks that macOS can read the image (SPEC section 7) and reports its size after orientation.
    public static func read(from url: URL) throws(ExportError) -> ImageInfo {
        let (_, size) = try openImage(at: url)
        return ImageInfo(size: size)
    }
}

/// Opens an image file and finds its oriented size.
private func openImage(at url: URL) throws(ExportError) -> (CGImageSource, PixelSize) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetStatus(source) == .statusComplete,
          CGImageSourceGetCount(source) > 0,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0
    else { throw .unreadableImage }
    // Orientation tags 5 to 8 turn the image a quarter turn, so the width and height trade places.
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    let swapped = (5...8).contains(orientation)
    return (source, PixelSize(width: swapped ? height : width, height: swapped ? width : height))
}

/// Decodes the oriented image, with an optional cap on its longest side.
func decodeImage(at url: URL, maxLongSide: Int? = nil) throws(ExportError) -> (image: CGImage, size: PixelSize) {
    let (source, size) = try openImage(at: url)
    let longSide = max(size.width, size.height)
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: min(longSide, maxLongSide ?? longSide),
        kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        throw .unreadableImage
    }
    return (image, size)
}
