import Foundation
import Testing
@testable import Song2VidCore

func dropped(_ name: String, _ kind: DropFileKind) -> DroppedFile {
    DroppedFile(url: URL(fileURLWithPath: "/media/\(name)"), kind: kind)
}

/// Seam 2, SPEC section 4a: rejected drops change nothing and say why.
@Suite("Drop handling: rejected drops")
struct DropRejectionTests {
    let handler = DropHandler(inspector: StubInspector())
    let empty = DropSlots()
    let filled = DropSlots(audio: song("old.mp3"), image: picture("old.jpg"))

    @Test func twoAudioFilesAreRejected() async {
        let outcome = await handler.handle([dropped("a.mp3", .audio), dropped("b.mp3", .audio)], slots: empty, isExporting: false)
        #expect(outcome == .rejected("Drop one song, one image, or one of each."))
    }

    @Test func twoImagesAreRejected() async {
        let outcome = await handler.handle([dropped("a.jpg", .image), dropped("b.jpg", .image)], slots: filled, isExporting: false)
        #expect(outcome == .rejected("Drop one song, one image, or one of each."))
    }

    @Test func moreThanTwoFilesAreRejectedEvenIfTheyAreASongAndAnImagePlusOne() async {
        let files = [dropped("a.mp3", .audio), dropped("a.jpg", .image), dropped("b.jpg", .image)]
        let outcome = await handler.handle(files, slots: empty, isExporting: false)
        #expect(outcome == .rejected("Drop no more than two files: one song, one image, or one of each."))
    }

    @Test func aFolderIsRejected() async {
        let outcome = await handler.handle([dropped("Albums", .folder)], slots: empty, isExporting: false)
        #expect(outcome == .rejected("Song2Vid can't use folders. Drop a song or an image."))
    }

    @Test func aFolderAlongsideAGoodFileRejectsTheWholeDrop() async {
        let outcome = await handler.handle([dropped("a.mp3", .audio), dropped("Albums", .folder)], slots: empty, isExporting: false)
        #expect(outcome == .rejected("Song2Vid can't use folders. Drop a song or an image."))
    }

    @Test func aFileTypeSong2VidCantReadIsRejected() async {
        let outcome = await handler.handle([dropped("notes.docx", .unsupported)], slots: empty, isExporting: false)
        #expect(outcome == .rejected("Song2Vid can't read this kind of file. Drop a song or an image."))
    }

    @Test func anUnsupportedFileAlongsideAGoodOneRejectsTheWholeDrop() async {
        let outcome = await handler.handle([dropped("a.jpg", .image), dropped("notes.docx", .unsupported)], slots: empty, isExporting: false)
        #expect(outcome == .rejected("Song2Vid can't read this kind of file. Drop a song or an image."))
    }

    @Test func dropsAreRefusedWhileAVideoIsBeingMade() async {
        let outcome = await handler.handle([dropped("a.mp3", .audio)], slots: empty, isExporting: true)
        #expect(outcome == .rejected("Wait for the current video to finish."))
    }

    @Test func theWaitMessageWinsOverEveryOtherReason() async {
        let outcome = await handler.handle([dropped("a.mp3", .audio), dropped("b.mp3", .audio)], slots: empty, isExporting: true)
        #expect(outcome == .rejected("Wait for the current video to finish."))
    }

    @Test func anEmptyDropIsRejected() async {
        let outcome = await handler.handle([], slots: empty, isExporting: false)
        #expect(outcome == .rejected("Drop a song or an image."))
    }

    // The highlight uses the same rules, before any file is read.
    @Test func validDropsHaveNoRejectionAndInvalidOnesDo() {
        #expect(DropHandler.rejection(for: [dropped("a.mp3", .audio)], isExporting: false) == nil)
        #expect(DropHandler.rejection(for: [dropped("a.mp3", .audio), dropped("a.jpg", .image)], isExporting: false) == nil)
        #expect(DropHandler.rejection(for: [dropped("Albums", .folder)], isExporting: false) != nil)
        #expect(DropHandler.rejection(for: [dropped("a.mp3", .audio)], isExporting: true) != nil)
    }
}
