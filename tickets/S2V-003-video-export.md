# S2V-003 - Video export

Status: ready-for-agent
Blocked by: S2V-002

## Goal

Given an audio file, an image and a placement, write a correct MP4 with progress and cancel.

## Scope

- Read the audio and image (SPEC §7). Render the still frame. Write H.264 at 30 fps plus AAC audio (SPEC §6.3).
- Report progress. Support cancel. Delete the partial file on cancel or failure. Return plain error messages.

## Acceptance Criteria

- Integration tests (SPEC §11) pass: correct pixel size for each Frame Shape, length within ±0.1 s, both tracks present, and the file removed after cancel.
- Unreadable audio or image gives the SPEC §7 message.

## Dependencies

S2V-002.
