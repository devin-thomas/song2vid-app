# S2V-015 - Docs page and Agent Guide on the site

Status: ready-for-agent
Blocked by: S2V-014

## Goal

People who use the command read `/docs`; agents read `/agent.md` (SPEC §15, §16).

## Scope

- `site/docs/index.html` (or `site/docs.html` served at `/docs`), matching the landing page's style: install, commands, every option with its short form, examples, progress modes, JSON keys, exit statuses and error codes, and the app's window route in brief.
- `site/agent.md` generated from `skills/song2vid/SKILL.md` by a script, never edited by hand; `_headers` serves it as `text/markdown; charset=utf-8`.
- A check in `scripts/check.sh` that fails if any `--help` option is missing from the docs page, or if `site/agent.md` differs from the skill.
- A link to `/docs` from the landing page.

## Acceptance Criteria

- The two checks pass, and each fails when deliberately broken.
- The docs page reads well at 375 px and desktop, light and dark, with no horizontal scroll and no third-party requests.
- A local preview serves `/agent.md` as Markdown text.

## Dependencies

S2V-014.
