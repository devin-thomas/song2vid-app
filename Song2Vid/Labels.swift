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

/// The file types the choosers open (SPEC section 7).
enum ChoosableTypes {
    static let audio: [UTType] = [.mp3, .mpeg4Audio, .wav, .aiff]
        + ["flac", "caf"].compactMap { UTType(filenameExtension: $0) }

    static let image: [UTType] = [.jpeg, .png, .heic, .tiff, .webP, .gif, .bmp]
}
