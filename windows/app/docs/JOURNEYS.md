# Journeys, budgets and the use gate

This is Song2Vid for Windows' page, written before any component was chosen (SPEC 28, process steps 1 and 10). The audit and the measurement scripts read the numbers from `qa/journeys.json` and `app.config.json`; this page says what they mean and holds what a script cannot.

## Essential journeys

Four things a person comes to Song2Vid to do (SPEC 28, process step 1), each as one sentence and a step budget. They are in `qa/journeys.json`; each needs a script in `qa/audit.ts` (S2V-030 writes them against the screens).

| Id | Journey | Step budget | Why this many |
| --- | --- | --- | --- |
| choose-and-make | Choose a song and an image, make the video and see that it was saved | 3 | Ctrl+O, Ctrl+Shift+O, Ctrl+Enter. Each opens a system dialog, whose pick and confirmation is part of that one step |
| drop-and-make | Drop a song and an image on the window, make the video and see that it was saved | 2 | The drop, then Ctrl+Enter. The drop is the one step no key can make: the script sends it through the stand-in bridge as the page receives a real one. The keyboard route to the same result is choose-and-make |
| crop-square | Choose a song and an image, switch to 1:1, move the crop, make the video | 10 | Ctrl+O, Ctrl+Shift+O, Tab to Frame Shape, Right twice (9:16, then 1:1), Tab to Resolution, Tab to Codec, Tab to Crop position, one arrow key (a 5% nudge), Ctrl+Enter |
| hevc-remembered | Switch to HEVC, restart the app and find HEVC still chosen | 6 | Tab four times (Choose Audio, Choose Image, Frame Shape, Resolution) to Codec; Right (HEVC); the restart. Focus starts on Choose Audio, so the first Tab is not needed if the page places it there |

**Focus order the budgets assume** (SPEC 27.2): Choose Audio, Choose Image, Frame Shape (one tab stop, arrow keys inside), Resolution, Codec, Crop position, Reset to Center, Make Video. A radio group is one tab stop and its arrow keys choose. Closing a system dialog returns focus to the control that opened it. A page that needs more steps than a budget gives changes the screen, not the budget: raising one is a recorded decision in `docs/DECISIONS.md`.

The audit runs every journey twice: with Ctrl (Windows and Linux) and with Command (macOS). The Electron build runs on the Mac only for development checks (SPEC 27.1), so Command is exercised in the audit and never by a person.

## Latency budgets

Each named interaction has a budget. `qa/typing.ts` opens a real window, so it runs on the DeskMini only (SPEC 28).

| Interaction | Budget | How it is measured |
| --- | --- | --- |
| Key press to the frame that shows it, main text field | Not applicable: no text entry (rules 27, 29, 41, 41b and 44 are N/A) | |
| The palette shortcut to the palette | 50 ms target, 100 ms limit | `pnpm qa:typing` (opens a window: DeskMini only) |
| List scroll, 10,000 rows | Not applicable: Song2Vid has no list (rules 25 and 26 are N/A in `windows/docs/PREMIUM-LEDGER.md`) | |
| Cancel to the bar leaving its running state | "Cancelling" on the next frame; "Cancelled. Nothing was saved." when the tool exits (SPEC 27.4) | `pnpm qa:audit` (job gate) |
| Crop drag to the frame that moves the image | The pointer's own frame, no lag behind it (rule 75) | `pnpm qa:audit` once S2V-030 adds the check |

## Memory budget

Private memory over the process tree, by each system's definition (private bytes on Windows, `phys_footprint` on macOS, anonymous resident memory plus swap on Linux; `scripts/memory-tree.*`), read from outside before the app is asked anything: budget 300 MB after five minutes idle, ceiling 680 MB at any time, counting the tool and everything it starts (for Song2Vid: `song2vid.exe` and FFmpeg during a 2160p HEVC job, SPEC 26.4 and 28; measured on the DeskMini and Titan). Split the budget into the empty shell's share (measure the starter before adding anything) and the app's own share. The app's share may not grow without an entry in `DECISIONS.md`.

| Build | System | Shell share | App share | Total idle | Peak |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

## Independent critic

One round (SPEC 28): after the screens exist, `pnpm qa:shots` makes the screenshots (it covers every system's key labels and title bar inset), and a reviewer that did not build the app and sees only the screenshots writes what reads as generic, unclear or unfinished. In both builds so far the builder's own audit passed while the critic found must-fix items (7 in each). The builder's notes, the code and the audit stay out of its brief. Record the round, the findings and what changed.

## Use gate and papercut log

The app is not called premium until the owner has done real work in it. Until then every report says "passes the automated bar; the owner has not used it". Each annoyance found in use goes here with a screenshot path, and each iteration closes at least one.

| Date | Papercut | Screenshot | Closed in |
| --- | --- | --- | --- |
| | | | |

## Not verified

Kept current per run in `windows/docs/PREMIUM-LEDGER.md`. Nothing is verified yet for the screens: they do not exist (S2V-030). Not verified so far, in plain words: everything that needs the real shell on Windows (`qa:crash`, `shell:evidence`, `measure:focus`, the installed check), which runs on the DeskMini; screen reader, IME, key-to-photon with a camera, cold start after a reboot, real fractional scaling, a downloaded (quarantined) build, Intel's hardware encoder, Windows on Arm, and each failure of the tool that was only simulated.
