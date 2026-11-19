/// A size in whole pixels.
public struct PixelSize: Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// The proportions of the output video (SPEC section 5).
public enum FrameShape: Equatable, Hashable, Sendable, CaseIterable {
    case sixteenByNine
    case nineBySixteen
    case oneByOne
    case fourByThree
    case original
}

/// The size tier of the output video, named by the pixel count of the frame's short side.
public enum Resolution: Equatable, Hashable, Sendable, CaseIterable {
    case p480
    case p1080
    case p2160

    /// The frame's short side in pixels.
    public var shortSide: Int {
        switch self {
        case .p480: 480
        case .p1080: 1080
        case .p2160: 2160
        }
    }
}

/// Which part of the image a Crop keeps, independent of Resolution.
/// Each value runs from 0 (the image's left or top edge is against the frame's) to 1 (the right or bottom
/// edge is), and 0.5 is centred. Values past an edge are held at the edge, so the image can't be dragged
/// past it. On an axis where the image has nothing to crop, the value makes no difference.
public struct CropPosition: Equatable, Sendable {
    public let horizontal: Double
    public let vertical: Double

    /// The starting position, also what "Reset to Center" restores.
    public static let center = CropPosition(horizontal: 0.5, vertical: 0.5)

    public init(horizontal: Double, vertical: Double) {
        self.horizontal = Self.limited(horizontal)
        self.vertical = Self.limited(vertical)
    }

    private static func limited(_ value: Double) -> Double {
        value.isNaN ? 0.5 : min(1, max(0, value))
    }
}

/// Where the image is drawn, in frame pixels measured from the frame's top-left corner.
/// The frame clips anything that falls outside it.
public struct ImagePlacement: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Why a frame can't be made.
public enum FrameError: Error, Equatable, Sendable {
    /// Original needs an image of at least 16×16 pixels.
    case imageTooSmall

    /// The text to show the person.
    public var message: String {
        switch self {
        case .imageTooSmall:
            "This image is too small. Original needs an image of at least 16×16 pixels."
        }
    }
}

/// The exact output size and image placement for an image, Frame Shape and Resolution.
///
/// `imageSize` is the image's size after applying its orientation tag.
public struct OutputFrame: Equatable, Sendable {
    public let size: PixelSize
    public let imagePlacement: ImagePlacement
    /// True when the image is drawn larger than its own pixel size (the "enlarge note").
    public let isEnlarged: Bool

    public init(
        imageSize: PixelSize,
        frameShape: FrameShape,
        resolution: Resolution,
        cropPosition: CropPosition = .center
    ) throws {
        let p = resolution.shortSide
        switch frameShape {
        case .sixteenByNine:
            self = Self.fitWithBars(imageSize, in: PixelSize(width: Self.evenCeil(p * 16, dividedBy: 9), height: p))
        case .nineBySixteen:
            self = Self.fitWithBars(imageSize, in: PixelSize(width: p, height: Self.evenCeil(p * 16, dividedBy: 9)))
        case .oneByOne:
            self = Self.crop(imageSize, in: PixelSize(width: p, height: p), at: cropPosition)
        case .fourByThree:
            self = Self.crop(imageSize, in: PixelSize(width: p * 4 / 3, height: p), at: cropPosition)
        case .original:
            self = try Self.original(imageSize)
        }
    }

    private init(size: PixelSize, imagePlacement: ImagePlacement, isEnlarged: Bool) {
        self.size = size
        self.imagePlacement = imagePlacement
        self.isEnlarged = isEnlarged
    }

    /// The whole image, scaled to fit and centred; black bars fill the rest.
    private static func fitWithBars(_ image: PixelSize, in frame: PixelSize) -> OutputFrame {
        let scale = min(Double(frame.width) / Double(image.width), Double(frame.height) / Double(image.height))
        let width = Double(image.width) * scale
        let height = Double(image.height) * scale
        let placement = ImagePlacement(
            x: (Double(frame.width) - width) / 2,
            y: (Double(frame.height) - height) / 2,
            width: width,
            height: height
        )
        return OutputFrame(size: frame, imagePlacement: placement, isEnlarged: scale > 1)
    }

    /// The image scaled to fill the frame, with the part outside the frame discarded.
    private static func crop(_ image: PixelSize, in frame: PixelSize, at position: CropPosition) -> OutputFrame {
        let scale = max(Double(frame.width) / Double(image.width), Double(frame.height) / Double(image.height))
        let width = Double(image.width) * scale
        let height = Double(image.height) * scale
        let placement = ImagePlacement(
            x: -(width - Double(frame.width)) * position.horizontal,
            y: -(height - Double(frame.height)) * position.vertical,
            width: width,
            height: height
        )
        return OutputFrame(size: frame, imagePlacement: placement, isEnlarged: scale > 1)
    }

    /// The image's own size, limited to 3840×2160 (2160×3840 for portrait) and made even (SPEC section 5).
    /// All arithmetic is in whole numbers so that boundaries such as exactly 0.99 can't drift.
    private static func original(_ image: PixelSize) throws -> OutputFrame {
        guard image.width >= 16, image.height >= 16 else { throw FrameError.imageTooSmall }

        let isPortrait = image.height > image.width
        let limit = isPortrait ? PixelSize(width: 2160, height: 3840) : PixelSize(width: 3840, height: 2160)

        // s = min(1, limit.width / width, limit.height / height), kept as the fraction num/den.
        var num = 1
        var den = 1
        if limit.width * den < image.width * num { num = limit.width; den = image.width }
        if limit.height * den < image.height * num { num = limit.height; den = image.height }

        var frame: PixelSize
        var placement: ImagePlacement
        if num == den {
            frame = image
            placement = ImagePlacement(x: 0, y: 0, width: Double(image.width), height: Double(image.height))
        } else if num * 100 >= den * 99 {
            // Under 1% too big: trim the excess equally from both edges, the odd pixel from the far edge.
            frame = PixelSize(width: min(image.width, limit.width), height: min(image.height, limit.height))
            placement = ImagePlacement(
                x: -Double((image.width - frame.width) / 2),
                y: -Double((image.height - frame.height) / 2),
                width: Double(image.width),
                height: Double(image.height)
            )
        } else {
            let scaled = PixelSize(width: image.width * num / den, height: image.height * num / den)
            frame = scaled
            placement = ImagePlacement(x: 0, y: 0, width: Double(scaled.width), height: Double(scaled.height))
        }

        // An odd width or height loses one pixel from the right or bottom edge.
        frame.width -= frame.width % 2
        frame.height -= frame.height % 2
        return OutputFrame(size: frame, imagePlacement: placement, isEnlarged: false)
    }

    /// `numerator / denominator` rounded up to the next even whole number.
    private static func evenCeil(_ numerator: Int, dividedBy denominator: Int) -> Int {
        let ceiling = (numerator + denominator - 1) / denominator
        return ceiling + ceiling % 2
    }
}
