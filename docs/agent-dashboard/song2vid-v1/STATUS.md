# Song2Vid v1 build

State: **working** · Phase: Build: tickets in progress (4 of 9 done) · Updated: 2026-11-19T00:18:04Z
Repository: devin-thomas/song2vid-app · Branch: build/v1

## Action required

No action required from you right now.

## Current activity

Two Sonnet implementers are building S2V-003 (video export engine) and S2V-004 (main window and live preview) in parallel worktrees. The coordinator will verify each one when it reports back.

## Milestones

- [complete] Plan approved (Grill to Build) (2026-11-18)
- [complete] S2V-001 Public repo and app skeleton (verified on a fresh clone)
- [complete] S2V-009 App icon (preview reviewed)
- [complete] S2V-002 Frame size and placement rules (45 tests; hand-checked)
- [in_progress] S2V-003 Video export
- [in_progress] S2V-004 Main window and live preview
- [pending] S2V-008 Drag and drop with replace dialog (after S2V-004)
- [pending] S2V-005 Make Video flow (after S2V-003, S2V-004 and S2V-008)
- [pending] S2V-006 v1.0.0 release on GitHub
- [pending] S2V-007 Download page live on pages.dev (ends with the owner's own download test)
- [pending] Code review, merge build/v1 to main
- [pending] Final progress save (Starter Pack)

## Blockers

None.

## Warnings

- (No action needed) GitHub Actions runs only when started by hand (ADR-011). All checks run on the owner's Mac before each merge.
- (Monitoring) The 2160p export speed for a full-length song is not yet measured. S2V-003 reports it.

## Decisions

- 2026-11-18: Native macOS app with SwiftUI and AVFoundation (final; costly to reverse). Small download, no bundled FFmpeg (ADR-001).
- 2026-11-18: Public repo with public plan, wiki and skills (final; one-way once pushed). A demonstration of building with AI using the Starter Pack (ADR-003, ADR-004).
- 2026-11-18: Chief-of-staff workflow: Sonnet builds, Opus verifies and writes docs (final; reversible). The owner's choice (ADR-010).
- 2026-11-19: Test on the owner's Mac; CI by hand only (final; reversible). Hosted Mac runners used up the account's allowance before (ADR-011).
- 2026-11-19: The owner's sample media is never committed (final; n/a). Personal images and possibly non-redistributable music (ADR-012).

## Outputs

- [Repository (public)](https://github.com/devin-thomas/song2vid-app/tree/build/v1)
- [SPEC.md](https://github.com/devin-thomas/song2vid-app/blob/build/v1/SPEC.md)
- [Tickets](https://github.com/devin-thomas/song2vid-app/tree/build/v1/tickets)
- [Wiki: ticket log](https://github.com/devin-thomas/song2vid-app/blob/build/v1/docs/wiki/ticket-log.md): verification evidence per ticket
- [Icon preview](https://github.com/devin-thomas/song2vid-app/blob/build/v1/design/preview.png)

## Next up

1. Verify S2V-003: tests, export timing, and a real ffprobe check
2. Verify S2V-004: screenshots of each Frame Shape, and the crop drag
3. Merge both, then dispatch S2V-008 (drag and drop)
4. Dispatch S2V-005 (Make Video flow) once S2V-008 lands

## Activity

- 2026-11-18: Plan approved, with drag and drop and an app icon added
- 2026-11-18: Chief-of-staff skills installed in the repo
- 2026-11-19: S2V-001 verified: public repo, check script, commit guard
- 2026-11-19: CI switched to manual-only, at the owner's request
- 2026-11-19: S2V-009 icon and S2V-002 frame math verified and merged into build/v1
- 2026-11-19: S2V-003 and S2V-004 dispatched in parallel
- 2026-11-19: Build dashboard started on localhost

## Walk-away snapshot

- Last verified good state: build/v1 passes scripts/check.sh (45 core tests, universal ad-hoc-signed build)
- Unfinished: S2V-003 and S2V-004 are being built on their own branches
- Next safe step: Verify each branch with scripts/check.sh, then merge it into build/v1
- Touched: song2vid-app repo (build/v1, ticket branches); private progress repo
- Expected processes: This dashboard's local server on localhost:4173
- Input needed: None right now

## Delivery and persistence

- Mode: localhost (http://localhost:4173/)
- Last endpoint check: 2026-11-19T00:18:04Z: task ID and timestamp verified on localhost:4173 (loopback only)
- Persistence: Committed to build/v1 at each checkpoint
- Limitations: Localhost only: viewable on this Mac, not on the phone.
