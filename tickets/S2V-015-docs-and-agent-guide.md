# S2V-015 - Docs page and Agent Guide on the site

Status: resolved
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

## Comments

- 2026-11-22: Built on `ticket/S2V-015` from `build/v2` after S2V-014. `site/docs/index.html` (served at `/docs`, which Pages redirects to `/docs/`) has install, every command and option with its short form, the size table, examples, the three progress modes, the JSON keys with sample lines, the exit-status and error-code table, the app's window route in brief and a pointer to the Agent Guide. It matches the landing page's style, with its own small inline style sheet, no script and no third-party requests. The landing page footer links to `/docs`.
- `site/agent.md` is made by `scripts/build-agent-md.sh`, a plain copy of `skills/song2vid/SKILL.md`. `site/_headers` serves it as `text/markdown; charset=utf-8`. `scripts/check-site.sh`, called from `scripts/check.sh`, fails if `agent.md` differs from the skill, if any option in the three `--help` texts (26 spellings) is not on the docs page as `<code>option</code>`, or if the header is missing. Each failure was shown by pointing the script at a deliberately broken copy: an edited `agent.md`, a docs page with `-q` and `--dry-run` renamed, and a header changed to `text/plain`.
- Local preview with `wrangler pages dev site` (run from this repo, which has no Wrangler config): `/agent.md` came back as `Content-Type: text/markdown; charset=utf-8`, and `/docs` redirected to `/docs/` and then returned the page. The docs page was viewed at 375 px in light and dark and at 1280 px: no page-level horizontal scroll (scroll width equals client width), no request to another origin. At 640 px and narrower each table row becomes a labelled card, so nothing is cut off.
- Not checked: Safari, the live site (S2V-017 deploys it), Windows or Linux browsers.
