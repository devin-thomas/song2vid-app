# S2V-021 - Check, deploy and prove the agent-ready site

Status: ready-for-agent
Blocked by: S2V-020

## Goal

The agent-ready site is checked by the repo's gate, live, and by a separate agent, and the milestone is recorded (SPEC §20, §21).

## Scope

- Extend `scripts/check-site.sh` with the checks in SPEC §20 and show each one fail on a deliberately broken copy (`SITE_DIR`). `scripts/check.sh` already runs it.
- `README.md`: one line on `scripts/build-site.py` and how to run it.
- Merge, then deploy `site/` to the `song2vid` Pages project from this repo only (`wrangler pages deploy site --project-name=song2vid`). The owner has chosen to deploy.
- Run the outside checks of SPEC §20 with `curl` against the live site and record the results.
- Run the separate-agent proof of SPEC §20 in a new Claude Code session that has not seen the repo; compare its answers with the pages.
- On a pass and the owner's confirmation, save the `agent-ready-website` step with its `verification` object in the private progress file.

## Acceptance Criteria

- `scripts/check.sh` passes, and each new check is shown to fail on a broken copy.
- Every outside check passes live.
- The agent gives 1.1.0 and macOS 14 or later, cites `/`, and says the site does not publish planned changes.
- The progress record holds the verification; nothing else in it changes.

## Dependencies

S2V-020.

## Comments
- 2026-11-22 (coordinator): Checks and deploy done; the separate-agent proof is pending. `scripts/check-site-ready.py` (called by `scripts/check-site.sh`, so by `scripts/check.sh`) holds the SPEC §20 checks, and `scripts/test-check-site.sh <command>` shows 20 of them failing on a broken copy (stray file, missing listed file, stale generated files, wrong or second canonical, missing alternate, date and version mismatches, missing facts, link without trailing slash, dead link, robots, content type, 404 page, sitemap). The full `scripts/check.sh` passes. A first gate run stopped at the public-safety scan because loading `build-site.py` wrote a `__pycache__` file whose path the scan flagged; the checks now run with `python3 -I -B` and `.gitignore` lists `__pycache__/`. Merged to `main` (`101166f`) and deployed with `wrangler pages deploy site --project-name=song2vid`. Outside checks against the live site, all as SPEC §20 says: `/` and `/docs/` 200 `text/html` with their own canonical link; `/docs` 308 to `/docs/`; `/index.md`, `/docs.md`, `/agent.md` 200 `text/markdown; charset=utf-8`; `/llms.txt`, `/robots.txt` 200 `text/plain; charset=utf-8`; `/sitemap.xml` 200 `application/xml; charset=utf-8`; `/roadmap` and `/nonexistent` 404 with `404.html` byte for byte; "Free · Version 1.1.0 · Requires macOS 14 or later" and `image_not_found` are in the served HTML; every live file except `404.html` (which Pages serves only for unknown addresses) is byte-identical to the repo; no local path, email, IP address or sample-file name in any public file. One finding the plan missed: before this change the live site answered every unknown address with the home page and status 200 (Pages treats a site without `404.html` as a single-page app); `site/404.html` fixes it. Not checked: the proof (next); Safari; the Copy button's real clipboard write.
