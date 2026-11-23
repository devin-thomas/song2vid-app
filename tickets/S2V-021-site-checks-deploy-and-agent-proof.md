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
