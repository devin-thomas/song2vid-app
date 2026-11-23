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

## ADR-013 - The command ships inside the app

**Status:** Accepted (2026-11-21)

**Decision:** The `song2vid` command is built into Song2Vid.app, and the person or their agent links it onto the PATH. There is no separate command download or Homebrew tap.

**Rationale:** The owner chose one download. One version number covers the app and the command, and the release process stays as it is.

**Consequences:** The command is signed without the app sandbox, which would otherwise block it from reading files passed on the command line. Whether macOS lets a command inside a downloaded, ad-hoc signed app run after Open Anyway must be checked on this Mac early in the build. The Agent Guide documents the link step. Rejected: a separate command zip on GitHub Releases, and a Homebrew tap.

## ADR-014 - The command never replaces a file unless told to

**Status:** Accepted (2026-11-21)

**Decision:** `song2vid make` stops with an error if the output already exists, unless `--overwrite` is given. `--dry-run` reports what would be made and writes nothing.

**Rationale:** An agent may run the command without a person watching, and a save dialog no longer asks first.

**Consequences:** The Agent Guide tells agents to ask the person before using `--overwrite`.

## ADR-015 - The agent skill is also the public Agent Guide

**Status:** Accepted (2026-11-21)

**Decision:** The skill lives at `skills/song2vid/SKILL.md`, written with Matt Pocock's `writing-for-agents`, and the same instructions are served at `song2vid.pages.dev/agent.md`.

**Rationale:** Agents that install skills and agents that only read a web page both get the same instructions, and the handoff prompt can stay one short sentence pointing at the guide.

**Consequences:** The guide must stay readable as plain Markdown and is published with each release.

## ADR-016 - Agent Handoff for ChatGPT, Claude, Grok Bot and Muse

**Status:** Accepted (2026-11-21)

**Decision:** The download page's handoff offers ChatGPT, Claude, Grok Bot and Muse. Claude Code and Codex are not offered.

**Rationale:** The owner's choice: the people who find the download page use chat agents.

**Consequences:** Each mark must be authentic, and none may be dropped. ChatGPT, Claude and Grok Bot come from the owner's `agent-prompts` set (Grok Bot from asvg.app, per its credits file). Muse comes from LobeHub Icons 1.104.0 (MIT), which labels it "Muse (Meta)" for muse.ai. Credits and licence notices ship beside the artwork. Phase 3's terminal test uses Claude Code separately.

## ADR-017 - The handoff asks for the outcome, not the method

**Status:** Accepted (2026-11-21)

**Decision:** The Agent Handoff prompt only asks the agent to use Song2Vid to make a video from a song and an image, and points at the Agent Guide. It does not tell the agent to use the command, or to coach the person through Terminal.

**Rationale:** The owner's choice. Agents that operate apps and agents with a terminal are different and both are growing; the agent should pick the route it can do. The handoff stays a simple, non-technical step, and technical users read the docs page.

**Consequences:** The Agent Guide describes both the app's window and the command. A separate docs page serves people who use the command directly. This replaces the coordinator's round 2 proposal of a Terminal walkthrough.

## ADR-018 - Progress is always visible, headed or headless

**Status:** Accepted (2026-11-21)

**Decision:** The command never leaves anyone waiting without a sign of progress. In a terminal it draws a live progress bar; headless, it reports the same progress in a form an agent can read while the run is going. Every feature works headless.

**Rationale:** The owner's rule: people should never feel they are waiting on something that isn't happening, and agents need to check on long runs.

**Consequences:** Progress is part of the command's tested behavior, not decoration. The headless format is ADR-019.

## ADR-019 - Headless progress is JSON Lines on stdout

**Status:** Accepted (2026-11-21)

**Decision:** With `--json`, `make` writes one JSON object per line to stdout: progress lines about every half second, then exactly one result or error line.

**Rationale:** An agent that runs the command in the background can read the newest line at any time, with no extra files or commands. It works the same in every agent harness.

**Consequences:** stdout carries only JSON lines under `--json`. Rejected: a `--progress-file` option (parked in Ideas), and both together.

## ADR-020 - `--update` reports, the person installs

**Status:** Accepted (2026-11-21)

**Decision:** `song2vid --update` checks GitHub for the latest release and says whether it is newer, with the download page link. It does not download or replace anything.

**Rationale:** Replacing the app means approving it again with Open Anyway, which only the person can do. A read-only check is easy, safe and has no destructive path.

**Consequences:** It is the only part of the command that uses the network. Rejected: downloading, verifying and replacing the app after a confirmation.

## ADR-021 - The site's Markdown, sitemap and llms.txt are generated from its pages

**Status:** Accepted (2026-11-22)

**Decision:** `site/index.html` and `site/docs/index.html` are the source of truth. One script, `scripts/build-site.py`, makes `index.md`, `docs.md`, `llms.txt` and `sitemap.xml` from them (descriptions from `<meta name="description">`, dates from the visible `<time>` element, addresses from the canonical link). A file list in that script says what may be published, and `scripts/check-site.sh` fails if `site/` holds anything else or if a generated file differs from a fresh build. `robots.txt` is written by hand.

**Rationale:** The lesson's rule is that a Markdown copy and the HTML must never disagree. Generating the copies makes that a fact the check can prove. A file list means a stray file cannot be published by accident, as the allowlist of fields does for data.

**Consequences:** Changing a page means running the script (the check says so). Rejected: writing the Markdown and `llms.txt` by hand (they would drift); a framework or build tool for a two-page site; structured data, which this site does not need.

## ADR-022 - Song2Vid for Windows uses the desktop-app skill's Electron starter

**Status:** Accepted (2026-11-22)

**Decision:** Build the Windows version from the `web-three-systems` starter in the public `desktop-app` skill (beta branch): a React page in its Electron shell over a bundled tool. Ship Windows only; the Mac app stays SwiftUI.

**Rationale:** The owner wants to prove the skill works for an outside developer with as little extra work as possible. Song2Vid's file pickers, drop target and crop preview put it on the skill's content-app branch rather than the fastwin utility branch.

**Consequences:** About 300 MB installed against the Mac app's few megabytes, under the skill's 300 MB idle memory budget. Changes to the starter are kept small and listed, so they can go back to the skill as feedback. Supersedes the last line of ADR-001's consequences ("a separate build later").

## ADR-023 - A proportionate premium bar: starter gates plus an applicability ledger

**Status:** Accepted (2026-11-22)

**Decision:** Keep every scripted check the starter ships, adapted to Song2Vid. Give every premium-bar rule a ledger line: applies (with the check that proves it) or N/A (with a one-line reason). Do manual rules only where they touch the main journey. Run one independent critic round. The owner's daily use is the premium verdict.

**Rationale:** The scripted checks already pass on the untouched starter, so keeping them costs only the edits to their marked blocks. Most of the bar's weight is in rules Song2Vid cannot trigger (no text fields, no long lists, no sign-in, no Linux or macOS build) and in process steps sized for bigger apps.

**Consequences:** Rejected: the full bar with every process step (ceremony out of proportion to one window and one job); a hand-picked subset that deletes the starter's other checks (drifts from the skill and loses the starter's free coverage).

## ADR-024 - The Windows tool speaks the existing command contract

**Status:** Accepted (2026-11-22)

**Decision:** The bundled tool is `song2vid.exe`, implementing SPEC section 14 (`check`, `make`, options, exit statuses, `--json` with `api_version` 1). The Electron adapter turns its JSON lines into the starter's job states. The skill's `--events 1` protocol is not added.

**Rationale:** The skill's packaging reference says an existing tool keeps its form. One contract means one Agent Guide and one docs page for both systems, and the Windows command behaves like the Mac one.

**Consequences:** The starter's adapter, stand-in tool scenarios and capability check are rewritten against section 14 instead of copied. Where section 14 lacks something the adapter needs (cancel by closing stdin, which Windows needs because it has no graceful signal), it is added to section 14 for both systems.

## ADR-025 - Windows encodes with the hardware it has

**Status:** Accepted (2026-11-22, rounds 1 and 2)

**Decision:** The Windows tool can make HEVC as well as H.264 and chooses the encoder automatically: NVENC, then a Media Foundation hardware encoder (AMD, Intel), then Microsoft's software H.264. The result names the encoder; a hardware encoder that fails to start falls back once, with a note. FFmpeg is a small LGPL build with NVENC (loaded from the driver at run time) and Media Foundation; no GPL encoders.

**Rationale:** The owner will use the app daily on an RTX 4090 and does not want the GPU left idle.

**Consequences:** No setting for the encoder in the window. A PC with no hardware HEVC encoder makes H.264 only (ADR-026). Intel's hardware path ships unverified; NVENC is verified on Titan and AMD on the DeskMini. Rejected: x264/x265 (GPL binary inside an MIT app); an encoder picker in the window.

## ADR-026 - A Codec choice on both systems, remembered

**Status:** Accepted (2026-11-22)

**Decision:** Both apps get a Codec picker (H.264 or HEVC) that remembers the last choice, H.264 on first run; both commands get `--codec`. The Mac app and command gain HEVC in the same release as Song2Vid for Windows. On Windows, HEVC is disabled with a reason when the PC has no hardware HEVC encoder.

**Rationale:** The owner makes videos daily on a 4090 and wants smaller HEVC files without picking it every time. One contract for both systems keeps one Agent Guide.

**Consequences:** The first remembered setting in either app; the rest of "Remember last settings" stays in Ideas. The Mac release grows by an AVFoundation HEVC path. Rejected: HEVC only in the command; Mac HEVC later.

## ADR-027 - One 1.2.0 release for both systems

**Status:** Accepted (2026-11-22)

**Decision:** Song2Vid for Windows and the Mac's HEVC change ship together as Song2Vid 1.2.0: one GitHub release with a Mac zip and a Windows zip, one version number on both commands.

**Rationale:** Both systems share one command contract and one Agent Guide; one version keeps `--version`, `--update` and the docs page simple.

**Consequences:** Neither system ships until both are ready. `--update` compares one version on both. Rejected: a separate Windows 1.0.0 with its own release and update check.

## ADR-028 - The command contract grows by addition within api_version 1

**Status:** Accepted (2026-11-22, while writing SPEC Part 4)

**Decision:** Version 1.2.0 adds `--codec`, `--cancel-on-eof`, the `encoders` and `preview` commands, the `codec`, `encoder` and `encoder_fallback` keys, and the `codec_unavailable` and `output_in_use` codes, to both commands, without a new `api_version`. Section 14.5's rule becomes: keys, line types and commands may be added within a version, and never removed, renamed or given a new meaning.

**Rationale:** Agents and scripts written for 1.1 keep working. A new `api_version` would break them for additions they can ignore. `preview` lets the Windows app show HEIC and TIFF, which Chromium cannot, oriented exactly as encoded, and lets an agent see the picture. `--cancel-on-eof` gives the app a way to cancel a windowless child on Windows without making stdin matter to anyone who does not ask for it.

**Consequences:** The docs page records the version each key arrived in. Rejected: `api_version` 2; Windows-only commands outside the shared contract; reading stdin by default, which would cancel a run whose stdin is closed.

## ADR-029 - The Windows command is Rust over a bundled FFmpeg, with shared frame fixtures

**Status:** Accepted (2026-11-22, while writing SPEC Part 4)

**Decision:** `song2vid.exe` is a Rust program that implements the contract and runs a bundled LGPL FFmpeg and FFprobe as child processes in a kill-on-close job object. The frame math is ported from `OutputFrame`, and parity is proven by `fixtures/frame-math.json`, written by the Swift tests and read by both suites.

**Rationale:** The skill's tool contract wants a real executable with a static runtime and children it owns. Rust builds that with `crt-static`, handles UTF-16 arguments, and is covered by the owner's `style` guide. Song2VidCore depends on AVFoundation and cannot run on Windows. Swift on Windows would bring a runtime and a toolchain for a few hundred lines of math. A fixture file turns "no copied logic" into "copied logic proven identical".

**Consequences:** Two implementations of the frame rules, held together by the fixture check. FFmpeg's command line becomes the encoding seam on Windows. Rejected: Swift on Windows; C++; FFmpeg's libraries linked into the tool, which brings more licence and build work for no gain over child processes.

