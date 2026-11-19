import Foundation

/// Everything needed to make one video: the files, where the image goes, and where to save.
public struct ExportRequest: Sendable {
    public var audioURL: URL
    public var imageURL: URL
    /// The frame size and image placement from `OutputFrame`.
    public var frame: OutputFrame
    /// Where the MP4 goes. An existing file there is replaced, but only once the new video is complete.
    public var destinationURL: URL

    public init(audioURL: URL, imageURL: URL, frame: OutputFrame, destinationURL: URL) {
        self.audioURL = audioURL
        self.imageURL = imageURL
        self.frame = frame
        self.destinationURL = destinationURL
    }
}

/// How an export ended. A cancelled export is not an error: the person asked for it.
public enum ExportOutcome: Equatable, Sendable {
    /// The MP4 is complete at this URL.
    case completed(URL)
    /// The person cancelled. No file was left behind.
    case cancelled
    /// The export failed. No file was left behind, and any file already at the destination is untouched.
    case failed(ExportError)
}

/// Why a video can't be made (SPEC sections 6.5 and 7).
public enum ExportError: Error, Equatable, Sendable {
    /// The audio file is unreadable, isn't audio, or has no audio track (SPEC section 7).
    case unreadableAudio
    /// The image file is unreadable or isn't an image (SPEC section 7).
    case unreadableImage
    /// The audio was readable when chosen but reading it failed partway through.
    case audioReadFailed
    /// The destination folder or file can't be written.
    case cannotSaveToFolder
    /// The disk filled up while writing.
    case diskFull
    /// The video encoder or writer failed for another reason.
    case encodingFailed

    /// The text to show the person.
    public var message: String {
        switch self {
        case .unreadableAudio: "Song2Vid can't read this audio file."
        case .unreadableImage: "Song2Vid can't read this image file."
        case .audioReadFailed: "Couldn't read the audio file"
        case .cannotSaveToFolder: "Couldn't save to that folder"
        case .diskFull: "Not enough disk space"
        case .encodingFailed: "Couldn't make the video"
        }
    }
}

/// What the app needs to show about a chosen audio file.
public struct AudioInfo: Equatable, Sendable {
    /// The length of the decoded audio in seconds. Counted from the file's packets, so it is exact even for
    /// MP3s whose header only estimates the length.
    public let duration: Double
    public let sampleRate: Double
    public let channelCount: Int
}

/// What the app needs to show about a chosen image.
public struct ImageInfo: Equatable, Sendable {
    /// The pixel size after applying the image's orientation tag.
    public let size: PixelSize
}
