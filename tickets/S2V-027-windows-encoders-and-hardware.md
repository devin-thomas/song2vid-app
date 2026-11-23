# S2V-027 - Windows: hardware encoders, HEVC and `encoders`

Status: open
Blocked by: S2V-026

## Goal

`song2vid.exe` uses NVENC, then Media Foundation hardware, then software, makes HEVC where hardware allows, and reports it (SPEC §23, §24.2, §26.3).

## Scope

- `encoders` with the 5 s limit; the Encoder order and the one-time fallback before the first frame; `-C hevc`; `encoder`, `encoder_fallback` and progress `encoder` keys; the human result line.
- `SONG2VID_TEST_ENCODER` test seam (not documented publicly).
- Runs on Titan (NVENC) and on the DeskMini (AMD through Media Foundation) once its SSH server answers.

## Acceptance Criteria

- Titan: `encoders` gives `nvenc` for both Codecs; a 3-minute song makes 1080p H.264 and 2160p HEVC in under 30 s each; the same with `software` forced is recorded for comparison.
- DeskMini: `encoders` gives `media_foundation` for both Codecs; each Frame Shape at 1080p in each Codec passes the S2V-026 media checks; HEVC files carry `hvc1`.
- With `software` forced, `encoders` reports HEVC unavailable and `make -C hevc` gives 3 / `codec_unavailable` before writing anything.
- A hardware encoder made to fail at start falls back once and the result has `"encoder_fallback": true`.
- Peak private memory of `song2vid.exe` plus children during a 2160p HEVC job is under 680 MB.

## Dependencies

S2V-026.

## Comments
