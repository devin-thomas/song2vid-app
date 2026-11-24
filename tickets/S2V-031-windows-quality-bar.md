# S2V-031 - Windows app: real-shell checks, critic round and the ledger

Status: open
Blocked by: S2V-030

## Goal

The quality bar of SPEC §28 is run and recorded: real-shell checks on the DeskMini, one critic round, memory, and a complete ledger.

## Scope

- On the DeskMini: `pnpm qa:crash`, `pnpm shell:evidence`, `pnpm measure:focus -- --first explorer --route explorer`, memory after 5 idle minutes and during a 2160p HEVC job.
- `pnpm qa:shots`; screenshots alone to a critic that did not build the app; fix every must-fix finding and turn each class into an audit gate where the starter allows.
- `pnpm qa:planted` for the rules it covers.
- Fill every ledger row with its check and verdict.

## Acceptance Criteria

- Every scripted gate in SPEC §28 passes; `qa:planted` catches every planted break it runs.
- The critic's must-fix list is empty after the fixes, and the critique and fixes are recorded.
- Memory: under 300 MB after 5 idle minutes, under 680 MB during the job, counting `song2vid.exe` and FFmpeg.
- The focus experiment shows no Song2Vid window in front.
- Every ledger row says applies (with verdict) or N/A (with reason); the unverified rows are listed for the release notes.
- Rule 77 ledger row: `electron/tool/locate.ts` reads `process.platform` as a default (from the starter, overridable for tests); decide whether it passes and note it in SKILL-NOTES if not.

## Dependencies

S2V-030.

## Comments
