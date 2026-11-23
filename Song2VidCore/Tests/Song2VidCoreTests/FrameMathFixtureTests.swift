import Foundation
import Testing
@testable import Song2VidCore

struct FrameMathFixtureTests {
    private struct Size: Encodable {
        let width: Int
        let height: Int

        init(_ size: PixelSize) {
            width = size.width
            height = size.height
        }
    }

    private struct Crop: Encodable {
        let horizontal: Double
        let vertical: Double
    }

    private struct Placement: Encodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ placement: ImagePlacement) {
            x = placement.x
            y = placement.y
            width = placement.width
            height = placement.height
        }
    }

    private struct Result: Encodable {
        let size: Size
        let placement: Placement
        let enlarged: Bool
    }

    private struct Fixture: Encodable {
        let image: Size
        let shape: String
        let resolution: String
        let crop: Crop
        let output: Result?
        let error: String?

        init(width: Int, height: Int, shape: FrameShape, resolution: Resolution, crop: Crop) throws {
            let size = PixelSize(width: width, height: height)
            self.image = Size(size)
            self.shape = shape.commandName
            self.resolution = resolution.commandName
            self.crop = crop
            do {
                let frame = try OutputFrame(
                    imageSize: size, frameShape: shape, resolution: resolution,
                    cropPosition: CropPosition(horizontal: crop.horizontal, vertical: crop.vertical)
                )
                output = Result(size: Size(frame.size), placement: Placement(frame.imagePlacement), enlarged: frame.isEnlarged)
                error = nil
            } catch FrameError.imageTooSmall {
                output = nil
                error = "image_too_small"
            }
        }
    }

    @Test("The shared frame math fixture matches Swift")
    func sharedFrameMathFixture() throws {
        // Three fractions on both axes, including asymmetric pairs to catch a swapped axis.
        let crops = [
            Crop(horizontal: 0.5, vertical: 0.5),
            Crop(horizontal: 0, vertical: 1),
            Crop(horizontal: 1, vertical: 0),
            Crop(horizontal: 0.5, vertical: 0),
            Crop(horizontal: 1, vertical: 0.5),
        ]
        let images = [(853, 479), (517, 913), (480, 480), (640, 480), (854, 480), (4033, 3025), (1179, 2557)]
        // Original's long- and short-edge limits, the odd-pixel rule, and both sides of scale 0.99.
        let originals = [
            (15, 16), (16, 15), (16, 16), (17, 19), (640, 481), (481, 640),
            (3840, 2160), (2160, 3840), (3841, 2161), (2161, 3841),
            (3878, 2160), (3879, 2160), (2160, 3878), (2160, 3879),
            (3840, 2181), (3840, 2182), (2181, 3840), (2182, 3840),
            (2161, 2161), (7681, 4321), (4321, 7681),
        ]

        var fixtures: [Fixture] = []
        for shape in FrameShape.allCases {
            for resolution in Resolution.allCases {
                let positions = shape == .oneByOne || shape == .fourByThree ? crops : [crops[0]]
                for (width, height) in shape == .original ? originals : images {
                    for crop in positions {
                        fixtures.append(try Fixture(width: width, height: height, shape: shape, resolution: resolution, crop: crop))
                    }
                }
            }
        }
        #expect(fixtures.count >= 200)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let rows = try fixtures.map { "  " + String(decoding: try encoder.encode($0), as: UTF8.self) }
        let expected = Data(("[\n" + rows.joined(separator: ",\n") + "\n]\n").utf8)

        let root = (0..<4).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let folder = root.appendingPathComponent("fixtures", isDirectory: true)
        let url = folder.appendingPathComponent("frame-math.json")
        if ProcessInfo.processInfo.environment["SONG2VID_UPDATE_FRAME_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try expected.write(to: url, options: .atomic)
        }
        let actual = try? Data(contentsOf: url)
        #expect(actual == expected, "Run SONG2VID_UPDATE_FRAME_FIXTURES=1 swift test --package-path Song2VidCore --filter FrameMathFixtureTests")
    }
}
