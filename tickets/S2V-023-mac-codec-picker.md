# S2V-023 - Mac: the Codec picker

Status: open
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
