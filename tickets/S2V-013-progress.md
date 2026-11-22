# S2V-013 - Progress that is always visible, headed and headless

Status: resolved
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

## Comments

- 2026-11-22: Built on `ticket/S2V-013` from `build/v2`. `ProgressDisplay` (`CommandProgressDisplay.swift`) takes the stage and fraction the relay already delivers and writes them on a timer, so the output keeps moving while the exporter has nothing new to say. `ProgressSnapshot` is the pure part (live line, plain line, JSON line), covered by unit tests with the text written out by hand. The relay now delivers to a `ProgressSink`; a caller's own handler is one kind of sink, so the hook from S2V-012 still works.
- Beat: 0.08 s live, 0.25 s JSON, 1 s plain. Choices the spec left open, now in SPEC 14.5: `Checking files` is shown only if it lasts past 0.15 s, so a run that fails at once shows only its error; every later stage shows the moment it begins; the percent shown never goes down; time left appears after one second of encoding; at the end the live line is wiped before the result prints.
- Seam 5 tests run the built command: `--json` with a one-hour silent song (first line within 0.5 s, no gap over 0.6 s, percent never goes back, one `result` last, stderr empty); a mid-run read of the latest stage and percent; headless plain (no escape or carriage-return characters, no gap over 2.1 s); a pseudo-terminal run (at least 10 redraws a second, a moving spinner during Preparing, bar, percent, elapsed and "estimating" then "about m:ss left", colour by default, `NO_COLOR` without colour, `TERM=dumb` with no escape codes at all, the line wiped at the end); `-q`; and a quick failure that shows no progress. Older `make` tests were updated for the progress lines that now come before the result.
- By eye on this Mac with a real 2:34 song and image at 2160p, run under a pseudo-terminal: 51 redraws in 3.8 s (13.5 a second), a moving spinner on `Preparing` for the whole run, no `Encoding` frames because the exporter's frame writing at that size takes a fraction of a second after a 3.6 s preparation. The output was a valid 3840×2160 H.264 plus AAC file.
- Not checked: Terminal.app or iTerm drawing the line with a human watching, very narrow windows by eye (the width logic is unit tested), and Intel.
