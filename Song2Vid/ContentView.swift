import AppKit
import Song2VidCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = MainWindowModel()
    @State private var picking: FileKind?
    @State private var dropHighlighted = false

    private enum FileKind {
        case audio, image

        var types: [UTType] {
            switch self {
            case .audio: ChoosableTypes.audio
            case .image: ChoosableTypes.image
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            controls

            PreviewView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 4)

            messages
            footer
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 540)
        .fileImporter(
            isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
            allowedContentTypes: picking?.types ?? []
        ) { result in
            guard case .success(let url) = result, let kind = picking else { return }
            Task {
                switch kind {
                case .audio: await model.chooseAudio(at: url)
                case .image: await model.chooseImage(at: url)
                }
            }
        }
        .overlay { if dropHighlighted { DropHighlight() } }
        .onDrop(of: [.fileURL], delegate: WindowDropDelegate(model: model, highlighted: $dropHighlighted))
        .onChange(of: model.pendingReplacement) { _, dialog in
            guard let dialog else { return }
            ReplaceAlert.present(dialog) { replace in
                Task { await model.answerReplacement(replace: replace) }
            }
        }
        #if DEBUG
        .task { await DebugLaunch.apply(to: model) }
        #endif
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Song2Vid")
                    .font(.title2.weight(.semibold))
                Text("Turn a song and an image into a video.")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Button("Choose Audio…") { picking = .audio }
                    .keyboardShortcut("o", modifiers: .command)
                    .accessibilityLabel("Choose Audio")
                    .accessibilityHint("Opens a file chooser for a song")
                fileSummary(model.audioSummary, empty: "No audio chosen")
            }
            GridRow {
                Button("Choose Image…") { picking = .image }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .accessibilityLabel("Choose Image")
                    .accessibilityHint("Opens a file chooser for a picture")
                fileSummary(model.imageSummary, empty: "No image chosen")
            }
            GridRow {
                Text("Frame Shape")
                    .gridColumnAlignment(.leading)
                Picker("Frame Shape", selection: $model.frameShape) {
                    ForEach(FrameShape.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            GridRow {
                Text("Resolution")
                if model.showsResolutionPicker {
                    Picker("Resolution", selection: $model.resolution) {
                        ForEach(Resolution.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                } else if let label = model.outputSizeLabel {
                    Text(label)
                        .monospacedDigit()
                } else {
                    Text("Output size follows the image")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func fileSummary(_ summary: String?, empty: String) -> some View {
        Text(summary ?? empty)
            .foregroundStyle(summary == nil ? .secondary : .primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var messages: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let note = model.enlargeNote {
                Label(note, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            if let notice = model.notice {
                Label(notice, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack {
            Button("Reset to Center") { model.resetCropToCenter() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!model.canAdjustCrop)
                .accessibilityHint("Puts the image back in the middle of the Crop")
            if model.canAdjustCrop {
                Text("Drag the preview or use the arrow keys to move the image.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Make Video") { makeVideo() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(!model.canMakeVideo)
        }
    }

    /// Placeholder: S2V-005 replaces this with the save dialog and the export.
    private func makeVideo() {}
}
