# S2V-024 - Windows: the bundled LGPL FFmpeg

Status: open
Blocked by: none

## Goal

A small, reproducible LGPL FFmpeg and FFprobe for win32-x64 with exactly what SPEC §26.2 lists.

## Scope

- `windows/ffmpeg/` script that downloads a pinned FFmpeg release (address and SHA-256 recorded) and `nv-codec-headers`, and builds with one recorded configure line (cross-built in a container on the Mac, or on Titan; record which).
- Output staged with the starter's `scripts/stage.ts` layout (`bin/win32-x64/`).
- Notices text for `THIRD-PARTY-NOTICES.txt`: LGPL statement, source, checksum, configure line, licence texts of linked runtime libraries.

## Acceptance Criteria

- `ffmpeg -buildconf` shows no `--enable-gpl` or `--enable-nonfree`; `ffmpeg -encoders` lists `h264_nvenc`, `hevc_nvenc`, `h264_mf`, `hevc_mf`, `aac`.
- On Titan: a 10 s still-image test encode succeeds with `h264_nvenc`, `hevc_nvenc` and `h264_mf`. On the DeskMini (when reachable): `h264_mf` and `hevc_mf` with hardware encoding.
- Every SPEC §7 input type decodes (generated samples, including a HEIC and an ALAC M4A).
- Two builds from the script produce the same configure line and the same feature list; the combined size of the two programs is recorded.

## Dependencies

None.

## Comments
