# S2V-022 - Mac: HEVC and the 1.2 command contract

Status: resolved
Blocked by: none

## Goal

The Mac command and core make HEVC and implement every addition in SPEC §24, so the shared contract exists and is tested before Windows starts (SPEC §23, §24, §25).

## Scope

- `StillEncoder`/`VideoExporter` take a Codec; HEVC is Main profile with the `hvc1` tag and the same quality, rate, group length and colour tags as H.264.
- `--codec`/`-C`, `song2vid encoders`, `song2vid preview`, `--cancel-on-eof`/`-E`; the `codec`, `encoder`, `encoder_fallback` keys and the `encoder` key in progress lines; `codec_unavailable` and `output_in_use` in the code table (the second is never produced on the Mac); version 1.2.0.
- Section 14.5's allowlist rule changed as SPEC §24.5 says; `--help` for each new command and option.
- The Swift tests write `fixtures/frame-math.json` (SPEC §31, at least 200 cases) and fail if the committed file is stale.

## Acceptance Criteria

- HEVC at 480p for each Frame Shape: correct size, length within 0.1 s, `hvc1` tag, Main profile, AAC audio (ffprobe).
- `encoders --json` reports `apple` for each Codec this Mac can make; with HEVC made unavailable by a test seam, `make -C hevc` gives 3 / `codec_unavailable` before writing anything.
- `preview` writes an oriented PNG within 2048 px for a rotated JPEG and a HEIC; refuses an existing file without `-w`.
- `make --cancel-on-eof` with stdin closed after 1 s exits 130 within 2 s and leaves no file; without the option, a closed stdin changes nothing.
- 1.1-era JSON consumers still parse every line (no key removed or renamed); `scripts/check.sh` passes.

## Dependencies

None.

## Comments
- 2026-11-22 (builder): Built the Mac 1.2.0 command contract, shared HEVC export, Apple encoder probe, oriented PNG preview, opt-in stdin cancellation, and 315 Swift-generated frame math cases. Updated the staged help, docs and Agent Guide for the new commands and additive JSON fields. Section 14.5 now follows section 24.5. A non-PNG destination for `preview` is a usage error.
  - `scripts/check.sh` passed (0). The Swift package tests, both Xcode test targets, ad-hoc signing and entitlements, both universal slices, the bundled command, and the site checks passed. The process tests exercised rotated JPEG and HEIC, black transparency, overwrite refusal and replacement, 1.1 JSON readers, and the test seam returning exit 3 and `codec_unavailable` without writing.
  - `ffprobe -v error -show_streams -show_format -of json <output>` and `ffprobe -v error -select_streams v:0 -show_packets -show_entries packet=pts_time,flags -of json <output>` passed (0) on five generated HEVC outputs. Sizes were 854x480, 480x854, 480x480, 640x480 and 640x480 for 16:9, 9:16, 1:1, 4:3 and Original. Each was 13.370 seconds, `hvc1` Main, 8-bit 4:2:0, BT.709, 30 fps and AAC, with keyframes at 0 and 10 seconds. `ffmpeg -v error -xerror -i <output> -f null -` decoded all five (0).
  - `song2vid encoders -j` reported `apple` for H.264 and HEVC (0). For `song2vid make <song> <image> -r 480p -o <output> -j -E`, stdin EOF after one second gave exit 130 in 0.004 seconds. A split `cancel` line at one second gave exit 130 in 0.037 seconds. Both left the output directory unchanged. The same command without `-E` made a complete MP4 with stdin at EOF (0).
  - `SONG2VID_UPDATE_FRAME_FIXTURES=1 swift test --package-path Song2VidCore --filter FrameMathFixtureTests` regenerated 315 cases (0). `swift test --package-path Song2VidCore --filter FrameMathFixtureTests` failed with exit 1 for a deliberately stale fixture and passed with the generated file restored. `scripts/test-check-site.sh <built song2vid>` passed (0). Headless WebKit rendered the download and docs pages at 1280, 390 and 320 pixels.
  - A gate attempt under heavy host load recorded a 0.716-second read gap in the JSON progress test. A direct replay measured a maximum 0.374-second read gap, with an approximately 0.25-second producer interval. The complete gate passed on retry with its timing assertions intact. Runtime checks used Apple silicon. The universal gate built and signature-checked the Intel slice.

- 2026-11-22 (builder): Repaired the process tests after the coordinator's gate on `a6ed20b` failed (65) when the `.mp4` output-name case printed checking progress. Audited the integration tests. Progress-capable `make` assertions now parse every JSON line and require exactly one result or error at the end. Dry runs, usage errors and commands without progress retain their single-line checks. Plain validation errors also allow preceding checking lines. Added a regression case for progress before `output_not_mp4` and for missing, duplicate and malformed final output.
  - `xcodebuild build -project Song2Vid.xcodeproj -scheme Song2Vid -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-arm64 ARCHS=arm64 -quiet` passed (0) on `plan/windows` (`b0cde58`). Measured the time from launch to the final error for `song2vid make a.m4a i.png --out=<dir>/.mp4 -j`, with H.264 as the default in both ARM64 Debug builds. In 40 interleaved runs per build after warm-up, `plan/windows` took 21.9 ms median and 51.2 ms p95. The repair build took 22.1 ms median and 54.3 ms p95. Every run exited 4 with `output_not_mp4` and wrote no file. Argument parsing and output validation already precede `AppleEncoder.isAvailable`, so the bad name exits without probing. No production code changed.
  - `scripts/check.sh` passed twice consecutively (0, 0). Both runs passed the package suite, both Xcode test targets, the universal build and signature checks, the bundled command and the site checks. Both passed the original progress beat limits. The JSON beat test timestamps pipe reads, so host scheduling can extend a measured gap even when the producer emits on schedule. The quiet-period test checks the reported elapsed time against 0.15 s if checking progress appears.
  - Runtime checks ran on Apple silicon. The gate built and signature-checked the Intel slice. Intel runtime and Windows checks were outside this repair.
