# S2V-029 - Windows app: the adapter for the song2vid contract

Status: resolved
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
- 2026-11-23 (builder): Rewrote the starter's tool adapter in `windows/app/electron/tool/` for the Song2Vid contract (SPEC 14, 24 including 24.8, 27.6) and tested it against a stand-in tool that replays section 14 and 24 lines.
  - Built: `contract.ts` (argument lists, readers, the `.song2vid-<32 hex>.tmp` pattern, error codes with exit statuses), `adapter.ts` (`--version`, `encoders --json`, one-file `check`, `preview`, `make`; `--json`, and `--cancel-on-eof` on `make` and `preview`; faults end the job as `export_failed` with the adapter's fault name in `details`; 3 s grace; 30 s stall report, never a kill), `progress.ts`, `status.ts` (the answers cached by size and modified time, refreshed on every launch), `jobs.ts` (the record names the output folder; leftovers removed), and two new files, `files.ts` (opaque ids, a drop's judgement) and `service.ts` (what each bridge call does, with the dialogs as an interface). `index.ts` is the Electron glue: the open and save dialogs (none under `--no-activate`), the channels `file:choose-audio`, `file:choose-image`, `file:drop`, `file:release`, `file:preview`, `job:make`, `job:cancel`, `job:show-in-folder`, the events `job:update`, `tool:encoders`, `file:opened`, and the quit question. The page screens are not touched (S2V-030). Decisions are D-024 in `windows/app/docs/DECISIONS.md`; BRIDGE.md, TOOL-CONTRACT.md and `windows/SKILL-NOTES.md` list every change to a starter file.
  - Stand-in scenarios in `test/scenarios/` (41 files): version (ok, ok without `--json`, wrong, garbage, silent), encoders (ok, no HEVC, a newer Encoder name, garbage), check (audio, image, tiny image, error, wrong kind, garbage, silent), preview (ok, slow, error), and for `make` success, slow success, a fallback, unknown keys and types, every error code of SPEC 14.6 and 24.6 (one file with variables) and an unknown code, a crash with no final line, a silent exit, garbage, a 2 MiB line, 10 MB of noise (with and without newlines), silence mid-job, a cancel ignored, two final lines, a line after the final one, no or another `api_version`, a result without keys, a result with exit 1 and a result with no Encoder.
  - Checks, on this Mac (Node 24.22.3, pnpm 11.9.0, Node's runner at concurrency 1): `pnpm install --frozen-lockfile` (0), `pnpm tokens` (0), `pnpm test` (0; 128 pass, 0 fail, 0 skipped; three clean runs at the final tree. One earlier run failed once: a cancel test gave the tool 500 ms to stop on a busy machine and it was killed instead; the two cancel tests now allow 2.5 s, as SPEC 24.4's 2 s needs), `pnpm shell:check` (0), `pnpm build` (0), `tsc --noEmit` for `tsconfig.node.json` (0) and `qa/tsconfig.json` (0), `tsc --noEmit -p tsconfig.json` (1; 18 errors, the same 18 as after S2V-028, all in `src/App.tsx`, `src/state/job.ts`, `src/components/StatusBar.tsx`, `src/components/TitleBar.tsx` and `src/bridge.fake.ts`, which D-022 leaves red until S2V-030), `scripts/safety-scan.sh` (0). `pnpm qa:audit` was not run: it stays red until S2V-030 (D-022).
  - On Titan (Windows, Node 24.22.2, headless, a copy of `windows/app` in a scratch folder under the profile): `pnpm install --frozen-lockfile` (0), `pnpm tokens` (0), `pnpm test` (0; 128 pass, 0 fail, 57 s), including the host-kill test and the Windows behaviour it asserts (the tool dies with the host, leaves its `.song2vid-<32 hex>.tmp`, and the next launch removes it). The first Titan run failed twice: macOS tar metadata files (`._*.ts`, my copy, not the repository) broke the parse test, and the sandbox folder could not be removed while a background check still had it as its working folder (EPERM, fixed in `test/helpers.ts` with retries). The second run, with a clean copy, passed (before the cancel tests' grace period was raised; not rerun on Titan after it, as nothing else changed).
  - Acceptance: `pnpm test` passes including the host-kill test; every scenario ends in its designed state with no stand-in process left (`adapter.test.ts`, `service.test.ts`); cancel is observed 3 s after stdin closes for an ignored cancel (the default grace, asserted between 2.9 s and 6 s) and within 2 s for a tool that honours it; a leftover `.song2vid-<32 hex>.tmp` in a recorded folder is removed at the next launch and a lookalike name, a folder of that name, a nested file, or a folder with no record is never touched (`units.test.ts`, `service.test.ts`); every change to a starter file is in `windows/SKILL-NOTES.md`. "Cancel shows on the next frame" is the page's own behaviour (BRIDGE.md); the shell closes stdin in the same tick as `cancelJob`.
  - Not checked: the real `song2vid.exe` (S2V-025/026 do not exist yet), so the stand-in's lines are the SPEC's, not recordings; the Electron glue in `electron/tool/index.ts` (dialogs, channels, quit question) was built and parsed by `pnpm shell:check` and `pnpm build` but never run, because nothing opens a window here; no named-pipe or window behaviour on the DeskMini.
  - Open points: (1) SPEC 27.6 says `--version --json` but SPEC 14.2 lists `--json` only for check, make and `--update`, and the Mac command refuses `--version --json`; the adapter asks both ways and S2V-025 or SPEC 27.6 should settle one (D-024). (2) The tool names its temporary file in no line, so the record holds the output folder only. (3) `app:preferences`, `app:open-link`, `app:notices`, `Bootstrap.preferences` and the second-launch hand-off are not tool calls and are listed for S2V-030 in BRIDGE.md. (4) `scripts/installed-helpers.ts` and `tool/placeholder/` still speak `--capabilities` (S2V-032).
