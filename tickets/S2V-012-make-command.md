# S2V-012 - `song2vid make`

Status: ready-for-agent
Blocked by: S2V-011

## Goal

Make a video from the command line with the same results as the app (SPEC §14.2, §14.4).

## Scope

- Options `-o -s -r -c -w -n -j -q` with the rules in SPEC §14.2, including usage errors for `-c` with a Fit with bars shape, `-r` with `original`, crop values outside 0–1, clustered short options, and a "Did you mean" hint.
- Validate everything before encoding. Write to a temporary file in the output folder and move it into place at the end.
- `--overwrite` guard (ADR-014), `--dry-run`, SIGINT/SIGTERM cancel with exit 130.
- Simple result output for now (text and the JSON `result`/`error` line); live progress is S2V-013.

## Acceptance Criteria

- Each Frame Shape at 480p from generated media: correct pixel size, length within 0.1 s, both tracks (ffprobe or AVFoundation).
- `--dry-run` writes no file and reports the planned output.
- An existing output without `-w` gives 4 / `output_exists` and leaves the file unchanged; with `-w` it is replaced.
- SIGINT during encoding gives 130 and leaves no file in the output folder.
- The input files' contents and modification dates are unchanged after a run.

## Dependencies

S2V-011.
