# S2V-022 - Mac: HEVC and the 1.2 command contract

Status: open
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
