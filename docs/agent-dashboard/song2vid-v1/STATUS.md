# Song2Vid v1 build

State: **waiting** · Phase: Deploy: the release is live; the download page is waiting on the owner · Updated: 2026-11-19T01:57:35Z
Repository: devin-thomas/song2vid-app · Branch: build/v1

## Action required

- **Choose how to host the download page, and approve deleting a stray Worker**: Wrangler's 'pages project create' made a Cloudflare Worker named song2vid instead of a Pages project. Because it ran from the stock-example folder, it published that folder's stock-ticker page at song2vid's workers.dev address. stock-example itself is unchanged. Smallest action: Reply: (1) delete the stray song2vid Worker? (2) host the page on song2vid.pages.dev, using Wrangler's opt-out flag for classic Pages, or on Workers?

## Current activity

Waiting for the owner to choose how to host the download page.

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
- [in_progress] S2V-007 Download page live on pages.dev (page built and reviewed; deploy after release)
- [complete] Code review, merge build/v1 to main (fixes verified; main = build/v1)
- [pending] Final progress save (Starter Pack)

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

## Outputs

- [Repository (public)](https://github.com/devin-thomas/song2vid-app/tree/build/v1)
- [SPEC.md](https://github.com/devin-thomas/song2vid-app/blob/build/v1/SPEC.md)
- [Tickets](https://github.com/devin-thomas/song2vid-app/tree/build/v1/tickets)
- [Wiki: ticket log](https://github.com/devin-thomas/song2vid-app/blob/build/v1/docs/wiki/ticket-log.md): verification evidence per ticket
- [Icon preview](https://github.com/devin-thomas/song2vid-app/blob/build/v1/design/preview.png)

## Next up

1. Delete the stray song2vid Worker (with approval)
2. Deploy site/ to the chosen host and verify the live page and download button
3. Owner downloads from the live page, opens the app and makes a video
4. Final progress save

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

## Walk-away snapshot

- Last verified good state: v1.0.0 is on GitHub Releases; main and build/v1 are at 6c0436e and all checks pass
- Unfinished: The download page is not deployed. A stray Worker named song2vid exists on Cloudflare.
- Next safe step: Wait for the owner, then run wrangler from the repo folder only, never from stock-example.
- Touched: song2vid-app repo (build/v1, ticket branches); private progress repo
- Expected processes: This dashboard's local server on localhost:4173
- Input needed: Hosting choice, and approval to delete the stray Worker

## Delivery and persistence

- Mode: localhost (http://localhost:4173/)
- Last endpoint check: 2026-11-19T01:57:35Z: task ID and timestamp verified on localhost:4173 (loopback only)
- Persistence: Committed to build/v1 at each checkpoint
- Limitations: Localhost only: viewable on this Mac, not on the phone.
