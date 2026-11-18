# S2V-008 - Drag and drop with replace dialog

Status: ready-for-agent
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
