# Tool contract: song2vid 1.2

The interface between the bundled command, `song2vid.exe`, and the app's adapter (`electron/tool/`). It is a seam file written before any builder starts, with `src/bridge.ts` and `docs/BRIDGE.md`. Neither side changes it alone: a change is a lead decision recorded in `docs/DECISIONS.md`.

**The contract is the repository's `SPEC.md`, not a copy of it here** (ADR-024): section 14 (`check`, `make`, the options, `--json` lines, exit statuses and error codes), section 24 (`--codec`, `encoders`, `preview`, `--cancel-on-eof`, the added keys and codes) and section 26 (how the Windows command behaves). The starter's example contract (`--capabilities`, `--events 1`, `--stdin-control`) is not used: the starter's adapter, its stand-in tool and its scenarios are rewritten against SPEC 14 and 24 by S2V-029.

## What the adapter relies on

| Need | Where it is decided |
| --- | --- |
| Run `song2vid.exe` by absolute path, never PATH, every file path absolute. `make` and `preview` take `--json --cancel-on-eof`; `check` and `encoders` take `--json` | SPEC 26.1, 27.6, D-024 |
| Read the JSON lines: every line has `"api_version":"1"` and a `type`; ignore unknown keys and types; exactly one final `result` or `error` line | SPEC 14.5, 24.5 |
| A non-JSON line, a line over 1 MiB, or an exit without exactly one final line ends the job as `export_failed`, after the rest of the output is drained and the tool stopped | SPEC 27.6 |
| Launch checks: `--version --json` must say `song2vid 1.2.0` (any other answer is the wrong version); `encoders --json` is cached by the binaries' size and modified time and refreshed in the background every launch | SPEC 24.7, 27.6, D-024 |
| One file's facts: `check <file> --json` for a chosen or dropped song or image; the type is taken from the file's contents | SPEC 24.8 |
| The picture the video will see: `preview <image> --out <file.png> --overwrite --json --cancel-on-eof` | SPEC 24.3 |
| Cancel by closing stdin, kill the process 3 s later; never kill a job for being silent; "Still working…" after 30 s with no line | SPEC 24.4, 27.6 |
| Record the job before it starts; the next launch removes a leftover `.song2vid-<32 hex>.tmp` directly in the recorded output folder and nothing else | SPEC 26.3, 27.6, D-024 |
| Exit statuses and error codes | SPEC 14.6, 24.6 |
| Which Encoder and fallback | SPEC 23, 24.5 |

## Where it is in the code

| File | What it holds |
| --- | --- |
| `electron/tool/contract.ts` | The argument lists, the readers of each answer, the temporary file's name pattern, the error codes with their exit statuses. Pure |
| `electron/tool/adapter.ts` | Starting the tool, reading its lines, the faults, the limits, cancel. No Electron |
| `electron/tool/progress.ts`, `status.ts`, `jobs.ts`, `files.ts` | The progress numbers, the launch answers and their cache, the job records and the removal of leftovers, the file ids and a drop's judgement. Pure |
| `electron/tool/service.ts` | What each call in `src/bridge.ts` does (choose, drop, preview, make, cancel, launch). Takes the dialogs as a small interface; no Electron |
| `electron/tool/index.ts` | The Windows dialogs, the window, the IPC channels and the quit question. The only file here that imports Electron |

## The stand-in

`test/standin-tool.ts` replays SPEC 14 and 24 lines from `test/scenarios/` so the adapter is tested on every system without FFmpeg (SPEC 27.6, 31). It takes the command's own arguments (`--version`, `check`, `make`, `preview`, `encoders` and their options), reads stdin only with `--cancel-on-eof`, honours a cancel (removes its temporary file, writes `cancelled`, exits 130) unless the scenario says `"cancel": "ignore"`, and logs each start and each cancel request for the tests. The scenario for each kind of call is chosen in its configuration (`make`, `check_audio`, `check_image`, `preview`, `encoders`, `version`); `vars` fill `${...}` in a scenario, so one file serves every error code. The header of the file lists the steps a scenario may use.

Scenarios: `version-ok`, `version-ok-without-json`, `version-wrong`, `version-garbage`, `version-silent`; `encoders-ok`, `encoders-no-hevc`, `encoders-newer-encoder`, `encoders-garbage`; `check-audio-ok`, `check-image-ok`, `check-image-tiny`, `check-error`, `check-wrong-kind`, `check-garbage`, `check-silent`; `preview-ok`, `preview-slow`, `preview-error`; and for `make`: `make-ok`, `make-slow`, `make-fallback`, `make-unknown-keys`, `make-error` (with `code`, `message`, `exit` for each error code, and an unknown one), `make-error-after-encoding`, `make-crash`, `make-silent-end`, `make-garbage`, `make-line-2mib`, `make-noise-10mb`, `make-noise-10mb-lines`, `make-silence-mid-job`, `make-cancel-ignored`, `make-two-finals`, `make-line-after-final`, `make-no-api-version`, `make-other-api-version`, `make-result-missing-keys`, `make-result-exit-1`, `make-result-no-encoder`.

In development, `STANDIN_TOOL=<path to test/standin-tool.ts>` (and `STANDIN_CONFIG=<file>`) runs the shell against it in place of a built tool. It is never honoured in a packaged app.
