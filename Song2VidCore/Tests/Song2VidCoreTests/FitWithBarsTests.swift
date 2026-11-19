import Testing
@testable import Song2VidCore

/// Compares placements with a tiny tolerance for floating-point noise.
func expectPlacement(
    _ actual: ImagePlacement,
    x: Double, y: Double, width: Double, height: Double,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let close: (Double, Double) -> Bool = { abs($0 - $1) < 1e-9 }
    #expect(close(actual.x, x), "x was \(actual.x), expected \(x)", sourceLocation: sourceLocation)
    #expect(close(actual.y, y), "y was \(actual.y), expected \(y)", sourceLocation: sourceLocation)
    #expect(close(actual.width, width), "width was \(actual.width), expected \(width)", sourceLocation: sourceLocation)
    #expect(close(actual.height, height), "height was \(actual.height), expected \(height)", sourceLocation: sourceLocation)
}

/// Expected placements are worked by hand for 1080p frames, where the numbers come out exact.
@Suite("Fit with bars placement")
struct FitWithBarsTests {
    @Test func squareImageIn16By9GetsBarsLeftAndRight() throws {
        let frame = try OutputFrame(imageSize: PixelSize(width: 1000, height: 1000), frameShape: .sixteenByNine, resolution: .p1080)
        expectPlacement(frame.imagePlacement, x: 420, y: 0, width: 1080, height: 1080)
    }

    @Test func wideImageIn16By9GetsBarsTopAndBottom() throws {
        let frame = try OutputFrame(imageSize: PixelSize(width: 3000, height: 1000), frameShape: .sixteenByNine, resolution: .p1080)
        expectPlacement(frame.imagePlacement, x: 0, y: 220, width: 1920, height: 640)
    }

    @Test func imageWithTheFrameShapeFillsTheFrameExactly() throws {
        let frame = try OutputFrame(imageSize: PixelSize(width: 1920, height: 1080), frameShape: .sixteenByNine, resolution: .p1080)
        expectPlacement(frame.imagePlacement, x: 0, y: 0, width: 1920, height: 1080)
        #expect(!frame.isEnlarged)
    }

    @Test func squareImageIn9By16GetsBarsTopAndBottom() throws {
        let frame = try OutputFrame(imageSize: PixelSize(width: 1000, height: 1000), frameShape: .nineBySixteen, resolution: .p1080)
        expectPlacement(frame.imagePlacement, x: 0, y: 420, width: 1080, height: 1080)
    }

    @Test func tallImageIn9By16GetsBarsLeftAndRight() throws {
        let frame = try OutputFrame(imageSize: PixelSize(width: 500, height: 1000), frameShape: .nineBySixteen, resolution: .p1080)
        expectPlacement(frame.imagePlacement, x: 60, y: 0, width: 960, height: 1920)
    }

    @Test func smallImageIsEnlargedToFit() throws {
        let frame = try OutputFrame(imageSize: PixelSize(width: 1000, height: 1000), frameShape: .sixteenByNine, resolution: .p1080)
        #expect(frame.isEnlarged)
    }

    @Test func largeImageIsShrunkNotEnlarged() throws {
        let frame = try OutputFrame(imageSize: PixelSize(width: 3000, height: 1000), frameShape: .sixteenByNine, resolution: .p1080)
        #expect(!frame.isEnlarged)
    }
}
