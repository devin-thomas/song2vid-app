import Testing
@testable import Song2VidCore

/// Expected placements are worked by hand from the SPEC: the Crop fills the frame, and the crop position
/// (0 = start edge, 1 = end edge, 0.5 = centre on each axis) picks which part of the image is kept.
@Suite("Crop placement and limits")
struct CropTests {
    private func frame(
        _ width: Int, _ height: Int,
        shape: FrameShape, resolution: Resolution = .p1080,
        position: CropPosition = .center
    ) throws -> OutputFrame {
        try OutputFrame(
            imageSize: PixelSize(width: width, height: height),
            frameShape: shape, resolution: resolution, cropPosition: position
        )
    }

    @Test func startingPositionIsTheCentre() {
        #expect(CropPosition.center == CropPosition(horizontal: 0.5, vertical: 0.5))
    }

    @Test func wideImageIn4By3KeepsTheMiddleAtCentre() throws {
        // 3000x1000 scales by 1.08 to 3240x1080; 1800 px overflow sideways, half of it each side.
        let result = try frame(3000, 1000, shape: .fourByThree)
        expectPlacement(result.imagePlacement, x: -900, y: 0, width: 3240, height: 1080)
    }

    @Test func wideImageCanBeMovedToTheLeftEdge() throws {
        let result = try frame(3000, 1000, shape: .fourByThree, position: CropPosition(horizontal: 0, vertical: 0.5))
        expectPlacement(result.imagePlacement, x: 0, y: 0, width: 3240, height: 1080)
    }

    @Test func wideImageCanBeMovedToTheRightEdge() throws {
        let result = try frame(3000, 1000, shape: .fourByThree, position: CropPosition(horizontal: 1, vertical: 0.5))
        expectPlacement(result.imagePlacement, x: -1800, y: 0, width: 3240, height: 1080)
    }

    @Test func wideImageQuarterWayAcross() throws {
        let result = try frame(3000, 1000, shape: .fourByThree, position: CropPosition(horizontal: 0.25, vertical: 0.5))
        expectPlacement(result.imagePlacement, x: -450, y: 0, width: 3240, height: 1080)
    }

    @Test func tallImageIn1By1MovesVertically() throws {
        // 1000x2000 scales by 0.48 to 480x960 in a 480x480 frame; 480 px overflow downwards.
        let top = try frame(1000, 2000, shape: .oneByOne, resolution: .p480, position: CropPosition(horizontal: 0.5, vertical: 0))
        let threeQuarters = try frame(1000, 2000, shape: .oneByOne, resolution: .p480, position: CropPosition(horizontal: 0.5, vertical: 0.75))
        let bottom = try frame(1000, 2000, shape: .oneByOne, resolution: .p480, position: CropPosition(horizontal: 0.5, vertical: 1))
        expectPlacement(top.imagePlacement, x: 0, y: 0, width: 480, height: 960)
        expectPlacement(threeQuarters.imagePlacement, x: 0, y: -360, width: 480, height: 960)
        expectPlacement(bottom.imagePlacement, x: 0, y: -480, width: 480, height: 960)
    }

    @Test func positionAcrossAnAxisWithNothingToCropHasNoEffect() throws {
        // The 3000x1000 image fits the 4:3 frame's height exactly, so vertical position cannot matter.
        let top = try frame(3000, 1000, shape: .fourByThree, position: CropPosition(horizontal: 0.5, vertical: 0))
        let bottom = try frame(3000, 1000, shape: .fourByThree, position: CropPosition(horizontal: 0.5, vertical: 1))
        #expect(top.imagePlacement == bottom.imagePlacement)
    }

    @Test func positionCannotBeDraggedPastAnEdge() {
        let past = CropPosition(horizontal: -0.3, vertical: 1.7)
        #expect(past == CropPosition(horizontal: 0, vertical: 1))
    }

    @Test func nonNumericPositionFallsBackToCentre() {
        let broken = CropPosition(horizontal: .nan, vertical: .infinity)
        #expect(broken == CropPosition(horizontal: 0.5, vertical: 1))
    }

    @Test func samePositionKeepsTheSamePartWhenResolutionChanges() throws {
        // At 480p the 3000x1000 image scales by 0.48 to 1440x480 in a 640x480 frame: 800 px overflow.
        let low = try frame(3000, 1000, shape: .fourByThree, resolution: .p480, position: CropPosition(horizontal: 0.25, vertical: 0.5))
        expectPlacement(low.imagePlacement, x: -200, y: 0, width: 1440, height: 480)
        // At 1080p the same position gives x = -450 of 1800 (also a quarter of the overflow).
        let high = try frame(3000, 1000, shape: .fourByThree, resolution: .p1080, position: CropPosition(horizontal: 0.25, vertical: 0.5))
        expectPlacement(high.imagePlacement, x: -450, y: 0, width: 3240, height: 1080)
    }

    @Test func imageIsEnlargedWhenItIsSmallerThanTheFrame() throws {
        #expect(try frame(1000, 1000, shape: .oneByOne).isEnlarged)
        #expect(try frame(1000, 800, shape: .fourByThree).isEnlarged)
    }

    @Test func imageIsNotEnlargedWhenItAlreadyCoversTheFrame() throws {
        #expect(try !frame(1080, 1080, shape: .oneByOne).isEnlarged)
        #expect(try !frame(3000, 1000, shape: .fourByThree, resolution: .p480).isEnlarged)
    }
}
