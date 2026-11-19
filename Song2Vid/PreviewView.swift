import Song2VidCore
import SwiftUI

/// The output frame drawn to scale, with the image placed exactly as the model says it will be in the video.
struct PreviewView: View {
    var model: MainWindowModel

    /// Where the Crop was when the current drag began.
    @State private var dragStart: CropPosition?
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let frameSize = model.previewFrameSize
            let scale = min(
                proxy.size.width / CGFloat(frameSize.width),
                proxy.size.height / CGFloat(frameSize.height)
            )
            let width = CGFloat(frameSize.width) * scale
            let height = CGFloat(frameSize.height) * scale

            frameView(width: width, height: height, scale: scale)
                .frame(width: width, height: height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    @ViewBuilder
    private func frameView(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        let canCrop = model.canAdjustCrop
        ZStack(alignment: .topLeading) {
            if let frame = model.frame {
                Color.black
                if let preview = model.previewImage {
                    let placement = frame.imagePlacement
                    Image(decorative: preview.cgImage, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: placement.width * scale, height: placement.height * scale)
                        .offset(x: placement.x * scale, y: placement.y * scale)
                }
            } else {
                Rectangle().fill(.quaternary)
                Text(model.frameProblem ?? model.previewPrompt ?? "")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .overlay(
            Rectangle().strokeBorder(canCrop && isFocused ? Color.accentColor : Color.primary.opacity(0.25),
                                     lineWidth: canCrop && isFocused ? 3 : 1)
        )
        .contentShape(Rectangle())
        .gesture(dragGesture(scale: scale), isEnabled: canCrop)
        .focusable(canCrop)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            guard canCrop else { return .ignored }
            let direction: CropNudge = switch press.key {
            case .leftArrow: .left
            case .rightArrow: .right
            case .upArrow: .up
            default: .down
            }
            model.nudgeCrop(direction, large: press.modifiers.contains(.shift))
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the video frame")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(canCrop ? "Use the arrow keys to move the image. Hold Shift for bigger steps." : "")
        .accessibilityAction(named: "Move image left") { model.nudgeCrop(.left) }
        .accessibilityAction(named: "Move image right") { model.nudgeCrop(.right) }
        .accessibilityAction(named: "Move image up") { model.nudgeCrop(.up) }
        .accessibilityAction(named: "Move image down") { model.nudgeCrop(.down) }
        .accessibilityAction(named: "Reset to Center") { model.resetCropToCenter() }
    }

    private var accessibilityValue: String {
        guard let frame = model.frame else { return model.frameProblem ?? model.previewPrompt ?? "" }
        let size = "\(frame.size.width) by \(frame.size.height) pixels"
        return model.canAdjustCrop ? "\(size). \(model.cropDescription)" : size
    }

    private func dragGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? model.cropPosition
                dragStart = start
                isFocused = true
                model.dragCrop(
                    from: start,
                    byFramePixels: Double(value.translation.width / scale),
                    Double(value.translation.height / scale)
                )
            }
            .onEnded { _ in dragStart = nil }
    }
}
