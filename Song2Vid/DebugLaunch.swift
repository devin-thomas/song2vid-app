#if DEBUG
import AppKit
import Foundation
import Song2VidCore

/// Debug builds only: lets a manual check start with files and choices already set, using launch arguments such as
/// `-S2VAudio <path> -S2VImage <path> -S2VShape 4:3 -S2VResolution 480p -S2VAppearance light`. Paths come from the person running the check.
@MainActor
enum DebugLaunch {
    static func apply(to model: MainWindowModel) async {
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "S2VAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        if let path = defaults.string(forKey: "S2VAudio") {
            await model.chooseAudio(at: URL(fileURLWithPath: path))
        }
        if let path = defaults.string(forKey: "S2VImage") {
            await model.chooseImage(at: URL(fileURLWithPath: path))
        }
        if let name = defaults.string(forKey: "S2VShape"),
           let shape = FrameShape.allCases.first(where: { $0.debugName == name }) {
            model.frameShape = shape
        }
        if let name = defaults.string(forKey: "S2VResolution"),
           let resolution = Resolution.allCases.first(where: { String($0.shortSide) + "p" == name }) {
            model.resolution = resolution
        }
    }
}

private extension FrameShape {
    var debugName: String {
        self == .original ? "Original" : title
    }
}
#endif
