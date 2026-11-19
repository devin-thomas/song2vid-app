import Song2VidCore
import UniformTypeIdentifiers

/// The words the window uses for each choice (GLOSSARY.md).
extension FrameShape {
    var title: String {
        switch self {
        case .sixteenByNine: "16:9"
        case .nineBySixteen: "9:16"
        case .oneByOne: "1:1"
        case .fourByThree: "4:3"
        case .original: "Original"
        }
    }
}

extension Resolution {
    var title: String {
        switch self {
        case .p480: "480p"
        case .p1080: "1080p"
        case .p2160: "2160p"
        }
    }
}

/// The file types the choosers open (SPEC section 7). Drops use the same lists.
enum ChoosableTypes {
    static let audio: [UTType] = SupportedTypes.audio
    static let image: [UTType] = SupportedTypes.image
}
