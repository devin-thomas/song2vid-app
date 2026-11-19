import Foundation

/// What a dropped item is, decided from its type before it is read (SPEC section 4a).
public enum DropFileKind: Equatable, Sendable {
    case audio, image, folder, unsupported
}

/// One item from a drop.
public struct DroppedFile: Equatable, Sendable {
    public let url: URL
    public let kind: DropFileKind

    public init(url: URL, kind: DropFileKind) {
        self.url = url
        self.kind = kind
    }
}

/// The song and image the window holds.
public struct DropSlots: Equatable, Sendable {
    public var audio: LoadedAudio?
    public var image: LoadedImage?

    public init(audio: LoadedAudio? = nil, image: LoadedImage? = nil) {
        self.audio = audio
        self.image = image
    }
}

/// The question asked when a drop would replace something (SPEC section 4a).
public struct ReplaceDialog: Equatable, Sendable {
    /// "Replace the current song?", "Replace the current image?" or "Replace the current song and image?"
    public let title: String
    /// What is there now and what was dropped, one line each, with a blank line between a song's pair and an image's pair.
    public let detail: String
    /// The button that uses the dropped file.
    public let replaceButton = "Replace"
    /// The default button, also chosen with Esc.
    public let keepButton = "Keep Current"
    /// The slots if the person answers Replace.
    public let ifReplaced: DropSlots
    /// The slots if the person answers Keep Current: filled empty slots stay filled, nothing else changes.
    public let ifKept: DropSlots
    /// A message to show whichever way the person answers, such as a dropped file that couldn't be read.
    public let notice: String?

    public init(title: String, detail: String, ifReplaced: DropSlots, ifKept: DropSlots, notice: String?) {
        self.title = title
        self.detail = detail
        self.ifReplaced = ifReplaced
        self.ifKept = ifKept
        self.notice = notice
    }
}

/// What the window should do about a drop.
public enum DropOutcome: Equatable, Sendable {
    /// Nothing changes; show this message.
    case rejected(String)
    /// Use these slots now, with an optional message.
    case apply(DropSlots, notice: String?)
    /// Ask first.
    case confirm(ReplaceDialog)
}

/// Decides what a drop does (SPEC section 4a). The window only carries out the outcome.
public struct DropHandler: Sendable {
    private let inspector: any MediaInspecting

    public init(inspector: any MediaInspecting) {
        self.inspector = inspector
    }

    /// The message for a drop that arrives while a video is being made (SPEC section 4a).
    public static let waitMessage = "Wait for the current video to finish."

    /// Why a drop can't be used, judged from the items' types alone. Also decides whether the window highlights.
    public static func rejection(for files: [DroppedFile], isExporting: Bool) -> String? {
        if isExporting { return waitMessage }
        if files.isEmpty { return "Drop a song or an image." }
        if files.contains(where: { $0.kind == .folder }) { return "Song2Vid can't use folders. Drop a song or an image." }
        if files.count > 2 { return "Drop no more than two files: one song, one image, or one of each." }
        if files.contains(where: { $0.kind == .unsupported }) { return "Song2Vid can't read this kind of file. Drop a song or an image." }
        let audioCount = files.filter { $0.kind == .audio }.count
        if audioCount > 1 || files.count - audioCount > 1 { return "Drop one song, one image, or one of each." }
        return nil
    }

    public func handle(_ files: [DroppedFile], slots: DropSlots, isExporting: Bool) async -> DropOutcome {
        if let message = Self.rejection(for: files, isExporting: isExporting) { return .rejected(message) }

        var droppedAudio: LoadedAudio?
        var droppedImage: LoadedImage?
        var problems: [String] = []
        if let file = files.first(where: { $0.kind == .audio }) {
            do { droppedAudio = try await inspector.inspectAudio(at: file.url) } catch { problems.append(MediaError.unreadableAudio.message) }
        }
        if let file = files.first(where: { $0.kind == .image }) {
            do { droppedImage = try await inspector.inspectImage(at: file.url) } catch { problems.append(MediaError.unreadableImage.message) }
        }
        let notice = problems.isEmpty ? nil : problems.joined(separator: " ")
        // Nothing usable arrived, so nothing can change and there is nothing to ask.
        if droppedAudio == nil && droppedImage == nil { return .rejected(notice ?? "Drop a song or an image.") }

        var ifReplaced = slots
        var ifKept = slots
        var questions: [(noun: String, detail: String)] = []
        if let droppedAudio {
            ifReplaced.audio = droppedAudio
            if let current = slots.audio {
                questions.append(("song", "Song now: \(current.summary)\nDropped song: \(droppedAudio.summary)"))
            } else {
                ifKept.audio = droppedAudio
            }
        }
        if let droppedImage {
            ifReplaced.image = droppedImage
            if let current = slots.image {
                questions.append(("image", "Image now: \(current.summary)\nDropped image: \(droppedImage.summary)"))
            } else {
                ifKept.image = droppedImage
            }
        }
        if questions.isEmpty { return .apply(ifReplaced, notice: notice) }
        return .confirm(ReplaceDialog(
            title: "Replace the current \(questions.map(\.noun).joined(separator: " and "))?",
            detail: questions.map(\.detail).joined(separator: "\n\n"),
            ifReplaced: ifReplaced,
            ifKept: ifKept,
            notice: notice
        ))
    }
}

extension LoadedAudio {
    /// "name, m:ss".
    public var summary: String {
        let seconds = Int(duration.rounded())
        return "\(name), \(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

extension LoadedImage {
    /// "name, W×H pixels".
    public var summary: String { "\(name), \(size.width)×\(size.height) pixels" }
}
