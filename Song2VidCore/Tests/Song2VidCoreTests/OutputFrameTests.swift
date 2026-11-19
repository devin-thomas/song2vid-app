import Testing
@testable import Song2VidCore

/// Expected values come from the SPEC section 5 table and hand-worked examples, not from the formula.
@Suite("Output frame size table")
struct OutputFrameTableTests {
    struct Cell: Sendable, CustomTestStringConvertible {
        let frameShape: FrameShape
        let resolution: Resolution
        let width: Int
        let height: Int
        var testDescription: String { "\(frameShape) \(resolution) -> \(width)x\(height)" }
    }

    static let cells: [Cell] = [
        Cell(frameShape: .sixteenByNine, resolution: .p480, width: 854, height: 480),
        Cell(frameShape: .sixteenByNine, resolution: .p1080, width: 1920, height: 1080),
        Cell(frameShape: .sixteenByNine, resolution: .p2160, width: 3840, height: 2160),
        Cell(frameShape: .nineBySixteen, resolution: .p480, width: 480, height: 854),
        Cell(frameShape: .nineBySixteen, resolution: .p1080, width: 1080, height: 1920),
        Cell(frameShape: .nineBySixteen, resolution: .p2160, width: 2160, height: 3840),
        Cell(frameShape: .oneByOne, resolution: .p480, width: 480, height: 480),
        Cell(frameShape: .oneByOne, resolution: .p1080, width: 1080, height: 1080),
        Cell(frameShape: .oneByOne, resolution: .p2160, width: 2160, height: 2160),
        Cell(frameShape: .fourByThree, resolution: .p480, width: 640, height: 480),
        Cell(frameShape: .fourByThree, resolution: .p1080, width: 1440, height: 1080),
        Cell(frameShape: .fourByThree, resolution: .p2160, width: 2880, height: 2160),
    ]

    @Test(arguments: cells)
    func frameSizeMatchesTable(cell: Cell) throws {
        let frame = try OutputFrame(
            imageSize: PixelSize(width: 1000, height: 1000),
            frameShape: cell.frameShape,
            resolution: cell.resolution
        )
        #expect(frame.size == PixelSize(width: cell.width, height: cell.height))
    }
}
