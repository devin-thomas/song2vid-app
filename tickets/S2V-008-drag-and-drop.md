# S2V-008 - Drag and drop with replace dialog

Status: resolved
Blocked by: S2V-004

## Goal

Dropping a song, an image or both onto the window fills the slots, and asks before replacing anything.

## Scope

- Everything in SPEC §4a: the drop-handling seam (pure logic plus tests), the window drop target and highlight, the Replace / Keep Current dialog, rejection messages, and refusing drops during export.

## Acceptance Criteria

- Unit tests at the drop-handling seam cover every rule in SPEC §4a.
- In the running app, dropping one audio file, one image, or both works. Dropping onto a filled slot shows the dialog, and Esc keeps the current file.

## Dependencies

S2V-004.

## Comments

Implemented. Implementation commit: a9d29a8. Drop logic is `DropHandler` in Song2VidCore (seam 2: current slots plus dropped files gives rejection, new slots, or the dialog; 4 new test files, every SPEC 4a rule). `MainWindowModel` gained `drop`, `answerReplacement`, `acceptsDrop` and `isExporting` (S2V-005 sets it while a video is made). The app side is thin: `WindowDrop.swift` (whole-window drop target, highlight) and `ReplaceAlert.swift` (NSAlert sheet).

Decisions on points the SPEC leaves open:
- One dialog covers every filled slot the drop touches. A dropped file for an empty slot is filled whatever the answer.
- The dialog detail names what is there and what was dropped, one line per slot.
- Esc on NSAlert is routed to Keep Current with a key monitor, since SwiftUI alerts cannot make one button both default and Esc.
- Rejection checks run in this order: exporting, folder, more than two files, unsupported type, two of one kind. Any of them rejects the whole drop.
- An unreadable dropped file (type fine, contents bad) never replaces anything. If its partner is readable, the partner is still used and the "can't read" message stays shown; if both are unreadable, both messages show.
- The highlight shows only when the held files pass the type checks and nothing is exporting. Every file drop is accepted so a rejected one can show its message.
