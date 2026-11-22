import Foundation

// The words the command uses for each choice (GLOSSARY.md and SPEC section 14.2). `make` will read the same
// names from the command line, so they live in one place.

extension FrameShape {
    /// The name on the command line and in JSON: `16:9`, `9:16`, `1:1`, `4:3` or `original`.
    var commandName: String {
        switch self {
        case .sixteenByNine: "16:9"
        case .nineBySixteen: "9:16"
        case .oneByOne: "1:1"
        case .fourByThree: "4:3"
        case .original: "original"
        }
    }
}

extension Resolution {
    /// The name on the command line and in JSON: `480p`, `1080p` or `2160p`.
    var commandName: String { "\(shortSide)p" }
}

/// How the image sits in the frame (SPEC section 5).
enum PlacementKind: String, Sendable {
    /// The whole image is shown. 16:9 and 9:16 add black bars.
    case fit
    /// The image fills the frame and the parts outside it are discarded.
    case crop

    /// The placement of a frame. 16:9 and 9:16 are Fit with bars and 1:1 and 4:3 are Crop. Original is Fit when the
    /// whole image is kept, and Crop when the image was a little over the limit and its edges were trimmed.
    init(shape: FrameShape, frame: OutputFrame) {
        switch shape {
        case .sixteenByNine, .nineBySixteen: self = .fit
        case .oneByOne, .fourByThree: self = .crop
        case .original: self = frame.imagePlacement.x < 0 || frame.imagePlacement.y < 0 ? .crop : .fit
        }
    }

    /// The glossary's word for it, for people reading the text output.
    func title(for shape: FrameShape) -> String {
        switch (self, shape) {
        case (.fit, .original): "Whole image"
        case (.crop, .original): "Crop (edges trimmed)"
        case (.fit, _): "Fit with bars"
        case (.crop, _): "Crop"
        }
    }
}
