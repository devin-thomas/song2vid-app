# Tool contract: song2vid 1.2

The interface between the bundled command, `song2vid.exe`, and the app's adapter (`electron/tool/`). It is a seam file written before any builder starts, with `src/bridge.ts` and `docs/BRIDGE.md`. Neither side changes it alone: a change is a lead decision recorded in `docs/DECISIONS.md`.

**The contract is the repository's `SPEC.md`, not a copy of it here** (ADR-024): section 14 (`check`, `make`, the options, `--json` lines, exit statuses and error codes), section 24 (`--codec`, `encoders`, `preview`, `--cancel-on-eof`, the added keys and codes) and section 26 (how the Windows command behaves). The starter's example contract (`--capabilities`, `--events 1`, `--stdin-control`) is not used: the starter's adapter, its stand-in tool and its scenarios are rewritten against SPEC 14 and 24 by S2V-029.

## What the adapter relies on

| Need | Where it is decided |
| --- | --- |
| Run `song2vid.exe --json --cancel-on-eof` with every path absolute, by absolute path, never PATH | SPEC 26.1, 27.6 |
| Read the JSON lines: every line has `"api_version":"1"` and a `type`; ignore unknown keys and types; exactly one final `result` or `error` line | SPEC 14.5, 24.5 |
| A non-JSON line, a line over 1 MiB, or an exit without exactly one final line ends the job as `export_failed`, after the rest of the output is drained | SPEC 27.6 |
| Launch checks: `--version --json` must say `song2vid 1.2.0` (any other answer is the wrong version); `encoders --json` is cached by the binaries' size and modified time and refreshed in the background every launch | SPEC 24.7, 27.6 |
| Cancel by closing stdin, kill the process 3 s later; never kill a job for being silent; "Still working…" after 30 s with no line | SPEC 24.4, 27.6 |
| Record the job before it starts; the next launch removes a leftover `.song2vid-<32 hex>.tmp` directly in the recorded output folder and nothing else | SPEC 26.3, 27.6 |
| Exit statuses and error codes | SPEC 14.6, 24.6 |
| Which Encoder and fallback | SPEC 23, 24.5 |

## The stand-in

`test/standin-tool.ts` replays recorded SPEC 14 and 24 lines from `test/scenarios/` so the adapter is tested on every system without FFmpeg (SPEC 27.6, 31): success, slow success, each error code, an unknown code, a crash with no final line, garbage, a 2 MiB line, 10 MB of noise, silence mid-job, a cancel ignored, and the wrong version. S2V-029 writes them.
