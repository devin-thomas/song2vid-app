# S2V-018 - Phase 3 proof with a real agent

Status: resolved
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

- 2026-11-22 (coordinator): The proof was run by the "Claude CLI smoke test" session, which the owner set up and gave this plan: a fresh Claude Code run (Haiku 5.5, `-p` mode, tools limited to Bash and WebFetch, only `song2vid`, `ls`, `ffprobe` and WebFetch allowed), working in a folder outside this repo on a generated 12-second tone and an 800×600 cover. The agent linked the command from the installed 1.1.0 app and reported: `--version` `song2vid 1.1.0`; `check` 12.0 s, 44100 Hz, 2 channels, image 800×600; `make` 1:1 480p `square.mp4` 480×480, 12.0 s, 426610 bytes, placement `crop`, enlarged false; a `make` with a missing image exit 1 and `image_not_found`. The coordinator then checked it against the real files and a rerun of the command: every value matches; `ffprobe` shows H.264 480×480 plus AAC 44100 Hz stereo, 12.000 s, 426610 bytes; a full decode is clean; the failing `make` exits 1 with the same error line and leaves no file.
- What the run was, plainly: the agent read `agent.md` through WebFetch, which returns a summary, so it worked from a summary of the skill and the command's own `--help` and output; the owner set up the second session and gave it this plan; one earlier attempt failed in 2 seconds with "Credit balance is too low" before any command ran (a rerun with the inherited Claude and Anthropic environment variables removed succeeded). A successful run from a summary is a stronger result than one from the full text, not a weaker one.
- 2026-11-22 (owner): Confirmed in chat that this proof passes, and that programmatic proof by several agents, checked by a higher model, is better than a manual one. The coordinator recorded the `agent-cli` verification and Phase 3 completion in the private progress repository (commit `ca90bf9`). Resolved.
