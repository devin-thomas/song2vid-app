import AppKit
import Song2VidCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = MainWindowModel(lastSaveFolder: SavePanel.rememberedFolder)
    @State private var picking: FileKind = .audio
    @State private var isPicking = false
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
        .frame(minWidth: 560, minHeight: 580)
        .fileImporter(
            isPresented: $isPicking,
            allowedContentTypes: picking.types
        ) { result in
            guard case .success(let url) = result else { return }
            let kind = picking
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
                Button("Choose Audio…") { picking = .audio; isPicking = true }
                    .disabled(model.controlsLocked)
                    .keyboardShortcut("o", modifiers: .command)
                    .accessibilityLabel("Choose Audio")
                    .accessibilityHint("Opens a file chooser for a song")
                fileSummary(model.audioSummary, empty: "No audio chosen")
            }
            GridRow {
                Button("Choose Image…") { picking = .image; isPicking = true }
                    .disabled(model.controlsLocked)
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
                .disabled(model.controlsLocked)
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
                    .disabled(model.controlsLocked)
                } else if let label = model.outputSizeLabel {
                    Text(label)
                        .monospacedDigit()
                } else {
                    Text("Output follows the image")
                        .foregroundStyle(.secondary)
                }
            }
            GridRow(alignment: .firstTextBaseline) {
                Text("Codec")
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Codec", selection: $model.codec) {
                        ForEach(Codec.allCases, id: \.self) { codec in
                            Text(codec.title).tag(codec)
                                .disabled(codec == .hevc && !model.canMakeHEVC)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!model.codecPickerEnabled)
                    .accessibilityLabel("Codec")
                    .accessibilityHint(model.codecNote ?? "Chooses how the video is compressed: H.264 or HEVC")
                    if let note = model.codecNote {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
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
            if let label = model.progressLabel {
                progressRow(model.progressFraction, label: label)
            }
            if let saved = model.savedVideoMessage, let url = model.savedVideoURL {
                HStack {
                    Label(saved, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let codec = model.savedCodecMessage {
                        Text(codec)
                            .foregroundStyle(.secondary)
                    }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .accessibilityHint("Shows the saved video in a Finder window")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// `progress` is nil while the video is still being prepared, which shows a bar that just moves.
    private func progressRow(_ progress: Double?, label: String) -> some View {
        HStack(spacing: 12) {
            if let progress {
                // Drawn by hand: the system ProgressView's fill did not follow the value while the encoder was busy.
                // At 0% the capsule is empty.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(Color.accentColor)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 8)
                .accessibilityElement()
                .accessibilityLabel("Making video")
                .accessibilityValue("\(Int(progress * 100)) percent")
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Preparing the video")
            }
            Text(label)
                .monospacedDigit()
            Button("Cancel") { model.cancelExport() }
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Stops making the video and deletes the unfinished file")
        }
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

    /// Asks where to save, then makes the video there (SPEC section 6).
    private func makeVideo() {
        guard model.canMakeVideo else { return }
        SavePanel.ask(name: model.defaultSaveName ?? "Video.mp4", folder: model.lastSaveFolder) { destination in
            Task {
                await model.makeVideo(to: destination)
                SavePanel.remember(model.lastSaveFolder)
            }
        }
    }
}
