import AppKit
import UniformTypeIdentifiers

/// The standard save dialog for the video (SPEC section 6.1). macOS asks before replacing an existing file.
@MainActor
enum SavePanel {
    private static let folderKey = "lastSaveFolder"

    /// The folder of the last save, if it is still there.
    static var rememberedFolder: URL? {
        guard let path = UserDefaults.standard.string(forKey: folderKey) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func remember(_ folder: URL?) {
        guard let folder else { return }
        UserDefaults.standard.set(folder.path, forKey: folderKey)
    }

    /// Shows the dialog as a sheet on the window, starting in `folder` or Movies, and calls `chosen` with the destination.
    static func ask(name: String, folder: URL?, chosen: @escaping @MainActor (URL) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.directoryURL = folder ?? moviesFolder
        panel.message = "Choose where to save the video."
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            chosen(url)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    /// The person's real Movies folder (inside the sandbox, the usual lookup would give the app's own container).
    private static var moviesFolder: URL? {
        guard let home = getpwuid(getuid()).flatMap({ String(cString: $0.pointee.pw_dir) }) else { return nil }
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Movies", isDirectory: true)
    }
}
