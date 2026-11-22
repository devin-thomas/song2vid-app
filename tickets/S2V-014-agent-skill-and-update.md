# S2V-014 - Agent skill, `--skill` and `--update`

Status: resolved
Blocked by: S2V-013

## Goal

An agent that has never seen Song2Vid can make a video by either route from one set of instructions (SPEC §15, §14.7).

## Scope

- Write `skills/song2vid/SKILL.md` using `.claude/skills/writing-for-agents` (read its `SKILL-MECHANICS.md`). Steps first; reference (options, JSON keys, exit codes) disclosed or tabled.
- Cover both routes: the app's window by its VoiceOver labels, and the command. Include the agent rules in SPEC §15.
- Bundle it in the app; `-S/--skill` prints it.
- `-u/--update` per SPEC §14.7, with `--json`. Tests use a local stub for the release lookup, not the network.

## Acceptance Criteria

- `song2vid --skill` output matches `skills/song2vid/SKILL.md` byte for byte.
- The coordinator gives the skill alone to a fresh Sonnet subagent with no repo access and the installed command on PATH; it makes a correct 480p 1:1 video from generated media and reports a deliberate failure's exit status and code correctly. Record its transcript summary.
- `--update` reports up to date, newer available, and `network` (exit 5) against the stub.

## Dependencies

S2V-013.

## Comments

- 2026-11-22: Built on `ticket/S2V-014` from `build/v2` after S2V-013. `skills/song2vid/SKILL.md` is written with `writing-for-agents`: rules first, then the command route as numbered steps that each end on a completion criterion, an options table, the JSON keys, an error table with what to do for each, and the app-window route by its control labels. The app copies it to `Contents/Resources/SKILL.md` in a Copy Files build phase, and `--skill` / `-S` prints that file (found through a link on the PATH too). `scripts/check.sh` fails if the printed text differs from the repo file.
- `--update` / `-u` (with `--json`) asks the GitHub releases API for `tag_name`, compares dotted versions as numbers and says whether a newer one exists; it downloads and installs nothing. The lookup address is GitHub's, unless `SONG2VID_UPDATE_URL` names a `file:` or `localhost` address, so tests use a stub and nothing else can be asked. No answer, or an answer that is not a release, is exit 5, code `network`. `--json` is now valid on its own only with `--update`.
- Verified by tests: `--skill` and `-S` match the file byte for byte, also through a symbolic link; the skill names every option, the error codes and both routes; `--update` up to date, newer and offline, as text and JSON, with stderr empty under `--json`; version ordering ("1.10.0" after "1.9.0"); the lookup address rules.
- Fresh-agent test (acceptance criterion 2): a Sonnet subagent was given only the skill file and the command on its PATH, with generated media (a 12 s tone and an 800×600 picture). It linked nothing (the command was already found), ran `check` and `make -s 1:1 -r 480p --json`, and reported `square.mp4`, 480×480, 12.0 s, 426610 bytes, `enlarged` false. ffprobe confirmed 480×480 H.264 and AAC at 12.000 s, and the byte count matches the file. For a missing image it reported exit status 1 and `image_not_found` as printed. It did not invent values. Its notes changed the skill: the percent scale (0 to 100) is stated, the output folder must exist, `check` is described as quick and safe, and background running is advised for long songs. Not re-run after those wording changes.
- Not checked: `--update` against the real GitHub API (the release does not exist until S2V-017; the answer shape is the documented `tag_name`).
