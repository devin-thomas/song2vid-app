# S2V-025 - Windows: `song2vid.exe` with check, preview and the info options

Status: open
Blocked by: S2V-022, S2V-024

## Goal

A Rust `song2vid.exe` that parses the shared contract and answers everything that does not encode (SPEC §14.2, §14.3, §24.3, §26.1, §26.3).

## Scope

- `windows/tool/` Rust crate, `x86_64-pc-windows-msvc`, `crt-static`, manifest with UTF-8 code page and `longPathAware`; a build check fails on any import outside Windows' own DLLs.
- The full option table (every long and short form, no clustering, "Did you mean", unknown text never echoed), `-h -v -S -R -u`, `check`, `preview`.
- Frame math ported from `OutputFrame`, tested against `fixtures/frame-math.json`.
- Finds `ffmpeg.exe`/`ffprobe.exe` only in its own folder; runs them in a kill-on-close job object with `CREATE_NO_WINDOW`.
- `windows/scripts/check.ps1` builds and tests it on Titan.

## Acceptance Criteria

- Every fixture case matches exactly.
- `check` and `preview` text and JSON match the Mac command's for the same generated inputs (names, sizes, placement, enlarged), apart from the encoder fields.
- Orientation: a rotated JPEG, HEIC and TIFF preview upright; a transparent PNG previews with black.
- Path matrix (SPEC §26.3) for `check` and `preview`; no folder path or planted secret in any output.
- Exit statuses 1, 2 and 3 with their codes; `-S` prints the bundled skill; `-v` prints `song2vid 1.2.0`.
- One-file `check` (SPEC §24.8): output matches the Mac command for an audio file alone, an image alone, an unreadable file alone and a missing file alone (`audio_not_found`/`image_not_found` by extension).

## Dependencies

S2V-022, S2V-024.

## Comments
