import AppKit
import Song2VidCore
import SwiftUI
import UniformTypeIdentifiers

/// The whole window accepts dropped files (SPEC section 4a). Every drop is accepted so a bad one can be answered with a
/// message; only a drop that could be used gets the highlight.
struct WindowDropDelegate: DropDelegate {
    let model: MainWindowModel
    @Binding var highlighted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        highlighted = model.acceptsDrop(of: Self.heldFiles())
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        highlighted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        highlighted = false
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.fileURL(from: provider) { urls.append(url) }
            }
            await model.drop(urls)
        }
        return true
    }

    /// The files being dragged, read from the drag pasteboard so the highlight can be decided before the drop.
    private static func heldFiles() -> [DroppedFile] {
        let urls = NSPasteboard(name: .drag)
            .readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.map { DroppedFile(url: $0, kind: DropFileKind.of($0)) }
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// Shown over the window while a usable drop is held above it.
struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.accentColor.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 4)
            }
            .padding(6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
