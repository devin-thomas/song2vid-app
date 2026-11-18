import Testing
import Song2VidCore

struct Song2VidIntegrationTests {
    @Test func coreIsLinked() {
        #expect(!Song2VidCore.appName.isEmpty)
    }
}
