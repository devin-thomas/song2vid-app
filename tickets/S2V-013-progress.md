# S2V-013 - Progress that is always visible, headed and headless

Status: ready-for-agent
Blocked by: S2V-012

## Goal

Nobody waiting on `make` ever wonders whether it is working (ADR-018, ADR-019, SPEC §14.5).

## Scope

- Headed: the live one-line display with stage, spinner or bar, percent, elapsed and time left, at least 10 redraws a second; `NO_COLOR` and `TERM=dumb` respected; `-q` silences it.
- Headless plain: a line at each stage change and at least every 2 s, no control characters.
- `--json`: JSON Lines on stdout, progress at least every 0.5 s and at each stage change, then exactly one final line; stderr empty.
- Real progress from the exporter, including the Preparing stage before encoding starts.

## Acceptance Criteria

- A test runs `make --json` on a song long enough to take several seconds: every line parses, the first line arrives within 0.5 s, no gap between lines exceeds 0.6 s, percent never decreases, and the last line is the only `result`.
- A test runs headless plain and checks for no escape characters and no gap over 2.1 s.
- A pseudo-terminal test sees the redraws; the coordinator checks the headed display by eye on this Mac with a 2160p export, including the spinner during Preparing.
- A background run's output can be read mid-run and shows the latest stage and percent.

## Dependencies

S2V-012.
