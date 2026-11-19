import CoreGraphics
import CoreVideo
import Foundation

/// A pixel buffer that is only ever read after it is drawn, so it can be shared with the encoder queue.
struct StillFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer

    /// Draws the image onto a black frame at the placement, once. The same buffer is then handed to the
    /// encoder for every video frame.
    init(image: CGImage, frame: OutputFrame) throws(ExportError) {
        let width = frame.size.width
        let height = frame.size.height
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var created: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &created
        ) == kCVReturnSuccess, let buffer = created else { throw .encodingFailed }

        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { throw .encodingFailed }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { throw .encodingFailed }

        // Black underneath: it is the bars, and it is what transparent areas of the image become.
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Whole-pixel edges keep the image's edge against a bar crisp. The placement is measured from the
        // top-left corner and Core Graphics counts from the bottom-left.
        let placement = frame.imagePlacement
        let left = placement.x.rounded()
        let right = (placement.x + placement.width).rounded()
        let top = placement.y.rounded()
        let bottom = (placement.y + placement.height).rounded()
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: left, y: Double(height) - bottom, width: right - left, height: bottom - top))

        // Say how the colours are meant to be read, so players show what was drawn.
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        pixelBuffer = buffer
    }
}
