# S2V-023 - Mac: the Codec picker

Status: resolved
Blocked by: S2V-022

## Goal

The Mac window has a remembered Codec picker (SPEC §25), and the Mac command gains one-file `check` (SPEC §24.8).

## Scope

- A Codec picker under Resolution, for every Frame Shape, disabled while making.
- Remembered in UserDefaults; H.264 on first run; HEVC disabled with "This computer can't make HEVC videos." when unavailable, keeping the remembered choice.
- The done state and VoiceOver labels name the Codec; the Agent Guide's window route lists the picker (text change only; publishing is S2V-033).

## Acceptance Criteria

- Choosing HEVC, quitting and relaunching starts on HEVC; a fresh defaults domain starts on H.264.
- A video made from the window with HEVC passes the S2V-022 ffprobe checks.
- The picker is reachable and operable by keyboard and named for VoiceOver; the app's existing tests pass.
- Mac command: one-file `check` (SPEC §24.8), with a process test for an audio file alone, an image alone and an unreadable file alone.

## Dependencies

S2V-022.

## Comments
- 2026-11-23 (builder): Built the Mac Codec picker and one-file `check`. Checks, all at `ad622f4`:
  - `scripts/check.sh` passed (0) as the last step: public-safety scan, the package suite, both Xcode test targets on arm64 (140 integration tests in 16 suites, and the app target's 1), the universal build with both slices ad-hoc signed, the bundled command (1.2.0, `--skill` matches), and the site checks. Two earlier gate runs failed (65) on my own new text test, which expected "125 seconds" where the command prints "125.0 seconds" (fixed in the test), and (1) on `site/docs.md` being stale because I had edited the generated file instead of `site/docs/index.html` (fixed, regenerated with `python3 -I scripts/build-site.py`). No timing assertion was loosened. One package `swift test` run on the first build reported a failure in `Song2VidCoreTests` that I could not see (the tail of the output only named the target); ten reruns afterwards all passed (0) and the gate's package run passed each time, so it is unexplained and not reproduced. The shared Mac was at 98% disk during the work, and the log prints "No space left on device" once per Xcode run from `xctest` in the runs that passed, from the disk-full export test.
  - Window: `MainWindowModel` gains `codec` (remembered in UserDefaults under `videoCodec` through `CodecPreference`, H.264 on a fresh domain or an unrecognised value), `canMakeHEVC`, `codecPickerEnabled`, `codecNote` ("This computer can't make HEVC videos.") and `savedCodecMessage` ("Made as HEVC."). The Codec goes into the `ExportRequest`. When HEVC is remembered but unavailable the window starts on H.264 and the stored value stays `hevc`; choosing H.264 there does not overwrite it, and the model refuses to select HEVC. Availability comes from `CodecSupport`, which asks `AppleEncoder.isAvailable` once, so the `SONG2VID_TEST_DISABLE_HEVC` seam also applies to the app. `ContentView` has a Codec row under Resolution for every Frame Shape (Original included), disabled while making and, when HEVC is unavailable, disabled as a whole with the note under it (H.264 is then the only choice). The done state keeps "Video saved." and adds "Made as H.264." or "Made as HEVC." beside it. The window's minimum height is 580 (was 540) for the extra row.
  - Agent Guide window route (`skills/song2vid/SKILL.md`, copied to `site/agent.md`) lists the Codec picker, the greyed-out case and the "Made as" line; the docs source `site/docs/index.html` (and generated `site/docs.md`) lists one-file `check` and the picker. Publishing is S2V-033.
  - One-file `check` (SPEC 24.8): `song2vid check <file> [-j]`. The kind comes from the contents: the audio reader first, then the image reader. Audio gives the `audio` keys only, an image gives `image` and `frames`; two-file output is unchanged (the existing two-file tests pass untouched). A file that is neither gives `audio_unreadable` if its extension is a section 7 audio type, else `image_unreadable`. SPEC 24.8 says nothing about a file that does not exist, so I chose the same extension rule: `audio_not_found` or `image_not_found`, status 1. S2V-025 must match this: no extension is image, and a folder is unreadable by the same rule. The usage message for 0 or 3+ files is now "check needs one audio file and one image file, or a single file."; `--help` for `check` and the global help show the one-file form.
  - Tests added: `MainWindowCodecTests` (17 tests in the package: remembered across a new model on the same defaults, fresh domain, unrecognised stored values, every Frame Shape, unavailable HEVC with the note and the kept choice, locked while making, the Codec reaching the export, the done state); `WindowCodecExportTests` (the window model with the real readers and exporter, H.264 and HEVC, `hvc1`, AAC, length within 0.1 s, the next window starting on HEVC, a fresh domain on H.264); `CommandCheckOneFileTests` (process tests: an audio file alone, an image alone with the SPEC 5 table, orientation, contents beating the extension, an unreadable file alone for song and image names, no extension, a folder, missing files, JSON and text, no folder path or content in any output, two-file check still two-file). The old "one operand is a usage error" case in `CommandCheckErrorTests` became a not-found case; the leak test now also runs the one-file forms.
  - `ffprobe` on the video the window model made with HEVC (854x480, 2.37 s): `hevc`, tag `hvc1`, Main, `yuv420p`, BT.709 primaries, transfer and matrix, 30/1, `aac` LC 44100 Hz 2 channels; `ffmpeg -v error -xerror -i <file> -f null -` decoded it (0). The H.264 one from the same window: `h264`, `avc1`, High, BT.709. `ffprobe -show_streams -show_format -of json` and the `-show_packets` keyframe query exited 0 for both.
  - Not checked: the live window. I did not open it or drive the picker on the owner's screen, so "reachable and operable by keyboard" and "named for VoiceOver" are checked in code only: the picker is a segmented `Picker` like the Frame Shape and Resolution pickers, with `.accessibilityLabel("Codec")` and a hint (the unavailable note when HEVC is missing), and the row's `Text` label. Whether SwiftUI honours `.disabled` on the single HEVC segment was not tested, which is why the whole picker is disabled and the model refuses HEVC when it is unavailable. Pixel layout at the new minimum height was not seen. The disabled-with-note state is checked through the model and the `SONG2VID_TEST_DISABLE_HEVC` seam only. Intel runtime was not checked (the gate builds the slice).
