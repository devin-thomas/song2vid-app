# Song2Vid v1 build

State: **working** · Phase: Review: code review, and the download page in parallel (7 of 9 tickets done) · Updated: 2026-11-19T01:13:27Z
Repository: devin-thomas/song2vid-app · Branch: build/v1

## Action required

No action required from you right now.

## Current activity

A Sonnet reviewer is running the two-axis code review (standards and spec) on build/v1. Meanwhile another Sonnet implementer is building the download page, without deploying it.

## Milestones

- [complete] Plan approved (Grill to Build) (2026-11-18)
- [complete] S2V-001 Public repo and app skeleton (verified on a fresh clone)
- [complete] S2V-009 App icon (preview reviewed)
- [complete] S2V-002 Frame size and placement rules (45 tests; hand-checked)
- [complete] S2V-003 Video export (22 integration tests; 2160p in about 7 s)
- [complete] S2V-004 Main window and live preview (81 tests; screenshots reviewed)
- [complete] S2V-008 Drag and drop with replace dialog (123 tests; real drags tested)
- [complete] S2V-005 Make Video flow (5 real videos checked with ffprobe)
- [pending] S2V-006 v1.0.0 release on GitHub
- [in_progress] S2V-007 Download page live on pages.dev (page being built; deploy after release)
- [in_progress] Code review, merge build/v1 to main
- [pending] Final progress save (Starter Pack)

## Blockers

None.

## Warnings

- (No action needed) GitHub Actions runs only when started by hand (ADR-011). All checks run on the owner's Mac before each merge.
- (No action needed) An implementer left a macOS Finder permission prompt open on screen during testing. It is safe to dismiss with Don't Allow.

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

1. Read the review; dispatch one fixer for the must-fix and should-fix items
2. Merge build/v1 into main
3. Dispatch S2V-006 (v1.0.0 release zip on GitHub Releases)
4. Deploy the download page to song2vid.pages.dev and verify it live
5. Owner downloads from the live page and makes a video

## Activity

- 2026-11-18: Plan approved, with drag and drop and an app icon added
- 2026-11-18: Chief-of-staff skills installed in the repo
- 2026-11-19: S2V-001 verified: public repo, check script, commit guard
- 2026-11-19: CI switched to manual-only, at the owner's request
- 2026-11-19: S2V-009 icon and S2V-002 frame math verified and merged into build/v1
- 2026-11-19: S2V-003 and S2V-004 dispatched in parallel
- 2026-11-19: Build dashboard started on localhost
- 2026-11-19: S2V-004 main window verified from screenshots and merged; S2V-008 dispatched
- 2026-11-19: S2V-008 drag and drop verified and merged
- 2026-11-19: S2V-003 export engine verified and merged (2:24 song at 2160p in about 7 s); S2V-005 dispatched
- 2026-11-19: S2V-005 verified: all five real videos probed and fully decoded; merged. Code review and page build started.

## Walk-away snapshot

- Last verified good state: build/v1 passes scripts/check.sh (142 core + 22 integration tests); the app makes correct videos end to end
- Unfinished: Code review (read-only) and the download page branch
- Next safe step: Verify each branch with scripts/check.sh, then merge it into build/v1
- Touched: song2vid-app repo (build/v1, ticket branches); private progress repo
- Expected processes: This dashboard's local server on localhost:4173
- Input needed: None right now

## Delivery and persistence

- Mode: localhost (http://localhost:4173/)
- Last endpoint check: 2026-11-19T01:13:27Z: task ID and timestamp verified on localhost:4173 (loopback only)
- Persistence: Committed to build/v1 at each checkpoint
- Limitations: Localhost only: viewable on this Mac, not on the phone.
