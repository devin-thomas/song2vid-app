# Decision record

## ADR-001 - Native Mac app built with Swift and Apple's own video tools

**Status:** Accepted (proposed in round 1; the learner did not object)

**Decision:** Build Song2Vid as a native macOS app (SwiftUI) that makes the video with Apple's built-in AVFoundation framework, rather than a web-tech desktop app bundling FFmpeg.

**Rationale:** Xcode 27 and Swift 6.4 are already on this Mac. Apple's built-in tools can combine a still image and audio into an MP4 without shipping a separate video engine, so the app stays a few megabytes and avoids FFmpeg's licence obligations in a public repo.

**Consequences:** Mac-only, macOS 14 or later, one download that runs on both Apple silicon and Intel Macs. Audio formats are limited to what macOS can read (MP3, M4A/AAC, WAV, AIFF, FLAC, ALAC). A Windows version would be a separate build later.

## ADR-002 - Download page on Cloudflare Pages

**Status:** Accepted

**Decision:** The download page is a small static site on Cloudflare Pages (`*.pages.dev`).

**Rationale:** Learner's choice; Cloudflare is the course default and the account already exists.

**Consequences:** Pages limits single files to 25 MiB, so the app download must stay small or be hosted on GitHub Releases and linked from the page.

## ADR-003 - Public repository from the first commit

**Status:** Accepted

**Decision:** `song2vid-app` is public from the start, so everything committed is treated as published.

**Rationale:** Learner's choice.

**Consequences:** Commits use the GitHub noreply address. `.gitignore` excludes build output, `.env` files, and local test media. No tokens, personal email, tailnet IPs, or home-folder paths are committed. Starter Pack progress stays in the private progress repo. Secret scanning and push protection are turned on for the repo.

## ADR-004 - Plan files are public

**Status:** Accepted

**Decision:** The planning files (PROJECT, GLOSSARY, ADR, SPEC, Ideas, tickets) live in the public `song2vid-app` repo.

**Rationale:** The repo is meant to show people how to plan and build a project like this themselves.

**Consequences:** The plan files are written to be read by the public. Starter Pack progress and session notes stay in the private progress repo.

## ADR-005 - No paid Apple signing

**Status:** Accepted

**Decision:** Ship the app without an Apple Developer ID signature or notarization.

**Rationale:** Avoids the $99/year Apple Developer Program for a free hobby tool.

**Consequences:** macOS blocks the first open. On current macOS the person allows it in System Settings → Privacy & Security → Open Anyway, and the download page explains this. The app is still ad-hoc signed, which Apple silicon requires before it will run any app.

## ADR-006 - Two placement rules: Fit with bars and Crop

**Status:** Accepted

**Decision:** 16:9 and 9:16 use Fit with bars (black bars). 1:1 and 4:3 use Crop, with the person choosing which part is kept. Original needs neither.

**Rationale:** Learner's product choice: the wide and tall frames show the whole picture, and the square and 4:3 frames fill the frame.

**Consequences:** The app needs a crop control for 1:1 and 4:3 only.

## ADR-007 - Commits authored as the owner

**Status:** Accepted

**Decision:** Every commit in `song2vid-app` is authored under the owner's own name and GitHub noreply address. The repo sets this locally, and commits carry no AI co-author line.

**Rationale:** The owner wants the public history to show their own name and account, not Claude or a bot. The noreply address links commits to the account without exposing a personal email.

**Consequences:** The repo-local git identity is set before the first commit and checked before every push. The computer's global git settings are left unchanged.

## ADR-008 - App download hosted on GitHub Releases

**Status:** Accepted

**Decision:** The zipped app is attached to a GitHub Release in `song2vid-app`. The download page links to the latest release.

**Rationale:** Releases keep a version history and checksums next to the source. The page stays a few kilobytes and does not need redeploying for each app version.

**Consequences:** The download page depends on the public GitHub repo. Each new version is a new GitHub Release.

## ADR-009 - MIT licence

**Status:** Accepted

**Decision:** The source code is released under the MIT licence.

**Rationale:** The owner's choice: simple and permissive, so people can learn from it and reuse it.

**Consequences:** `LICENSE` is in the repo root. The bundled third-party agent skills in `.claude/skills/` keep their own MIT licence file.

## ADR-010 - Chief-of-staff build workflow

**Status:** Accepted

**Decision:** The build is run with Matt Pocock's `chief-of-staff` skill and its dependencies (`implement-spec`, `tdd`, `code-review`, `retro`, `to-spec`, `to-tickets`, `writing-for-agents`, `setup-matt-pocock-skills`). They are copied into this repo's `.claude/skills/` from `mattpocock/skills@5863806`. One coordinating Opus session dispatches Sonnet subagents on high reasoning for every ticket. It reviews their work and keeps the docs current.

**Rationale:** The owner wants the implementation done by subagents and the coordinator limited to verifying and writing docs. A repo-local install keeps these skills out of other projects.

**Consequences:** The tickets stay in `tickets/`, which `docs/agents/issue-tracker.md` points to. ADRs stay in `ADR.md`. Each ticket is built on its own branch and merged into the integration branch `build/v1`, which merges into `main` after review.

## ADR-011 - Test on the owner's Mac, CI by hand only

**Status:** Accepted

**Decision:** The gate for every change is `scripts/check.sh` run on the owner's Mac, plus the pre-commit hook. The GitHub Actions `check` workflow runs only when started by hand (`workflow_dispatch`).

**Rationale:** Hosted macOS runners have used up the owner's Actions allowance before. The owner's Mac is fast and is the real target hardware. Push-triggered runs were not starting anyway (docs/wiki/ci-push-trigger.md).

**Consequences:** Verification happens locally before each merge. A manual CI run can still be started for a public-repo check, which is free for public repositories.

## ADR-012 - Owner's sample media stays out of the repo

**Status:** Accepted

**Decision:** Real songs and images for manual testing come from a folder on the owner's Mac outside this repo, and are never committed. Automated tests generate their own media.

**Rationale:** The samples include personal pictures and music that may not be redistributable, and this repo is public.

**Consequences:** Local test scripts read the sample folder path from an environment variable or argument. The repo contains no sample file names or paths.
