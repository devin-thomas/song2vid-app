import Foundation
import Testing
@testable import Song2VidCore

/// Which slot a dropped item belongs to, decided from its type (SPEC sections 4a and 7).
@Suite("Drop handling: sorting dropped items by type")
struct DropClassifierTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("s2v-classify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test(arguments: ["mp3", "m4a", "wav", "aiff", "aif", "flac", "caf", "MP3"])
    func supportedAudioExtensionsAreAudio(ext: String) {
        let url = URL(fileURLWithPath: "/media/song.\(ext)")
        #expect(DropFileKind.of(url) == .audio)
    }

    @Test(arguments: ["jpg", "jpeg", "png", "heic", "tif", "tiff", "webp", "gif", "bmp", "JPG"])
    func supportedImageExtensionsAreImages(ext: String) {
        let url = URL(fileURLWithPath: "/media/cover.\(ext)")
        #expect(DropFileKind.of(url) == .image)
    }

    @Test(arguments: ["docx", "txt", "pdf", "mp4", "mov", "zip", "svg", ""])
    func everythingElseIsUnsupported(ext: String) {
        let name = ext.isEmpty ? "mystery" : "mystery.\(ext)"
        #expect(DropFileKind.of(URL(fileURLWithPath: "/media/\(name)")) == .unsupported)
    }

    @Test func aFolderIsAFolderEvenIfItsNameLooksLikeASong() throws {
        let parent = try makeFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let tricky = parent.appendingPathComponent("album.mp3", isDirectory: true)
        try FileManager.default.createDirectory(at: tricky, withIntermediateDirectories: true)
        #expect(DropFileKind.of(tricky) == .folder)
        #expect(DropFileKind.of(parent) == .folder)
    }
}
