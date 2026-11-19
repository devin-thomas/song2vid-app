# S2V-004 - Main window and live preview

Status: claimed
Blocked by: S2V-002

## Goal

The person can choose files and options and see exactly what the video frame will look like.

## Scope

- Everything in SPEC §4: file choosers, Frame Shape and Resolution pickers, Original output size, preview, Crop by dragging and arrow keys, Reset to Center, the enlarge note, the empty state, and VoiceOver labels.

## Acceptance Criteria

- The preview matches the S2V-002 placement for every Frame Shape.
- Crop can't be dragged past an edge, is kept across Resolution changes, and resets when the image or Frame Shape changes.
- Make Video is enabled only when both files are loaded.
- The window can be used with the keyboard alone.

## Dependencies

S2V-002.
