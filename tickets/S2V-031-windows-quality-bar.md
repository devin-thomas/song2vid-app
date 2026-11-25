# S2V-031 - Windows app: real-shell checks, critic round and the ledger

Status: open (the Mac side is done; the Titan runs that remain are listed in the last comment)
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
- 2026-11-25 (builder): The critic's round and the gates, on the Mac. Branch `ticket/S2V-031`; not merged. The Titan runs are not finished: Titan refused this build's ssh key (publickey denied, from about 11:35 AM Central on) after the first runs, so the rest is listed under "Not done".
  - Critic round (process step 3): the critique is `windows/docs/CRITIQUE-1.md`, with the disposition of every item (must-fix 1 to 11 fixed, except the rejected parts of 6, 7 and 8; the cheap should-fix items done, the rest left with a reason). Decisions in `windows/app/docs/DECISIONS.md` D-028; changes to starter files and 5 new items (25 to 29) in `windows/SKILL-NOTES.md`.
  - Must-fix 1, the cause: the page takes its theme from the saved choice (D-020) and `qa/lib.ts` set only the browser's colour scheme, so every "light" picture and every "light" axe run of S2V-030 was dark (the pictures were byte-identical). Fixed in `openPage`; `load` throws when a page shows another theme than it was opened for; `qa/shots.ts` fails on a light picture equal to its dark one (36 pairs checked); gate `theme`. The light theme then showed real contrast failures (the accent's key labels, a dialog checked mid-fade), fixed.
  - Layout: the card's work area scrolls with a real "More below" strip (not a mask); Frame Shape reflows to 3 + 2; names are cut in the middle and keep their extension; the status bar wraps and is as tall as its longest message at its width, in every state (every message drawn invisibly in one grid cell, no script); its button takes its own line at 280 px; progress is a bar across the bar's top edge with the percent said once; failures (danger) and refusals (warning) have a tone, a mark, a tint and an edge, a saved video a success mark; the accent fills the primary button in both themes; the focus ring is for keyboard modality; a file the tool could not find or read is marked in its row and the preview, Make Video waits, the enlarge note goes; a missing tool leaves the bar empty; an image too small is said by the bar; refused drops say what was refused and what to do. SPEC 27.5's sentences are unchanged. At 200% zoom the work area is about 95 px high (the bar needs its longest message and its button), so most rows are reached by scrolling; every control is reachable.
  - New or changed gates, each shown failing on the S2V-030 build (`024bb99`, new `qa/` files copied over it): `clipped` (no mask as a cue; 47 scroll areas with no cue at 200% zoom and the minimum), `reach`, `truncated` (170 cut labels, sentences and names, and buttons cut by their own box, e.g. "Cancel" 49 > 32, "Show in File Explorer" 130 > 107), `distinct` (84 failures), `messages` (24), `ring` (10), `theme` (2, with the old `lib.ts`); the `tokens` gate now computes the contrast of the accent, the tones and the bar's text in both themes (4.98:1 light and 8.12:1 dark for the text on the accent). Planted breaks added for rules 5, 38 (two), 77, 97 and 111 (all caught).
  - Rule 77 (the ticket's last criterion): `electron/tool/locate.ts` read `process.platform` and `process.arch` itself, which the starter's shell-check excused. It did not pass the rule; it passes now (`NODE_PLATFORM` and `NODE_ARCH` exported by `electron/platform.ts`, used as locate.ts's defaults; shell-check covers `electron/tool/`; planted break caught). Noted in SKILL-NOTES item 29.
  - Ledger: `windows/docs/PREMIUM-LEDGER.md` has no row left "pending": 0 rows "applies, pending"; every rule is applies with a verdict or N/A with a reason (new N/A: 10, 12, 56). The unverified rows are listed in its header for the release notes.
  - Checks on this Mac (Node 24.22.3, headless Chromium from Playwright), final tree, native exit codes: `pnpm typecheck` (0), `pnpm build` (0), `pnpm test` (0; 186 pass, 0 fail), `pnpm shell:check` (0), `node qa/audit.ts` (0: axe 0 violations in 90 state and theme runs, both themes now real; 688 focus checks; 180 layout cases at 4 sizes with spill, stable, clipped, reach and truncated; journeys within budgets; the job, crop, files, tool, notices, theme, distinct, messages and ring gates), `node qa/visual.ts --update` then `node qa/visual.ts` twice (0 and 0; 166 pictures, largest change 0.000%), `pnpm qa:crash` (0), `node qa/planted-breaks.ts 5 38 97 107 108 109 110 111` (every break caught except the packaged variant of 108, which needs a packaged app: S2V-032), `node qa/planted-breaks.ts 77` (caught), `scripts/safety-scan.sh` (0). I looked at the new pictures: dark and light at 560x760, 480x640 and 200% zoom, the error, done, making, cancelling, long-name, tool-missing and refused-drop states; each must-fix is gone.
  - Checks on Titan (Windows 11, Edge headless, a copy of `windows/app` under the profile), before the ssh key was refused, on the tree just before the last two edits (rule 77 and the ledger): `pnpm typecheck` (0), `pnpm build` (0), `pnpm test` (0 on the third run: the first run failed on the same EPERM cleanup of a scratch folder as in S2V-030, so `test/helpers.ts` now leaves a folder it cannot remove after 10 s and says so), `pnpm qa:kill` (0: the Codec chosen survived a kill at 62, 308 and 882 ms), `pnpm qa:crash` (0: recover, loop, maximized, lost). The audit on Titan found one real race (the state "the tool turns missing after launch" chose files while a 300 ms fixture timer replaced the card; fixed in `qa/states.ts`).
  - Not done, and why: (1) on Titan, `shell:check`, `qa:audit` and `qa:visual` on the final tree, `qa:typing`, `qa:planted`, `shell:evidence`, `measure:focus --first explorer --route explorer`, `measure:memory` (5 idle minutes): Titan stopped accepting the key (`Permission denied (publickey)` for the `titan` alias, as user gohan, from about 11:35 AM Central; Tailscale shows it online). Titan also still has my files under `s2v-build-031` in the profile, `app031.tgz`, `t031.ps1`, `tstep.ps1`, `tchain.ps1`, `repro031.ts` and `repro2031.ts` in the profile folder, and a scheduled task `S2V031Run` (it can start only `t031.ps1`); nothing of mine is running there that I know of (the last run's tree was stopped by exact process ids). (2) The Windows visual baselines in `qa/baselines/windows/` are the S2V-030 ones, from before the new design: `qa:visual` on Windows will fail until they are accepted on Titan (`node qa/visual.ts --update`, after looking at them). (3) The 2160p HEVC job's memory needs the real `song2vid.exe` with NVENC (S2V-027), pending for S2V-032. (4) `pnpm fuses:check` and the packaged variant of planted rule 108: S2V-032. (5) DeskMini criteria: not verified: DeskMini not available. (6) The critic's round was one round (SPEC 28); a second look at the new pictures is the owner's use gate.
  - Owner decisions: none. Rejected by ruling: must-fix 6, and the encoder-line and encoder-name parts of 7 and 8.

