# S2V-010 - The command ships inside the app and runs after download

Status: ready-for-agent
Blocked by: none

## Goal

Prove the riskiest part first: a `song2vid` command built into Song2Vid.app runs from Terminal after the app is downloaded and approved with Open Anyway (SPEC §14.1, ADR-013).

## Scope

- A command-line target that links `Song2VidCore`, built universal and placed at `Song2Vid.app/Contents/Helpers/song2vid`.
- Signing: the command ad hoc without the sandbox; the app keeps the sandbox and drops `get-task-allow`. Sign the command before the app.
- Global options only: `-h/--help`, `-v/--version`, `-R/--repo`; unknown options give exit 2 without echoing (SPEC §14.2, §14.6). Subcommands come in later tickets.
- `scripts/check.sh` builds and tests the command.

## Acceptance Criteria

- `codesign -d --entitlements` shows the app with the sandbox and without `get-task-allow`, and the command without the sandbox.
- A release-style zip, downloaded through a browser so it has the quarantine flag, unzipped into a clean folder outside the repo and approved with Open Anyway: the linked command prints `song2vid 1.1.0` and exits 0. Record exactly what macOS asked, with screenshots. If macOS blocks the command, stop and report the options to the coordinator before changing anything.
- The app still opens, makes a video and saves inside the sandbox.
- Tests run the built binary as a separate process (seam 5).

## Dependencies

None.
