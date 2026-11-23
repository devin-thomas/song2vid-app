# S2V-028 - Windows app: the starter, renamed, with the seam files first

Status: open
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
