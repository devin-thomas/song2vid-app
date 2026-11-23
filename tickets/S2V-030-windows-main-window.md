# S2V-030 - Windows app: the main window and the make flow

Status: open
Blocked by: S2V-025, S2V-029

## Goal

The Song2Vid window works end to end on Windows: choose or drop files, pick options, crop, make, cancel, and recover from every error (SPEC §27.2 to §27.8).

## Scope

- The layout of SPEC §27.2 with the starter's parts; the preview from `song2vid preview`; crop drag, nudges, Reset to Center and the "Crop position" value text.
- Drag and drop with the Replace dialog (SPEC §4a, §27.3); save dialog and the `--overwrite` rule; progress, Cancel, done and closing-during-a-job states; the error table and the blocking missing-tool state; About with notices.
- Saved preferences: Codec, last save folder, theme, window bounds.
- Audit states, journey scripts, shortcut effects, `fill()`, shots, `electron/qa.ts` and `measure/workload.js` replaced for Song2Vid; visual baselines accepted for Windows and macOS.

## Acceptance Criteria

- `pnpm qa:audit` and `pnpm qa:visual` pass, covering empty, one file, both files, each Frame Shape, HEVC disabled, making, cancelling, done, every error row and the missing-tool state, in both themes and at the four audited sizes.
- The four journeys run by keyboard alone within their step budgets, with both key families.
- With the real tool on Titan (headless page against the real adapter), one video per Frame Shape matches the command's output for the same options.
- No banned term, path or template token in any state.

## Dependencies

S2V-025, S2V-029.

## Comments
