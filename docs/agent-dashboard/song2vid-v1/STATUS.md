# Song2Vid v1 build

State: **complete** · Phase: Done: v1.0.0 released and the download page is live · Updated: 2026-11-19T15:27:09Z
Repository: devin-thomas/song2vid-app · Branch: build/v1

## Action required

No action required from you right now.

## Current activity

Finished. Nothing running except this dashboard server.

## Milestones

- [complete] Plan approved (Grill to Build) (2026-11-18)
- [complete] S2V-001 Public repo and app skeleton (verified on a fresh clone)
- [complete] S2V-009 App icon (preview reviewed)
- [complete] S2V-002 Frame size and placement rules (45 tests; hand-checked)
- [complete] S2V-003 Video export (22 integration tests; 2160p in about 7 s)
- [complete] S2V-004 Main window and live preview (81 tests; screenshots reviewed)
- [complete] S2V-008 Drag and drop with replace dialog (123 tests; real drags tested)
- [complete] S2V-005 Make Video flow (5 real videos checked with ffprobe)
- [complete] S2V-006 v1.0.0 release on GitHub (v1.0.0 published; 1.5 MB; anonymous download verified)
- [complete] S2V-007 Download page live on pages.dev (live; owner downloaded, opened and made a video)
- [complete] Code review, merge build/v1 to main (fixes verified; main = build/v1)
- [complete] Final progress save (Starter Pack) (progress record saved and verified on the remote)

## Blockers

- Hosting choice and deletion approval needed from the owner. Impact: The download page is not live yet. Owner: Owner. Recovery: After the answer, delete the stray Worker if approved, deploy site/ from a folder with no Wrangler config, then verify the live URL.

## Warnings

- (No action needed) GitHub Actions runs only when started by hand (ADR-011). All checks run on the owner's Mac before each merge.
- (No action needed) An implementer left a macOS Finder permission prompt open on screen during testing. It is safe to dismiss with Don't Allow.

## Decisions

- 2026-11-18: Native macOS app with SwiftUI and AVFoundation (final; costly to reverse). Small download, no bundled FFmpeg (ADR-001).
- 2026-11-18: Public repo with public plan, wiki and skills (final; one-way once pushed). A demonstration of building with AI using the Starter Pack (ADR-003, ADR-004).
- 2026-11-18: Chief-of-staff workflow: Sonnet builds, Opus verifies and writes docs (final; reversible). The owner's choice (ADR-010).
- 2026-11-19: Test on the owner's Mac; CI by hand only (final; reversible). Hosted Mac runners used up the account's allowance before (ADR-011).
- 2026-11-19: The owner's sample media is never committed (final; n/a). Personal images and possibly non-redistributable music (ADR-012).
- 2026-11-19: Audio above 48 kHz is converted to 48 kHz (final; reversible). The AAC encoder rejects higher rates at 256 kbps; this was found by the code review (SPEC §6.3).
- 2026-11-19: Host the page on classic Cloudflare Pages (song2vid.pages.dev); delete the stray Worker (final; yes). Matches ADR-002 and SPEC section 8; owner approved

## Outputs

- [Download page (live)](https://song2vid.pages.dev): Cloudflare Pages; download checksum verified
- [Release v1.0.0](https://github.com/devin-thomas/song2vid-app/releases/tag/v1.0.0)
- [Repository (public)](https://github.com/devin-thomas/song2vid-app/tree/build/v1)
- [SPEC.md](https://github.com/devin-thomas/song2vid-app/blob/build/v1/SPEC.md)
- [Tickets](https://github.com/devin-thomas/song2vid-app/tree/build/v1/tickets)
- [Wiki: ticket log](https://github.com/devin-thomas/song2vid-app/blob/build/v1/docs/wiki/ticket-log.md): verification evidence per ticket
- [Icon preview](https://github.com/devin-thomas/song2vid-app/blob/build/v1/design/preview.png)

## Next up

1. Optional: v1.0.1 without the debugging permission, keeping the sandbox
2. Optional: test on an Intel Mac
3. Optional: retro on the S2V-004 verification gap

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
- 2026-11-19: Code review: 2 must-fix, 5 should-fix, 14 nits. Fixer dispatched.
- 2026-11-19: v1.0.0 released and verified anonymously (sha256 matches, universal, signature valid)
- 2026-11-19: Deploy attempt created a stray Worker serving the stock-ticker page; paused for the owner
- 2026-11-19: Stray Worker deleted with approval; classic Pages project created; site deployed and verified at song2vid.pages.dev
- 2026-11-19: Owner report: downloaded from the live page, made and played a video. S2V-007 resolved; Starter Pack Phase 2 saved

## Walk-away snapshot

- Last verified good state: v1.0.0 released; song2vid.pages.dev live; owner report recorded
- Unfinished: None required
- Next safe step: Optional follow-ups only
- Touched: song2vid-app repo (main, build/v1); Cloudflare Pages project song2vid; private progress repo
- Expected processes: This dashboard's local server on localhost:4173
- Input needed: None

## Delivery and persistence

- Mode: localhost (http://localhost:4173/)
- Last endpoint check: 2026-11-19T01:57:35Z: task ID and timestamp verified on localhost:4173 (loopback only)
- Persistence: Committed to build/v1 at each checkpoint
- Limitations: Localhost only: viewable on this Mac, not on the phone.
