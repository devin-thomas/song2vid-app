import Foundation
import Testing
@testable import Song2VidCore

@MainActor
@Suite("Main window: Crop")
struct MainWindowCropTests {
    /// A 3000x1000 image in 4:3 at 1080p overflows 1800 px sideways and 0 px vertically.
    private func cropModel(_ width: Int = 3000, _ height: Int = 1000, shape: FrameShape = .fourByThree) async -> MainWindowModel {
        let m = model(images: [picture("wide.jpg", width, height)])
        await m.chooseImage(at: URL(fileURLWithPath: "/media/wide.jpg"))
        m.frameShape = shape
        return m
    }

    @Test func cropCanBeAdjustedOnlyWhenTheImageIsCropped() async {
        let m = await cropModel(shape: .sixteenByNine)
        #expect(m.canAdjustCrop == false)
        m.frameShape = .original
        #expect(m.canAdjustCrop == false)
        m.frameShape = .oneByOne
        #expect(m.canAdjustCrop == true)
        m.frameShape = .fourByThree
        #expect(m.canAdjustCrop == true)
        #expect(model().canAdjustCrop == false)
    }

    @Test func nothingToAdjustWhenTheImageAlreadyFillsTheFrameExactly() async {
        let m = await cropModel(1600, 1200)
        #expect(m.canAdjustCrop == false)
    }

    @Test func draggingTheImageLeftShowsMoreOfItsRightSide() async {
        let m = await cropModel()
        m.dragCrop(from: .center, byFramePixels: -450, 0)
        #expect(m.cropPosition == CropPosition(horizontal: 0.75, vertical: 0.5))
        #expect(m.frame?.imagePlacement.x == -1350)
    }

    @Test func draggingTheImageRightShowsMoreOfItsLeftSide() async {
        let m = await cropModel()
        m.dragCrop(from: .center, byFramePixels: 450, 0)
        #expect(m.cropPosition == CropPosition(horizontal: 0.25, vertical: 0.5))
    }

    @Test func aDragIsMeasuredFromWhereItStarted() async {
        let m = await cropModel()
        let start = CropPosition(horizontal: 0.25, vertical: 0.5)
        m.dragCrop(from: start, byFramePixels: -180, 0)
        m.dragCrop(from: start, byFramePixels: -360, 0)
        #expect(m.cropPosition == CropPosition(horizontal: 0.45, vertical: 0.5))
    }

    @Test func dragCannotPassAnEdgeOnEitherSide() async throws {
        let m = await cropModel()
        m.dragCrop(from: .center, byFramePixels: -50_000, 0)
        #expect(m.cropPosition.horizontal == 1)
        #expect(try #require(m.frame).imagePlacement.x == -1800)
        m.dragCrop(from: .center, byFramePixels: 50_000, 0)
        #expect(m.cropPosition.horizontal == 0)
        #expect(try #require(m.frame).imagePlacement.x == 0)
    }

    @Test func dragCannotMoveTheImageAcrossAnAxisWithNothingToCrop() async {
        let m = await cropModel()
        m.dragCrop(from: .center, byFramePixels: 0, 700)
        #expect(m.cropPosition.vertical == 0.5)
    }

    @Test func tallImageDragsVerticallyOnly() async {
        // 1000x2000 in 1:1 at 1080p is 1080x2160: 1080 px overflow downwards.
        let m = await cropModel(1000, 2000, shape: .oneByOne)
        m.dragCrop(from: .center, byFramePixels: 300, -270)
        #expect(m.cropPosition == CropPosition(horizontal: 0.5, vertical: 0.75))
    }

    @Test func dragDoesNothingWhenNoCropApplies() async {
        let m = await cropModel(shape: .sixteenByNine)
        m.dragCrop(from: .center, byFramePixels: -450, 0)
        #expect(m.cropPosition == .center)
    }

    @Test func cropIsKeptWhenResolutionChanges() async {
        let m = await cropModel()
        m.dragCrop(from: .center, byFramePixels: -450, 0)
        m.resolution = .p480
        #expect(m.cropPosition == CropPosition(horizontal: 0.75, vertical: 0.5))
        m.resolution = .p2160
        #expect(m.cropPosition == CropPosition(horizontal: 0.75, vertical: 0.5))
    }

    @Test func cropResetsWhenTheFrameShapeChanges() async {
        let m = await cropModel()
        m.dragCrop(from: .center, byFramePixels: -450, 0)
        m.frameShape = .oneByOne
        #expect(m.cropPosition == .center)
    }

    @Test func cropStaysWhenTheSameFrameShapeIsPickedAgain() async {
        let m = await cropModel()
        m.dragCrop(from: .center, byFramePixels: -450, 0)
        m.frameShape = .fourByThree
        #expect(m.cropPosition.horizontal == 0.75)
    }

    @Test func cropResetsWhenTheImageChanges() async {
        let m = model(images: [picture("a.jpg", 3000, 1000), picture("b.jpg", 3000, 1000)])
        await m.chooseImage(at: URL(fileURLWithPath: "/media/a.jpg"))
        m.frameShape = .fourByThree
        m.dragCrop(from: .center, byFramePixels: -450, 0)
        await m.chooseImage(at: URL(fileURLWithPath: "/media/b.jpg"))
        #expect(m.cropPosition == .center)
    }

    @Test func cropIsKeptWhenAnImageCantBeRead() async {
        let m = await cropModel()
        m.dragCrop(from: .center, byFramePixels: -450, 0)
        await m.chooseImage(at: URL(fileURLWithPath: "/media/broken.jpg"))
        #expect(m.cropPosition.horizontal == 0.75)
    }

    @Test func resetToCenterRestoresTheStartingPosition() async {
        let m = await cropModel(1000, 2000, shape: .oneByOne)
        m.dragCrop(from: .center, byFramePixels: 200, 400)
        m.resetCropToCenter()
        #expect(m.cropPosition == .center)
    }

    @Test func arrowKeysMoveTheImageInSteps() async {
        let m = await cropModel()
        m.nudgeCrop(.left)
        #expect(m.cropPosition == CropPosition(horizontal: 0.55, vertical: 0.5))
        m.nudgeCrop(.right)
        m.nudgeCrop(.right)
        #expect(m.cropPosition == CropPosition(horizontal: 0.45, vertical: 0.5))
    }

    @Test func aLargeNudgeMovesFurther() async {
        let m = await cropModel()
        m.nudgeCrop(.left, large: true)
        #expect(m.cropPosition == CropPosition(horizontal: 0.75, vertical: 0.5))
    }

    @Test func nudgingCannotPassAnEdge() async {
        let m = await cropModel()
        for _ in 0..<40 { m.nudgeCrop(.left) }
        #expect(m.cropPosition.horizontal == 1)
        for _ in 0..<80 { m.nudgeCrop(.right) }
        #expect(m.cropPosition.horizontal == 0)
    }

    @Test func upAndDownMoveATallImage() async {
        let m = await cropModel(1000, 2000, shape: .oneByOne)
        m.nudgeCrop(.down)
        #expect(m.cropPosition == CropPosition(horizontal: 0.5, vertical: 0.45))
        m.nudgeCrop(.up)
        m.nudgeCrop(.up)
        #expect(m.cropPosition == CropPosition(horizontal: 0.5, vertical: 0.55))
    }

    @Test func nudgingAcrossAnAxisWithNothingToCropDoesNothing() async {
        let m = await cropModel()
        m.nudgeCrop(.up)
        m.nudgeCrop(.down)
        #expect(m.cropPosition == .center)
    }

    @Test func cropDescriptionForVoiceOver() async {
        let m = await cropModel()
        #expect(m.cropDescription == "Crop position: 50% across")
        m.nudgeCrop(.left)
        #expect(m.cropDescription == "Crop position: 55% across")
        let tall = await cropModel(1000, 2000, shape: .oneByOne)
        #expect(tall.cropDescription == "Crop position: 50% down")
    }
}
