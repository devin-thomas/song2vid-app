import Testing
import Song2VidCore

struct Song2VidTests {
    @Test func appNameIsSong2Vid() {
        #expect(Song2VidCore.appName == "Song2Vid")
    }
}
