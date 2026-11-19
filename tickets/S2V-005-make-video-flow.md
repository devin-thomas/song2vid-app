# S2V-005 - Make Video flow

Status: resolved
Blocked by: S2V-003, S2V-004, S2V-008

## Goal

Clicking Make Video saves a finished video where the person chooses.

## Scope

- The save dialog with the default name and folder, the progress bar with Cancel, locked controls, "Video saved" with Show in Finder, and error messages (SPEC §6).

## Acceptance Criteria

- The agent runs the built app on this Mac and saves one video per Frame Shape. Each plays in QuickTime at the right size and length.
- Cancel leaves no file behind. A second video can be made straight after the first.

## Dependencies

S2V-003, S2V-004, S2V-008.

## Comments

Implemented. Implementation commit: 28263ae. The flow is in `MainWindowModel` in Song2VidCore (`makeVideo(to:)`, `cancelExport()`, `exportState`, progress and saved labels, `controlsLocked`, `defaultSaveName`, `lastSaveFolder`), tested with a fake exporter behind a new `VideoExporting` protocol (20 new tests). The app side is thin: `SavePanel.swift` (the standard save sheet, default name and folder), and the progress row, Cancel, "Video saved." with Show in Finder in `ContentView.swift`.

Manual check in the running sandboxed Debug build, through the real file chooser and save sheet: one video per Frame Shape (16:9 1080p, 9:16 1080p, 1:1 480p, 4:3 2160p with the crop dragged to the bottom, Original 1672x2048), each 144.000 s with H.264 30 fps and AAC. Cancel at 26% left no file. A second video was made straight after the first. A read-only folder gave "Couldn't save to that folder" and no file. A drop during export gave "Wait for the current video to finish." and changed nothing.

Decisions and fixes beyond the SPEC:
- Two bugs found in the running app. (1) The Choose Audio/Image buttons never loaded the chosen file: the file importer cleared its own state before the result handler read it. (2) The exporter could not save at all in the sandbox: the save dialog opens only the chosen file, so the writable-folder check failed and a hidden partial file beside it could not be made. The exporter now tries creating the file instead of asking about the folder, and writes the partial file to the temporary folder when the folder isn't writable (beside the destination otherwise, as before).
- The system progress bar did not follow the value while the encoder was busy, so the bar is drawn by hand. Progress stays at 0% for a few seconds at 2160p while the still frame is encoded.
- The Replace dialog detail is now "Song now: ..." and "Dropped: ..." on separate lines, then the same for the image, with a blank line between the two slots.
- A "Wait for the current video to finish." message clears when the video ends. "Video saved." stays until the next video starts. The default folder is that of the last successful save, kept in UserDefaults, else Movies.
- While a video is made the file buttons, pickers, crop drag and keys, and drops are all disabled. Esc cancels.
