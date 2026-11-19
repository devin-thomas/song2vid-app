import Foundation
import Testing
@testable import Song2VidCore

private func url(_ name: String) -> URL { URL(fileURLWithPath: "/media/\(name)") }

/// The window's side of seam 2: what a drop does to the window, and what the dialog's two answers do.
@MainActor
@Suite("Main window: drops")
struct MainWindowDropTests {
    let oldSong = song("old.mp3", seconds: 185)
    let oldImage = picture("old.jpg", 6000, 3000)
    let newSong = song("new.mp3", seconds: 62)
    let newImage = picture("new.jpg", 1920, 1080)

    func filledWindow() async -> MainWindowModel {
        let m = model(audio: [oldSong, newSong], images: [oldImage, newImage])
        await m.chooseAudio(at: oldSong.url)
        await m.chooseImage(at: oldImage.url)
        return m
    }

    @Test func droppingOnAnEmptyWindowFillsTheSlotsWithoutAskingAnything() async {
        let m = model(audio: [newSong], images: [newImage])
        await m.drop([url("new.mp3"), url("new.jpg")])
        #expect(m.audio == newSong)
        #expect(m.image == newImage)
        #expect(m.pendingReplacement == nil)
        #expect(m.notice == nil)
    }

    @Test func droppingOnAFilledSlotAsksAndChangesNothingYet() async {
        let m = await filledWindow()
        await m.drop([url("new.mp3")])
        #expect(m.pendingReplacement?.title == "Replace the current song?")
        #expect(m.audio == oldSong)
    }

    @Test func replaceUsesTheDroppedFile() async {
        let m = await filledWindow()
        await m.drop([url("new.mp3"), url("new.jpg")])
        await m.answerReplacement(replace: true)
        #expect(m.audio == newSong)
        #expect(m.image == newImage)
        #expect(m.pendingReplacement == nil)
    }

    @Test func keepCurrentDiscardsTheDroppedFile() async {
        let m = await filledWindow()
        await m.drop([url("new.mp3"), url("new.jpg")])
        await m.answerReplacement(replace: false)
        #expect(m.audio == oldSong)
        #expect(m.image == oldImage)
        #expect(m.pendingReplacement == nil)
    }

    @Test func anEmptySlotIsFilledEvenWhenTheAnswerIsKeepCurrent() async {
        let m = model(audio: [oldSong, newSong], images: [newImage])
        await m.chooseAudio(at: oldSong.url)
        await m.drop([url("new.mp3"), url("new.jpg")])
        await m.answerReplacement(replace: false)
        #expect(m.audio == oldSong)
        #expect(m.image == newImage)
    }

    @Test func aReplacedImageMovesTheCropBackToCenterButAKeptOneDoesNot() async {
        let m = await filledWindow()
        m.frameShape = .fourByThree
        m.dragCrop(from: .center, byFramePixels: -100, 0)
        let moved = m.cropPosition
        #expect(moved != .center)

        await m.drop([url("new.jpg")])
        await m.answerReplacement(replace: false)
        #expect(m.cropPosition == moved)

        await m.drop([url("new.jpg")])
        await m.answerReplacement(replace: true)
        #expect(m.cropPosition == .center)
    }

    @Test func rejectedDropsChangeNothingAndShowTheirMessage() async {
        let m = await filledWindow()
        await m.drop([url("new.mp3"), url("other.mp3")])
        #expect(m.notice == "Drop one song, one image, or one of each.")
        #expect(m.audio == oldSong)
        #expect(m.image == oldImage)
        #expect(m.pendingReplacement == nil)
    }

    @Test func anUnreadableDroppedFileNeverReplacesAGoodOne() async {
        let m = await filledWindow()
        await m.drop([url("broken.mp3")])
        #expect(m.notice == "Song2Vid can't read this audio file.")
        #expect(m.audio == oldSong)
        #expect(m.pendingReplacement == nil)
    }

    @Test func dropsAreRefusedWhileAVideoIsBeingMade() async {
        let m = model(audio: [newSong], images: [newImage])
        m.isExporting = true
        await m.drop([url("new.mp3")])
        #expect(m.notice == "Wait for the current video to finish.")
        #expect(m.audio == nil)
    }

    @Test func aGoodDropClearsAnEarlierMessage() async {
        let m = model(audio: [newSong], images: [newImage])
        await m.drop([url("broken.mp3")])
        #expect(m.notice != nil)
        await m.drop([url("new.mp3")])
        #expect(m.notice == nil)
    }

    @Test func theDialogsNoticeShowsAfterTheAnswer() async {
        let m = await filledWindow()
        await m.drop([url("new.mp3"), url("broken.jpg")])
        #expect(m.pendingReplacement?.notice == "Song2Vid can't read this image file.")
        await m.answerReplacement(replace: false)
        #expect(m.notice == "Song2Vid can't read this image file.")
    }

    @Test func theHighlightShowsOnlyForADropThatCouldBeUsed() {
        let m = model()
        #expect(m.acceptsDrop(of: [DroppedFile(url: url("a.mp3"), kind: .audio)]))
        #expect(!m.acceptsDrop(of: [DroppedFile(url: url("Albums"), kind: .folder)]))
        m.isExporting = true
        #expect(!m.acceptsDrop(of: [DroppedFile(url: url("a.mp3"), kind: .audio)]))
    }
}
