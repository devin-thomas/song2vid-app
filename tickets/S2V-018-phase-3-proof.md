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
