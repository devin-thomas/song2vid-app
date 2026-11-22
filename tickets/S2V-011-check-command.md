# S2V-011 - `song2vid check`

Status: ready-for-agent
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
