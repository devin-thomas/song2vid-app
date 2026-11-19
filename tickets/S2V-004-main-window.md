# S2V-004 - Main window and live preview

Status: resolved
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

## Comments

Implemented. Implementation commit: 3735f7b. The window logic is `MainWindowModel` in Song2VidCore (36 new tests: labels, enabling, Crop drag and nudge limits, keep or reset rules), and the views in `Song2Vid/` are thin. Make Video is a no-op placeholder for S2V-005. Drag and drop is left for S2V-008.

Decisions on points the SPEC leaves open:
- Arrow keys move the image the way a drag does (Left shows more of the right side). Each press is 5% of the movable range; Shift makes it 25%.
- Original with an image under 16 pixels shows the "too small" message in the preview and disables Make Video; other Frame Shapes still work for that image.
- The enlarge note names the output frame size (for Fit with bars too).
- With no image, the empty frame uses the chosen Frame Shape and Resolution (16:9 for Original).
- Shortcuts for keyboard use: Cmd-O (audio), Shift-Cmd-O (image), Shift-Cmd-R (Reset to Center), Return (Make Video).
