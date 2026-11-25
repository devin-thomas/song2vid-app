# S2V-024 - Windows: the bundled LGPL FFmpeg

Status: resolved
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
- 2026-11-23 (builder): Built the pinned LGPL FFmpeg 8.1.3 and FFprobe for win32-x64 in `windows/ffmpeg/`. The recipe cross-builds in a Docker container on the Mac (Debian trixie arm64 image and package snapshot pinned by digest and date, mingw-w64 GCC), downloads the FFmpeg source and `nv-codec-headers` n12.2.72.0 (commit `c692783`) with SHA-256 checks, and builds with one configure line recorded in `compile.sh`. The `build.sh` output follows the starter's staging layout (`bin/win32-x64/ffmpeg.exe`, `ffprobe.exe`, `THIRD-PARTY-NOTICES.txt`). The notices carry the LGPL statement, sources and checksums, the configure line, and the licence texts of the linked runtime libraries. Both programs import only Windows system DLLs. Enabled the GIF parser, which the GIF demuxer needs to assemble frames, and made the build assert it.
  - `./windows/ffmpeg/build.sh` passed (0) and `./windows/ffmpeg/build.sh <second directory>` passed (0). Configure reported `License: LGPL version 2.1 or later` and the build asserts `CONFIG_GPL 0` and `CONFIG_NONFREE 0`. Sizes: `ffmpeg.exe` 9,472,000 and `ffprobe.exe` 9,256,448 bytes, **18,728,448 bytes combined** (stripped).
  - Two builds: the notices are byte-identical, and the configure line and all eight feature lists (`-buildconf -encoders -decoders -demuxers -muxers -filters -protocols -bsfs`) match for both programs. The executables are not bit-identical: `ffmpeg.exe` differs in 3 bytes and `ffprobe.exe` in 2, all inside the first 220 bytes (the PE header), so the criterion (same configure line and feature list) is met without claiming bit-identical output.
  - On Titan over ssh (headless, a scratch folder removed afterwards), with the two staged builds and the generated media copied across (SHA-256 of all four executables matched the Mac): `.\check.ps1 -Staging a -SecondStaging b -Media media -Machine Titan` passed (0). It verified no `--enable-gpl` or `--enable-nonfree` in `-buildconf` and the five encoders `h264_nvenc`, `hevc_nvenc`, `h264_mf`, `hevc_mf`, `aac` in `-encoders`. It decoded every SPEC §7 input type to a 320x240 PNG or re-encoded it as AAC: JPEG, PNG, HEIC (single and tiled, through the Tile Grid stream group), TIFF, WebP, GIF, BMP, MP3, M4A (AAC), AAC, WAV, AIFF, FLAC, ALAC M4A and CAF. GIF now passes. It then produced a 10.000 s MP4 with 300 frames, H.264/HEVC video in the right tag (`avc1`/`hvc1`) and AAC audio with `h264_nvenc`, `hevc_nvenc` and the software `h264_mf`, each checked with `ffprobe`.
  - Supplementary on the Mac (not Titan): the same executables under Wine 10.0 in a linux/amd64 container produced the same encoder list, no GPL grep match, and decoded all images and audio inputs, GIF included, with exit 0; `-buildconf` was identical for the two builds there.
  - `scripts/check.sh` passed (0) on the final tree (no Mac code changed). One earlier run failed (65) when the Mac's disk filled during the Xcode tests (`No space left on device`); it passed after scratch files were removed.
  - Not checked: `h264_mf` and `hevc_mf` with hardware encoding on the DeskMini (SSH to the DeskMini is still off). `check.ps1 -Machine DeskMini` is written for it and requires `-hw_encoding 1` for both encoders. The Titan run exercised `h264_mf` in software only and never ran `hevc_mf`. The ticket stays `open` on that one criterion; every other criterion is met. Titan's ssh intermittently refused the key for several minutes during the run, then accepted it again, with no change made on this side.

### 2026-11-24, coordinator

Owner direction on 2026-11-24: Titan stands in for the DeskMini, and nothing waits for it. On Titan, the staged 8.1.3 build encoded a PNG plus WAV with `h264_mf -hw_encoding 1` and `hevc_mf -hw_encoding 1` (NVIDIA's Media Foundation encoder). Both exited 0, and the outputs probe as h264 and hevc at 1280x720. Together with the NVENC and software encodes recorded above, every encoder in the build is proven on real hardware. Still for the owner: one encode on the DeskMini (AMD 3400G, Windows 10) through AMD's Media Foundation encoder. Resolved.
