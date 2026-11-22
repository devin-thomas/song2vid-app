# S2V-012 - `song2vid make`

Status: resolved
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

## Comments

Built on `ticket/S2V-012`, from `build/v2` at the S2V-011 merge. `make` adds a case and rows to the option table (`-o -s -r -c -w -n -q`, and `-j` and `-h` now also apply to `make`), then runs the app's own export (`VideoExporting`, `ExportRequest`, `OutputFrame`); no frame or export logic is copied. The command line is turned into a `MakeOptions` value first, so every usage rule of SPEC 14.2 is found before a file is looked at, then the files, the size for Original and the output are checked, and only then does the export start.

The export writes to a hidden temporary file in the output folder. The final name is touched once, at the end: with `--overwrite` by an atomic rename over the old file, without it by a rename that fails if the name is taken (a file that appeared during the run gives 4 and the new video is deleted). Ctrl-C and SIGTERM are read through dispatch signal sources with the default action ignored, so the export is cancelled, its files are deleted and the command exits 130.

All system-framework work runs with fd 1 and 2 pointed at /dev/null. The command keeps private copies of the real streams in a `CommandChannel`, which the progress handler receives with each event, so S2V-013 only adds rendering. A test proves the channel writes reach the real stderr while other writes do not.

Seam 5 tests run the built command as a separate process, including a run long enough to send it Ctrl-C and to plant a file at the output mid-run. The choices the spec left open are in the implementer notes.

- 2026-11-22 (coordinator): Verified and merged. check.sh passed on a separate checkout of f1a1863. Made one video per Frame Shape with `make` from the owner's real MP3 and a 2048×2048 JPEG (16:9 1080p, 9:16 1080p, 1:1 480p, 4:3 2160p cropped to the bottom, Original), 1–3 s each. ffprobe: correct sizes, H.264 plus AAC, 137.143 s against a 137.143 s source. Viewed a 4:3 frame: the bottom of the image is kept. A repeat without `-w` gave 4 / `output_exists`. Not checked: a real Ctrl-C in Terminal (S2V-013 covers the headed run), `disk_full`, x86_64.
