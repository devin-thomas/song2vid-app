import Foundation
import Testing
@testable import Song2VidCore

/// Seam 2, SPEC section 4a: from the current slots and the dropped files to the new slots or the dialog.
@Suite("Drop handling: filling and replacing")
struct DropOutcomeTests {
    let oldSong = song("old.mp3", seconds: 185)
    let oldImage = picture("old.jpg", 4000, 3000)
    let newSong = song("new.mp3", seconds: 62)
    let newImage = picture("new.jpg", 1920, 1080)

    func handler() -> DropHandler {
        DropHandler(inspector: StubInspector(
            audio: ["new.mp3": newSong],
            images: ["new.jpg": newImage]
        ))
    }

    // MARK: Empty slots are filled straight away

    @Test func aSongOnEmptySlotsFillsTheSongSlot() async {
        let outcome = await handler().handle([dropped("new.mp3", .audio)], slots: DropSlots(), isExporting: false)
        #expect(outcome == .apply(DropSlots(audio: newSong), notice: nil))
    }

    @Test func anImageOnEmptySlotsFillsTheImageSlot() async {
        let outcome = await handler().handle([dropped("new.jpg", .image)], slots: DropSlots(), isExporting: false)
        #expect(outcome == .apply(DropSlots(image: newImage), notice: nil))
    }

    @Test func aSongAndAnImageFillBothSlotsInEitherOrder() async {
        let expected = DropOutcome.apply(DropSlots(audio: newSong, image: newImage), notice: nil)
        let one = await handler().handle([dropped("new.mp3", .audio), dropped("new.jpg", .image)], slots: DropSlots(), isExporting: false)
        let two = await handler().handle([dropped("new.jpg", .image), dropped("new.mp3", .audio)], slots: DropSlots(), isExporting: false)
        #expect(one == expected)
        #expect(two == expected)
    }

    @Test func aSongDroppedWhereOnlyTheImageSlotIsFilledNeedsNoQuestion() async {
        let outcome = await handler().handle([dropped("new.mp3", .audio)], slots: DropSlots(image: oldImage), isExporting: false)
        #expect(outcome == .apply(DropSlots(audio: newSong, image: oldImage), notice: nil))
    }

    // MARK: A filled slot asks first

    @Test func aSongOnAFilledSongSlotAsksToReplaceTheSong() async {
        let slots = DropSlots(audio: oldSong, image: oldImage)
        let outcome = await handler().handle([dropped("new.mp3", .audio)], slots: slots, isExporting: false)
        guard case .confirm(let dialog) = outcome else { Issue.record("expected a dialog, got \(outcome)"); return }
        #expect(dialog.title == "Replace the current song?")
        #expect(dialog.replaceButton == "Replace")
        #expect(dialog.keepButton == "Keep Current")
        #expect(dialog.ifReplaced == DropSlots(audio: newSong, image: oldImage))
        #expect(dialog.ifKept == slots)
        #expect(dialog.notice == nil)
        #expect(dialog.detail == """
            Song now: old.mp3, 3:05
            Dropped song: new.mp3, 1:02
            """)
    }

    @Test func anImageOnAFilledImageSlotAsksToReplaceTheImage() async {
        let slots = DropSlots(audio: oldSong, image: oldImage)
        let outcome = await handler().handle([dropped("new.jpg", .image)], slots: slots, isExporting: false)
        guard case .confirm(let dialog) = outcome else { Issue.record("expected a dialog, got \(outcome)"); return }
        #expect(dialog.title == "Replace the current image?")
        #expect(dialog.ifReplaced == DropSlots(audio: oldSong, image: newImage))
        #expect(dialog.ifKept == slots)
        #expect(dialog.detail == """
            Image now: old.jpg, 4000×3000 pixels
            Dropped image: new.jpg, 1920×1080 pixels
            """)
    }

    @Test func theDialogNamesWhatIsThereAndWhatWasDropped() async {
        let slots = DropSlots(audio: oldSong, image: oldImage)
        let outcome = await handler().handle([dropped("new.mp3", .audio), dropped("new.jpg", .image)], slots: slots, isExporting: false)
        guard case .confirm(let dialog) = outcome else { Issue.record("expected a dialog, got \(outcome)"); return }
        #expect(dialog.detail == """
            Song now: old.mp3, 3:05
            Dropped song: new.mp3, 1:02

            Image now: old.jpg, 4000×3000 pixels
            Dropped image: new.jpg, 1920×1080 pixels
            """)
    }

    @Test func aSongAndAnImageOnTwoFilledSlotsAskOneQuestionAboutBoth() async {
        let slots = DropSlots(audio: oldSong, image: oldImage)
        let outcome = await handler().handle([dropped("new.mp3", .audio), dropped("new.jpg", .image)], slots: slots, isExporting: false)
        guard case .confirm(let dialog) = outcome else { Issue.record("expected a dialog, got \(outcome)"); return }
        #expect(dialog.title == "Replace the current song and image?")
        #expect(dialog.ifReplaced == DropSlots(audio: newSong, image: newImage))
        #expect(dialog.ifKept == slots)
    }

    @Test func aDropOfBothWithOnlyTheSongSlotFilledAsksAboutTheSongAndFillsTheImageEitherWay() async {
        let slots = DropSlots(audio: oldSong)
        let outcome = await handler().handle([dropped("new.mp3", .audio), dropped("new.jpg", .image)], slots: slots, isExporting: false)
        guard case .confirm(let dialog) = outcome else { Issue.record("expected a dialog, got \(outcome)"); return }
        #expect(dialog.title == "Replace the current song?")
        #expect(dialog.ifReplaced == DropSlots(audio: newSong, image: newImage))
        #expect(dialog.ifKept == DropSlots(audio: oldSong, image: newImage))
        #expect(!dialog.detail.contains("Image now"))
    }

    @Test func aDropOfBothWithOnlyTheImageSlotFilledAsksAboutTheImageAndFillsTheSongEitherWay() async {
        let slots = DropSlots(image: oldImage)
        let outcome = await handler().handle([dropped("new.mp3", .audio), dropped("new.jpg", .image)], slots: slots, isExporting: false)
        guard case .confirm(let dialog) = outcome else { Issue.record("expected a dialog, got \(outcome)"); return }
        #expect(dialog.title == "Replace the current image?")
        #expect(dialog.ifReplaced == DropSlots(audio: newSong, image: newImage))
        #expect(dialog.ifKept == DropSlots(audio: newSong, image: oldImage))
    }

    // MARK: An unreadable file never replaces a good one

    @Test func anUnreadableSongNeverReplacesTheCurrentOneAndAsksNothing() async {
        let slots = DropSlots(audio: oldSong, image: oldImage)
        let outcome = await handler().handle([dropped("broken.mp3", .audio)], slots: slots, isExporting: false)
        #expect(outcome == .rejected("Song2Vid can't read this audio file."))
    }

    @Test func anUnreadableImageIsRejectedOnEmptySlotsToo() async {
        let outcome = await handler().handle([dropped("broken.jpg", .image)], slots: DropSlots(), isExporting: false)
        #expect(outcome == .rejected("Song2Vid can't read this image file."))
    }

    @Test func whenBothFilesAreUnreadableBothAreNamed() async {
        let outcome = await handler().handle([dropped("broken.mp3", .audio), dropped("broken.jpg", .image)], slots: DropSlots(audio: oldSong), isExporting: false)
        #expect(outcome == .rejected("Song2Vid can't read this audio file. Song2Vid can't read this image file."))
    }

    @Test func aGoodFileIsStillUsedWhenItsPartnerIsUnreadableAndTheMessageStays() async {
        let outcome = await handler().handle([dropped("new.mp3", .audio), dropped("broken.jpg", .image)], slots: DropSlots(image: oldImage), isExporting: false)
        #expect(outcome == .apply(DropSlots(audio: newSong, image: oldImage), notice: "Song2Vid can't read this image file."))
    }

    @Test func anUnreadableFileIsNotWorthAQuestionButTheGoodOneIsAskedAbout() async {
        let slots = DropSlots(audio: oldSong, image: oldImage)
        let outcome = await handler().handle([dropped("new.mp3", .audio), dropped("broken.jpg", .image)], slots: slots, isExporting: false)
        guard case .confirm(let dialog) = outcome else { Issue.record("expected a dialog, got \(outcome)"); return }
        #expect(dialog.title == "Replace the current song?")
        #expect(dialog.ifReplaced == DropSlots(audio: newSong, image: oldImage))
        #expect(dialog.ifKept == slots)
        #expect(dialog.notice == "Song2Vid can't read this image file.")
    }
}
