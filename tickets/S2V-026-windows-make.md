# S2V-026 - Windows: `song2vid make` with the software encoder

Status: open
Blocked by: S2V-025

## Goal

`song2vid.exe make` produces correct H.264 videos with the software encoder, with publication, cancel and progress exactly as the contract says (SPEC §14.4, §14.5, §24.4, §26.3).

## Scope

- Validation before encoding; `--dry-run`; temporary file and one-step publication (`MoveFileExW` without replace; with `-w`, replace with 2 s retry then `output_in_use`).
- Encoding through FFmpeg with the Media Foundation software H.264 encoder and FFmpeg's `aac`, section 6.3's audio rules; the repeated-group approach of SPEC §26.3 if needed for speed.
- Cancel by Ctrl-C/Ctrl-Break and `--cancel-on-eof`; exit 130.
- Headed, plain and `--json` progress with the S2V-013 timings; virtual terminal sequences turned on or plain lines used.

## Acceptance Criteria

- Each Frame Shape at 480p and one at 2160p: correct size, length within 0.1 s, H.264 High, BT.709 tags, AAC 256 kbps; the input files unchanged.
- Parity with the Mac command for the five SPEC §31 inputs: midpoint SSIM at least 0.95.
- Existing output: 4 / `output_exists` without `-w`; replaced with `-w`; held open by another process, 4 / `output_in_use` and unchanged.
- Killing `song2vid.exe` mid-job leaves no `ffmpeg.exe` after 2 s; `--cancel-on-eof` cancels within 2 s with no file left; the next run is unaffected.
- JSON Lines: every line parses, progress at least every 0.5 s, exactly one final line; plain lines contain no control characters.

## Dependencies

S2V-025.

## Comments
