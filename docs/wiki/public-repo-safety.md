# Public repo safety

- On 2026-11-18, the repo was decided public from the first commit (ADR-003). Never commit tokens, account IDs, personal emails, IP addresses, or `/Users/...` paths.
- On 2026-11-18, ticket S2V-001 was scoped to add guardrails: a `scripts/check.sh` safety scan, a tracked pre-commit hook that also checks the commit author, CI on a macOS runner, and GitHub secret scanning with push protection. The outcome is in [ticket-log](ticket-log.md).
- Cloudflare credentials stay in Wrangler's own login storage, never in the repo (SPEC §9).
- On 2026-11-19, S2V-001 added the guardrails at `90c7639`: `scripts/check.sh`, `scripts/safety-scan.sh`, `.githooks/pre-commit`, and the `check` workflow. The hook only runs after `git config core.hooksPath .githooks`, which a fresh clone does not set; the README says so.
