import Foundation
import Observation

/// An arrow key used to move the Crop.
public enum CropNudge: Sendable {
    case left, right, up, down
}

/// Everything the main window shows and changes (SPEC section 4), kept free of any view code so it can be tested.
@MainActor
@Observable
public final class MainWindowModel {
    public private(set) var audio: LoadedAudio?
    public private(set) var image: LoadedImage?
    /// The image drawn in the preview; nil when there is no image or none could be decoded.
    public private(set) var previewImage: PreviewImage?
    /// A short message about the last choice that didn't work; cleared by the next one that does.
    public private(set) var notice: String?

    /// Changing the Frame Shape moves the Crop back to the center.
    public var frameShape: FrameShape = .sixteenByNine {
        didSet { if frameShape != oldValue { cropPosition = .center } }
    }

    /// Changing the Resolution keeps the Crop where it is.
    public var resolution: Resolution = .p1080

    public private(set) var cropPosition: CropPosition = .center

    @ObservationIgnored private let inspector: any MediaInspecting
    /// Files stay readable (sandbox access) for as long as they are the current choice, so the export can read them.
    @ObservationIgnored private var heldAudioAccess: URL?
    @ObservationIgnored private var heldImageAccess: URL?

    public init(inspector: any MediaInspecting = SystemMediaInspector()) {
        self.inspector = inspector
    }

    // MARK: Choosing files

    /// Reads the song at `url` and makes it the current one. If it can't be read, the current one stays.
    public func chooseAudio(at url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        do {
            audio = try await inspector.inspectAudio(at: url)
            notice = nil
            Self.swapAccess(&heldAudioAccess, to: access ? url : nil)
        } catch {
            if access { url.stopAccessingSecurityScopedResource() }
            notice = MediaError.unreadableAudio.message
        }
    }

    /// Reads the image at `url` and makes it the current one. If it can't be read, the current one stays.
    /// A new image puts the Crop back at the center.
    public func chooseImage(at url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        do {
            let loaded = try await inspector.inspectImage(at: url)
            let preview = await inspector.previewImage(at: url)
            image = loaded
            previewImage = preview
            cropPosition = .center
            notice = nil
            Self.swapAccess(&heldImageAccess, to: access ? url : nil)
        } catch {
            if access { url.stopAccessingSecurityScopedResource() }
            notice = MediaError.unreadableImage.message
        }
    }

    private static func swapAccess(_ held: inout URL?, to new: URL?) {
        held?.stopAccessingSecurityScopedResource()
        held = new
    }

    // MARK: What the window shows

    /// "name, m:ss" once a song is chosen.
    public var audioSummary: String? {
        guard let audio else { return nil }
        let seconds = Int(audio.duration.rounded())
        return "\(audio.name), \(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    /// "name, W×H pixels" once an image is chosen.
    public var imageSummary: String? {
        guard let image else { return nil }
        return "\(image.name), \(image.size.width)×\(image.size.height) pixels"
    }

    /// The output frame and image placement for the current choices; nil without an image or when the frame can't be made.
    public var frame: OutputFrame? {
        guard let image else { return nil }
        return try? OutputFrame(imageSize: image.size, frameShape: frameShape, resolution: resolution, cropPosition: cropPosition)
    }

    /// Why no frame can be made, when that's the reason.
    public var frameProblem: String? {
        guard let image else { return nil }
        do {
            _ = try OutputFrame(imageSize: image.size, frameShape: frameShape, resolution: resolution)
            return nil
        } catch let error as FrameError {
            return error.message
        } catch {
            return nil
        }
    }

    /// The size of the frame to draw in the preview. With no image yet, it's the chosen Frame Shape's size (16:9 for Original).
    public var previewFrameSize: PixelSize {
        if let frame { return frame.size }
        let shape: FrameShape = frameShape == .original ? .sixteenByNine : frameShape
        let standIn = PixelSize(width: 16, height: 9)
        let size = (try? OutputFrame(imageSize: standIn, frameShape: shape, resolution: resolution))?.size
        return size ?? PixelSize(width: 1920, height: 1080)
    }

    /// "Choose an image" until there is one.
    public var previewPrompt: String? {
        image == nil ? "Choose an image" : nil
    }

    public var showsResolutionPicker: Bool { frameShape != .original }

    /// "Output: W×H", shown instead of the Resolution picker for Original.
    public var outputSizeLabel: String? {
        guard frameShape == .original, let frame else { return nil }
        return "Output: \(frame.size.width)×\(frame.size.height)"
    }

    /// Shown when the image would be scaled up.
    public var enlargeNote: String? {
        guard let frame, frame.isEnlarged else { return nil }
        return "This image is smaller than \(frame.size.width)×\(frame.size.height) and will be enlarged, so it may look soft."
    }

    /// Make Video is available only when both files are loaded and a frame can be made.
    public var canMakeVideo: Bool {
        audio != nil && frame != nil
    }

    // MARK: Crop

    /// How far the image runs past the frame on each axis, in frame pixels. Zero on both unless the Frame Shape crops.
    private var cropOverflow: (horizontal: Double, vertical: Double) {
        guard frameShape == .oneByOne || frameShape == .fourByThree, let frame else { return (0, 0) }
        return (
            max(0, frame.imagePlacement.width - Double(frame.size.width)),
            max(0, frame.imagePlacement.height - Double(frame.size.height))
        )
    }

    /// True when dragging or the arrow keys can change what part of the image is kept.
    public var canAdjustCrop: Bool {
        let overflow = cropOverflow
        return overflow.horizontal > 0 || overflow.vertical > 0
    }

    /// Moves the image by (`dx`, `dy`) frame pixels from where `start` had it, as a drag does.
    /// The image can't be dragged past an edge, and doesn't move on an axis where it has nothing to crop.
    public func dragCrop(from start: CropPosition, byFramePixels dx: Double, _ dy: Double) {
        let overflow = cropOverflow
        // Dragging the image right shows more of its left side, so the position falls.
        cropPosition = CropPosition(
            horizontal: overflow.horizontal > 0 ? Self.tidy(start.horizontal - dx / overflow.horizontal) : cropPosition.horizontal,
            vertical: overflow.vertical > 0 ? Self.tidy(start.vertical - dy / overflow.vertical) : cropPosition.vertical
        )
    }

    /// An arrow-key press: the image moves one step in that direction.
    public func nudgeCrop(_ direction: CropNudge, large: Bool = false) {
        let step = large ? 0.25 : 0.05
        let overflow = cropOverflow
        var horizontal = cropPosition.horizontal
        var vertical = cropPosition.vertical
        switch direction {
        case .left where overflow.horizontal > 0: horizontal += step
        case .right where overflow.horizontal > 0: horizontal -= step
        case .up where overflow.vertical > 0: vertical += step
        case .down where overflow.vertical > 0: vertical -= step
        default: return
        }
        cropPosition = CropPosition(horizontal: Self.tidy(horizontal), vertical: Self.tidy(vertical))
    }

    /// "Reset to Center".
    public func resetCropToCenter() {
        cropPosition = .center
    }

    /// For VoiceOver: where the Crop sits along the axis that can move.
    public var cropDescription: String {
        let overflow = cropOverflow
        if overflow.vertical > 0 && overflow.horizontal == 0 {
            return "Crop position: \(Int((cropPosition.vertical * 100).rounded()))% down"
        }
        return "Crop position: \(Int((cropPosition.horizontal * 100).rounded()))% across"
    }

    /// Rounds away floating-point dust so repeated steps land on tidy values.
    private static func tidy(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }
}
