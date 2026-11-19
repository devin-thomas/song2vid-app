import SwiftUI
import Song2VidCore

@main
struct Song2VidApp: App {
    var body: some Scene {
        Window(Song2VidCore.appName, id: "main") {
            ContentView()
        }
        .defaultSize(width: 760, height: 640)
        .windowResizability(.contentMinSize)
    }
}
