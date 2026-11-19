import Testing
@testable import Song2VidCore

/// Expected values are worked by hand from the SPEC section 5 rules for Original.
@Suite("Original frame rules")
struct OriginalTests {
    private func original(_ width: Int, _ height: Int, resolution: Resolution = .p1080) throws -> OutputFrame {
        try OutputFrame(
            imageSize: PixelSize(width: width, height: height),
            frameShape: .original, resolution: resolution
        )
    }

    // MARK: Exact size

    @Test func imageWithinTheLimitKeepsItsExactSize() throws {
        let frame = try original(1600, 900)
        #expect(frame.size == PixelSize(width: 1600, height: 900))
        expectPlacement(frame.imagePlacement, x: 0, y: 0, width: 1600, height: 900)
        #expect(!frame.isEnlarged)
    }

    @Test func imageExactlyOnTheLandscapeLimitIsUntouched() throws {
        let frame = try original(3840, 2160)
        #expect(frame.size == PixelSize(width: 3840, height: 2160))
        expectPlacement(frame.imagePlacement, x: 0, y: 0, width: 3840, height: 2160)
    }

    @Test func smallestAcceptedImageKeepsItsSize() throws {
        let frame = try original(16, 16)
        #expect(frame.size == PixelSize(width: 16, height: 16))
    }

    @Test func resolutionDoesNotChangeOriginal() throws {
        #expect(try original(1600, 900, resolution: .p480).size == PixelSize(width: 1600, height: 900))
        #expect(try original(1600, 900, resolution: .p2160).size == PixelSize(width: 1600, height: 900))
    }

    // MARK: Under 1% too big: trim, never scale

    @Test func widthOverByUnderOnePercentIsTrimmedEquallyFromBothEdges() throws {
        // 3860 wide is 0.52% over 3840, so 20 px go: 10 from each edge.
        let frame = try original(3860, 2160)
        #expect(frame.size == PixelSize(width: 3840, height: 2160))
        expectPlacement(frame.imagePlacement, x: -10, y: 0, width: 3860, height: 2160)
    }

    @Test func heightOverByUnderOnePercentIsTrimmedEquallyFromTopAndBottom() throws {
        let frame = try original(3840, 2180)
        #expect(frame.size == PixelSize(width: 3840, height: 2160))
        expectPlacement(frame.imagePlacement, x: 0, y: -10, width: 3840, height: 2180)
    }

    @Test func bothSidesOverByUnderOnePercentAreBothTrimmed() throws {
        // 3860 wide (0.52% over) and 2170 high (0.46% over).
        let frame = try original(3860, 2170)
        #expect(frame.size == PixelSize(width: 3840, height: 2160))
        expectPlacement(frame.imagePlacement, x: -10, y: -5, width: 3860, height: 2170)
    }

    @Test func trimOfAnOddNumberOfPixelsTakesTheExtraPixelFromTheFarEdge() throws {
        // 3843 wide: 3 px over, so 1 from the left and 2 from the right.
        let frame = try original(3843, 2160)
        #expect(frame.size == PixelSize(width: 3840, height: 2160))
        expectPlacement(frame.imagePlacement, x: -1, y: 0, width: 3843, height: 2160)
    }

    @Test func lastWidthThatIsTrimmedRatherThanScaled() throws {
        // 3878 wide is 0.99% over 3840: still under 1% (3840 / 3878 = 0.9902), so 38 px are trimmed.
        let frame = try original(3878, 2160)
        #expect(frame.size == PixelSize(width: 3840, height: 2160))
        expectPlacement(frame.imagePlacement, x: -19, y: 0, width: 3878, height: 2160)
    }

    @Test func portraitImageOverTheLimitByUnderOnePercentIsTrimmed() throws {
        let frame = try original(2160, 3860)
        #expect(frame.size == PixelSize(width: 2160, height: 3840))
        expectPlacement(frame.imagePlacement, x: 0, y: -10, width: 2160, height: 3860)
    }

    // MARK: 1% or more too big: scale, keeping the shape

    @Test func firstWidthThatIsScaledRatherThanTrimmed() throws {
        // 3879 wide: 3840 / 3879 = 0.9899, below 0.99. Scaled to 3840 x floor(2160 x 0.9899) = 2138.
        let frame = try original(3879, 2160)
        #expect(frame.size == PixelSize(width: 3840, height: 2138))
        expectPlacement(frame.imagePlacement, x: 0, y: 0, width: 3840, height: 2138)
    }

    @Test func imageTwiceTheLimitIsHalved() throws {
        let frame = try original(7680, 4320)
        #expect(frame.size == PixelSize(width: 3840, height: 2160))
        expectPlacement(frame.imagePlacement, x: 0, y: 0, width: 3840, height: 2160)
        #expect(!frame.isEnlarged)
    }

    @Test func landscapeImageIsScaledByTheLongSide() throws {
        // 4000 x 2000: s = 3840 / 4000 = 0.96, so 3840 x 1920.
        let frame = try original(4000, 2000)
        #expect(frame.size == PixelSize(width: 3840, height: 1920))
    }

    @Test func squareImageIsLimitedByTheShortSideLimit() throws {
        // 3000 x 3000: s = 2160 / 3000 = 0.72, so 2160 x 2160.
        let frame = try original(3000, 3000)
        #expect(frame.size == PixelSize(width: 2160, height: 2160))
    }

    // MARK: Portrait limit

    @Test func portraitImageUsesThePortraitLimit() throws {
        // 2160 x 3840 is exactly the portrait limit. The landscape limit would have shrunk it.
        let frame = try original(2160, 3840)
        #expect(frame.size == PixelSize(width: 2160, height: 3840))
    }

    @Test func portraitImageOverTheLimitIsScaled() throws {
        // 2000 x 4000: s = 3840 / 4000 = 0.96, so 1920 x 3840.
        let frame = try original(2000, 4000)
        #expect(frame.size == PixelSize(width: 1920, height: 3840))
    }

    @Test func tallPortraitWithinTheLimitIsUntouched() throws {
        let frame = try original(1080, 3800)
        #expect(frame.size == PixelSize(width: 1080, height: 3800))
    }

    // MARK: Even sizes

    @Test func oddWidthAndHeightLoseOnePixelFromTheRightAndBottom() throws {
        let frame = try original(1001, 501)
        #expect(frame.size == PixelSize(width: 1000, height: 500))
        expectPlacement(frame.imagePlacement, x: 0, y: 0, width: 1001, height: 501)
    }

    @Test func oddWidthOnlyLosesOnePixelFromTheRight() throws {
        let frame = try original(1601, 900)
        #expect(frame.size == PixelSize(width: 1600, height: 900))
    }

    @Test func scaledSizeThatComesOutOddLosesOnePixelFromTheRightAndBottom() throws {
        // 3880 x 2160: s = 3840 / 3880, so 3840 x floor(2137.9) = 2137, which is odd, so 2136.
        let frame = try original(3880, 2160)
        #expect(frame.size == PixelSize(width: 3840, height: 2136))
        expectPlacement(frame.imagePlacement, x: 0, y: 0, width: 3840, height: 2137)
    }

    // MARK: Too small

    @Test func imageSmallerThan16By16IsRejected() {
        #expect(throws: FrameError.imageTooSmall) { try original(15, 15) }
    }

    @Test func imageNarrowerThan16IsRejected() {
        #expect(throws: FrameError.imageTooSmall) { try original(15, 2000) }
    }

    @Test func imageShorterThan16IsRejected() {
        #expect(throws: FrameError.imageTooSmall) { try original(2000, 15) }
    }

    @Test func rejectionMessageSaysWhy() {
        #expect(FrameError.imageTooSmall.message == "This image is too small. Original needs an image of at least 16×16 pixels.")
    }
}
