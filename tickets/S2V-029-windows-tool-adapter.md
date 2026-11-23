# S2V-029 - Windows app: the adapter for the song2vid contract

Status: open
Blocked by: S2V-022, S2V-028

## Goal

The starter's tool adapter speaks SPEC §14 and §24 instead of `--events 1`, and is tested against a stand-in tool (SPEC §27.6).

## Scope

- `electron/tool/contract.ts`, `adapter.ts`, `progress.ts`, `status.ts`, `jobs.ts` rewritten for `--json --cancel-on-eof`; launch-time `--version --json` and `encoders --json`, cached by size and time, refreshed in the background.
- Stand-in tool scenarios in `test/scenarios/` replaying section 14/24 lines: success, slow success, each error code, an unknown code, a crash with no final line, garbage, a 2 MiB line, 10 MB of noise, silence mid-job, a cancel ignored, the wrong version.
- Job records and launch reconciliation of `.song2vid-*.tmp` files.

## Acceptance Criteria

- `pnpm test` passes, including the host-kill test with the stand-in tool, and every scenario ends in the designed state with no stand-in process left.
- Cancel shows on the next frame; the process is killed 3 s after stdin closes if it ignores it.
- A leftover `.song2vid-<32 hex>.tmp` in a recorded folder is removed at the next launch; a file not matching the pattern, or outside the recorded folder, is never touched.
- Every change to starter files is in `SKILL-NOTES.md`.

## Dependencies

S2V-022, S2V-028.

## Comments
