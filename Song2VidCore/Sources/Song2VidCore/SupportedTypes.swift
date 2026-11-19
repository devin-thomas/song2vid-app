import Foundation
import UniformTypeIdentifiers

/// The file types Song2Vid opens (SPEC section 7). The pickers and the drop target use the same lists.
public enum SupportedTypes {
    public static let audio: [UTType] = [.mp3, .mpeg4Audio, .wav, .aiff]
        + ["flac", "caf"].compactMap { UTType(filenameExtension: $0) }

    public static let image: [UTType] = [.jpeg, .png, .heic, .tiff, .webP, .gif, .bmp]
}

extension DropFileKind {
    /// Sorts a dropped item by what it is, without reading its contents.
    public static func of(_ url: URL) -> DropFileKind {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return .folder }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .unsupported }
        if SupportedTypes.audio.contains(where: { type.conforms(to: $0) }) { return .audio }
        if SupportedTypes.image.contains(where: { type.conforms(to: $0) }) { return .image }
        return .unsupported
    }
}
