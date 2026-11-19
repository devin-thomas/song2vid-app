# Build workflow

- On 2026-11-18, the build started with Matt Pocock's `chief-of-staff` skill and its dependencies, copied into `.claude/skills/` from `mattpocock/skills@5863806` (ADR-010).
- Roles, as of 2026-11-18: the Opus coordinator reads the spec and tickets, dispatches one fresh Sonnet subagent per ticket (high reasoning, background), checks each result against the ticket's acceptance criteria, and keeps PROJECT/SPEC/ADR/this wiki current. Subagents write all app code.
- Tickets live in `tickets/` with `Status:` and `Blocked by:` lines (docs/agents/issue-tracker.md). The work runs in this order, with paired tickets running in parallel: S2V-001 → (S2V-002, S2V-009) → (S2V-003, S2V-004) → S2V-008 → S2V-005 → S2V-006 → S2V-007.
- Branches, as of 2026-11-18: ticket work merges into `build/v1`, and `build/v1` merges into `main` after a code review.
- Implementer notes (build commands, gotchas) are kept outside the repo, so private machine details never become public. Durable lessons are summarised here instead.
- Plan from the chief-of-staff skill: a `retro` on about one in five subagent sessions, starting with any that went wrong.
