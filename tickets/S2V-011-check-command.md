# S2V-011 - `song2vid check`

Status: resolved
Blocked by: S2V-010

## Goal

A read-only command that tells a person or agent what Song2Vid would make from two files (SPEC §14.3).

## Scope

- `song2vid check <audio> <image> [-j]`, using the existing audio and image readers and frame rules.
- Text output and a single JSON `result` or `error` line under `--json` (SPEC §14.5).
- Exit statuses 0, 1, 2 and 3 with their error codes (SPEC §14.6).
- `check --help` with usage, examples and exit statuses.

## Acceptance Criteria

- For generated media, the JSON lists every Frame Shape and Resolution with sizes matching SPEC §5, placement, and enlarged flags; Original reports "too small" under 16 px.
- Missing audio gives 1 / `audio_not_found`; an unreadable image gives 3 / `image_unreadable`; an unknown option gives 2 without echoing it.
- No output contains a folder path, a planted fake secret from the environment, or file contents.

## Dependencies

S2V-010.

## Comments

Built on `ticket/S2V-011`, from `build/v2` at the S2V-010 commit. `check` reads both files with `AudioInfo.read` and `ImageInfo.read` and takes every size and enlarged flag from `OutputFrame`; no logic is copied. The command line is read by a small table-driven parser (`CommandOptions.swift`): each option has a short form, a long form, the commands it applies to and whether it takes a value, so `make` is a new case and new rows. JSON is written from a fixed list of keys (`CommandJSON.swift`), so a key outside the list cannot be written.

Found while testing: the macOS audio and image readers write their own log lines to stderr for a file that is not what it claims to be, and the image reader's line contains the full file path. The readers now run with stdout and stderr pointed at /dev/null (`CommandSilence.swift`), and a test sets `OS_ACTIVITY_DT_MODE=YES` to prove it.

Seam 5 tests (the built command as a separate process) cover every acceptance criterion, including a planted fake value and folder path in text and JSON, on success and on error. The JSON keys and the choices the spec left open are in the implementer notes.
- 2026-11-22 (coordinator): Verified and merged. check.sh passed on a separate checkout of 320a7af. Ran `check` on the owner's real MP3 and a 2048×2048 JPEG (text and JSON; sizes and enlarged flags correct by hand), a .docx as audio gave 3 / `audio_unreadable`, and with `OS_ACTIVITY_DT_MODE=YES` no folder path leaked. Not checked: other audio and image formats, the x86_64 slice, terminal (tty) output.
