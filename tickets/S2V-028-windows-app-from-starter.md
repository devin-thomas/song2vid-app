# S2V-028 - Windows app: the starter, renamed, with the seam files first

Status: resolved
Blocked by: none

## Goal

`windows/app/` is the desktop-app starter at a pinned commit, renamed to Song2Vid, passing its own gates, with the seam files written before any page work (SPEC §27.1, §28).

## Scope

- Copy `beta/desktop-app/starters/web-three-systems` from `devin-thomas/skills` at a recorded commit; `PROVENANCE.md` names it.
- `app.config.json`, `package.json` names, `index.html` title, `build/icon.svg` from `design/icon.svg`.
- Seam files: `src/bridge.ts` and `docs/BRIDGE.md`, `docs/JOURNEYS.md` and `qa/journeys.json` (four journeys with step budgets), `shortcuts.json` (SPEC §27.7), `qa/banned-terms.json` (from GLOSSARY, the tool's keys and codes, and the encoder names `nvenc`, `FFmpeg`, `Media Foundation`).
- Start `windows/SKILL-NOTES.md` and `windows/docs/PREMIUM-LEDGER.md` (every rule listed; the known N/A rows of SPEC §28 filled in).

## Acceptance Criteria

- `pnpm install --frozen-lockfile`, `typecheck`, `build`, `test`, `shell:check`, `qa:audit` pass on the renamed starter on the Mac and on Titan (headless).
- No starter file outside its marked blocks is changed without a line in `SKILL-NOTES.md`.
- The ledger has one row for each of rules 1 to 111 and 41b.

## Dependencies

None.

## Comments
- 2026-11-23 (builder): Copied `beta/desktop-app/starters/web-three-systems` from `devin-thomas/skills` branch `beta` at `48b054d16de2fbcdcb30487471967dda176b469b` into `windows/app/`, renamed it, wrote the seam files, and started `windows/SKILL-NOTES.md` and `windows/docs/PREMIUM-LEDGER.md`. Commits on `ticket/S2V-028`, in order: the safety scan allowing loopback and package pins (`scripts/safety-scan.sh`, which flagged 663 starter lines as emails and addresses); the starter copied unchanged except one `.gitignore` line; the rename (`bfbd20f`); the window size; the seam files, notes and ledger.
  - The gates passed on the renamed starter at `bfbd20f`, with the starter's own window size (1280 x 800, minimum 720 x 540), on the Mac (Node 24, pnpm 11.9.0 chosen by `packageManager`): `pnpm install --frozen-lockfile` (0), `pnpm electron:install` (0), `pnpm typecheck` (0), `pnpm build` (0), `pnpm test` (0; 63 pass, 0 fail), `pnpm shell:check` (0), `pnpm qa:audit` (0; 0 axe violations in 30 state and theme runs, 60 layout cases at 4 sizes, both journeys and the shortcuts on both key families).
  - The same seven commands on Titan (Windows, Node 24, headless, a copy of `windows/app` at `bfbd20f` extracted into a scratch folder under the profile) all exited 0 in 3 minutes 43 seconds, as printed by the script. Titan's logs were not read back: its ssh stopped accepting the key right after the run (`Permission denied (publickey)`, the agent holding no identities), so test counts and audit lines from Titan are not in this comment, and the same commands were not rerun on Titan at the final commit.
  - Setting the window to 560 x 760 (minimum 480 x 640) makes the starter's own `qa:audit` fail 122 times at the renamed starter: its title bar overflows at 200% zoom and its note journey fails in the narrow layout. That is the example screen, which S2V-030 replaces. The window size is its own commit (`634740e`) for that reason.
  - At the last commit (`ebb416a` plus the notes edit): `pnpm build` (0), `pnpm test` (0; 63 pass), `pnpm shell:check` (0; the macOS menu carries the 9 commands of `shortcuts.json`), `pnpm typecheck` (1; 18 errors, all in the example page and its stand-in bridge, which still use the old bridge and command ids), `pnpm qa:audit` (1; stops at its first state because the example presses shortcuts that `shortcuts.json` no longer has). These two stay red until S2V-030 replaces the example screen; `windows/SKILL-NOTES.md` and D-022 in `windows/app/docs/DECISIONS.md` say so. The seam files cannot be written and the starter's example gates stay green at once.
  - Seam files: `src/bridge.ts` and `docs/BRIDGE.md` (the page holds opaque ids, never paths; calls to choose audio and image, judge a drop, preview, report encoders, make with the save dialog in the shell, cancel, show in folder, preferences), `docs/JOURNEYS.md` and `qa/journeys.json` (choose-and-make 3, drop-and-make 2, crop-square 10, hevc-remembered 6 steps), `shortcuts.json` (SPEC 27.7, plus the starter's command palette), `qa/banned-terms.json`, and `docs/TOOL-CONTRACT.md`, which points at SPEC 14, 24 and 26. `electron/preload.ts` and `electron/menu.ts` carry them so `pnpm test` and `pnpm shell:check` keep passing. The main-process handlers for the new channels are not written (S2V-029, S2V-030).
  - Ledger: 112 rows, rules 1 to 111 and 41b; the 24 known N/A rows of SPEC 28 filled in with a reason, the rest "applies, pending", rule 75 noted for the crop control; the process steps listed. No verdicts yet.
  - `scripts/safety-scan.sh` (clean on the tree and on the branch's commit messages). `scripts/check.sh` (Swift package tests and Xcode) was not run: nothing under `Song2Vid*`, `fixtures` or `site` changed, only `windows/` and the scan.
  - Open points for S2V-029 and S2V-030, in `windows/app/docs/BRIDGE.md`: `check` needs an audio and an image together while the window chooses them one at a time; the banned-terms gate has no exemption for About's FFmpeg notice. `tool.binaries` lists `song2vid`, `ffmpeg` and `ffprobe` (the config has no per-system field, so "win32-x64 only" is kept by running `package:win` alone).
  - Not checked: anything that opens a window; the Electron shell was installed (`electron:install`) but never launched.
