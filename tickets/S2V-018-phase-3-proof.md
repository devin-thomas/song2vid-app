# S2V-018 - Phase 3 proof with a real agent

Status: ready-for-human
Blocked by: S2V-017

## Goal

A real agent that has never seen this project uses the installed command correctly, and the owner confirms it (SPEC §18, Starter Pack `agent-cli`).

## Scope

- The owner opens a new Claude Code session outside this repo with the command installed, and gives it the prompt the coordinator prepares (one `check --json`, one `make --json` to a 480p 1:1 video, one `make` with a missing image).
- The coordinator checks the reported values against the real output.

## Acceptance Criteria

- The agent reports the real values, and exit status 1 with `image_not_found` for the failure, without inventing results.
- The owner confirms. The progress record's `agent-cli` step gets the short verification object the Starter Pack asks for.

## Dependencies

S2V-017.

## Comments

- 2026-11-22 (coordinator): The proof was run by the "Claude CLI smoke test" session on the owner's behalf: a fresh Claude Code run (Haiku 5.5, `-p` mode, tools limited to Bash and WebFetch, only `song2vid`, `ls`, `ffprobe` and WebFetch allowed), working in a folder outside this repo on a generated 12-second tone and an 800×600 cover. The agent linked the command from the installed 1.1.0 app and reported: `--version` `song2vid 1.1.0`; `check` 12.0 s, 44100 Hz, 2 channels, image 800×600; `make` 1:1 480p `square.mp4` 480×480, 12.0 s, 426610 bytes, placement `crop`, enlarged false; a `make` with a missing image exit 1 and `image_not_found`. The coordinator then checked it against the real files and a rerun of the command: every value matches; `ffprobe` shows H.264 480×480 plus AAC 44100 Hz stereo, 12.000 s, 426610 bytes; a full decode is clean; the failing `make` exits 1 with the same error line and leaves no file.
- What this does not show: the agent read `agent.md` through WebFetch, which returns a summary, so it worked from a summary of the skill and not its verbatim text; the files were made and the permissions set by another session, not by the owner; one earlier attempt failed in 2 seconds with "Credit balance is too low" before any command ran (the cause was not found; a rerun with the inherited Claude and Anthropic environment variables removed succeeded). It also was not the exact owner-run session described in `docs/wiki/phase-3-proof.md`.
- Still open: the owner's confirmation, and then the short verification object on the Starter Pack progress record's `agent-cli` step. Status stays `ready-for-human`.
