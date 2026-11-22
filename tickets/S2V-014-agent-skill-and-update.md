# S2V-014 - Agent skill, `--skill` and `--update`

Status: ready-for-agent
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
