# Issue tracker: local Markdown (Grill to Build layout)

Tickets for this repo are Markdown files in `tickets/`, one per ticket, named `S2V-NNN-slug.md`. The specification is `SPEC.md` at the repo root.

## Conventions

- A `Status:` line near the top of each ticket: `ready-for-agent`, `claimed`, `needs-info`, `ready-for-human` or `resolved`.
- A `Blocked by:` line lists ticket IDs, or `none`. A ticket is ready when every ticket it lists is `resolved`.
- Comments and handover notes go at the bottom, under `## Comments`.

## Operations

- **Publish:** create a new `tickets/S2V-NNN-slug.md`, numbered after the highest existing one.
- **Fetch:** read the file at the given path or ID.
- **Frontier:** tickets that are `ready-for-agent` and unblocked. The lowest number goes first.
- **Claim:** set `Status: claimed` before starting work.
- **Close:** set `Status: resolved` and add a `## Comments` note with the merge commit.
