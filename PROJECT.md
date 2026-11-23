# Song2Vid — Project brief

## What it is

Song2Vid is a Mac desktop app. You give it one audio file and one image file, pick a **Frame Shape** and **Resolution**, and it makes a video: the image stays on screen for the whole song. A small download page on Cloudflare Pages (`*.pages.dev`) lets other people download the app and read short instructions.

The project is also a public demonstration of building with AI using the Starter Pack and the Grill to Build planning process. The plan files, `docs/agents/`, the wiki in `docs/wiki/`, and the agent skills in `.claude/skills/` are public on purpose, so someone can see the whole setup or start from this point themselves.

## Who it is for

The owner, plus anyone who finds the download page. The app is not signed with a paid Apple Developer ID, so the download page tells people how to open it the first time (right-click → Open).

## Agreed so far

- Name: **Song2Vid**. Source repository: `song2vid-app` on GitHub, **fully public**, including these plan files (ADR-004).
- Platform: native macOS app (ADR-001), Apple silicon.
- One song at a time: choose or drag in an audio file and an image, choose options, make the video, choose where to save it.
- **Drag and drop is required.** Drop a song, an image, or both. If a slot is already filled, a dialog asks to Replace or Keep Current (the safe default) before anything changes.
- Song2Vid has its own original icon, showing a song becoming a video, also used on the download page.
- **Frame Shapes:** 16:9, 9:16, 1:1 (square), 4:3, and Original (the image's own exact dimensions).
- **Resolutions:** 480p, 1080p, 2160p, available for every Frame Shape except Original. "p" is the short side of the frame (see `GLOSSARY.md`):

  | Frame Shape | 480p | 1080p | 2160p |
  | --- | --- | --- | --- |
  | 16:9 | 854×480 | 1920×1080 | 3840×2160 |
  | 9:16 | 480×854 | 1080×1920 | 2160×3840 |
  | 1:1 | 480×480 | 1080×1080 | 2160×2160 |
  | 4:3 | 640×480 | 1440×1080 | 2880×2160 |

- **Fit with bars** for 16:9 and 9:16: the whole image is shown, scaled to fit, with black bars filling the rest.
- **Crop** for 1:1 and 4:3: the image fills the frame, and the person drags the image in a live preview to choose which part is kept. It starts centered.
- **Enlarging:** if the image is smaller than the chosen Resolution, it is enlarged anyway and a short note says so.
- **Original sizing:** the image's exact shape, kept within 4K (3840×2160 wide, 2160×3840 tall). A larger image is scaled down. If it is less than 1% too big, a few edge pixels are trimmed instead of scaling, which keeps it sharp. Odd pixel sizes lose one pixel, because video needs even sizes.
- Download page: minimal, with a download link and brief instructions only. Address `song2vid.pages.dev`, falling back to `song2vid-app.pages.dev`. Hosted on the same Cloudflare account as the earlier `stock-example` and `beat2vid` projects. If the name is held by one of the owner's own older projects, that page may be replaced (the owner confirms at deploy time).
- Commits show the owner's own name and GitHub account, not Claude or a bot (ADR-007).
- Public-from-day-one rules (ADR-003).

## Phase 3: make Song2Vid usable by agents (version 1.1)

Started 2026-11-21. Goal: an agent can make a Song2Vid video for someone, and people can hand that job to the agent they already use. This is the Starter Pack Phase 3 **agent-cli** level, extending this Phase 2 build.

Agreed so far (round 1):

- **Command:** a `song2vid` command-line tool that calls `Song2VidCore`, with no copied logic. It ships **inside Song2Vid.app** (ADR-013); the person or their agent links it onto the PATH. Release **1.1.0**, which also removes the leftover debugging permission while keeping the app sandbox.
- **Existing files:** `song2vid make` never replaces an existing output unless `--overwrite` is given, and `--dry-run` reports the output size and placement without writing anything (ADR-014). The person's audio and image files are never changed.
- **Agent skill:** written with the `writing-for-agents` skill, kept at `skills/song2vid/SKILL.md`, and served publicly as the **Agent Guide** at `song2vid.pages.dev/agent.md` (ADR-015).
- **Agent Handoff:** on the download page, for **ChatGPT, Claude, Grok Bot and Muse** (Meta's personal agent). Claude Code and Codex are not on it (ADR-016). All four marks are authentic and must be shown; none may be skipped (Muse and Grok Bot artwork sources are in ADR-016). The prompt is simple and non-technical: it asks the agent to use Song2Vid to make a video from a song and an image, and points at the Agent Guide. The agent decides whether to use the app's window or the command (ADR-017).
- **Agent Guide** covers both routes: the app's window, for agents that operate apps, and the command, for agents with a terminal.
- **Docs page:** a human documentation page on the download site (`song2vid.pages.dev/docs`) for people who use the command directly.
- **Commands (first version):** `song2vid check` (read-only: song length, image size, and the output size for each Frame Shape) and `song2vid make`. Options also include `--help`, `--version`, `--skill` (prints the agent skill), `--repo` (prints the source repo link) and `--update` if it is easy. **Every option has a one-letter short form.**
- **Progress is always visible (ADR-018).** Nobody should wait on something that seems stalled. In a terminal (headed), a live progress bar with stage, percent, elapsed time and time left; a moving indicator while the percent is not known yet. Headless (agents, scripts), the same progress is available in machine-readable form while the run is going, so an agent can check on it mid-run. Everything the command does works headless.
- **Headless progress:** with `--json`, `make` prints one JSON line of progress about every half second, then a final result line, so an agent running it in the background can read the newest line at any time (ADR-019). A progress file is not offered.
- **`--update`** only reports whether a newer release exists and links the download page. The person replaces the app themselves, because a new copy needs Open Anyway again (ADR-020).
- **Short options:** `-h` help, `-v` version, `-s` shape, `-r` resolution, `-c` crop, `-o` out, `-w` overwrite, `-n` dry-run, `-j` json, `-q` quiet, `-S` skill, `-R` repo, `-u` update.
- **Other command defaults** (stated by the coordinator, not objected to): Ctrl-C cancels, deletes the partial file and exits 130; results go to stdout, progress and errors to stderr; colour and the animated bar appear only in a real terminal, honour `NO_COLOR`, and `-q` turns them off; `make` checks every input before it starts encoding; each command has its own `--help`, and a mistyped option gets a suggestion.
- **Test media:** test videos are made from the owner's sample files outside the repo (ADR-012); they are never committed.
- **Workflow:** same as Phase 2: Grill to Build, the chief-of-staff workflow with Sonnet builders, commits as `devin`, tests on this Mac.
- **Phase 3 proof:** a new Claude Code session that has never seen the project runs the installed command, makes a video, and hits one deliberate failure; the owner confirms. This is separate from the handoff's agent list.

## Windows version (Song2Vid for Windows 1.0)

Started 2026-11-22. Goal: Song2Vid on Windows, built on the public `desktop-app` skill (`devin-thomas/skills`, branch `beta`, folder `beta/desktop-app`) as an outside developer would use it: copy the `web-three-systems` Electron starter and change as little of it as possible. The owner will use it daily on a Windows PC with an RTX 4090.

Agreed so far (round 1):

- **Shell:** the skill's content-app branch: a React page in the starter's Electron shell, with the work done by a bundled command-line tool. Windows is the only shipped target. The Mac app stays SwiftUI. The starter's Mac build is used only to run the headless checks during development (ADR-022).
- **Quality bar: starter gates plus an applicability ledger (ADR-023).** Every scripted check the starter already ships stays and is adapted to Song2Vid (typecheck, test, shell check, audit, visual baselines, crash, fuses, planted breaks). Every premium-bar rule gets a line in a ledger: applies (with its check), or N/A with a one-line reason. Manual rules are done only where they touch the main journey. One independent critic round on screenshots. The owner's own daily use decides whether it is premium.
- **Tool contract: SPEC section 14 (ADR-024).** The bundled tool is a Windows `song2vid.exe` with the same `check` and `make` commands, options, exit statuses and `--json` lines (`api_version` 1) as the Mac command. The Electron adapter translates those lines; the skill allows a tool to keep its existing form. Anything added for Windows is added to the one contract.
- **Encoding: use the hardware (ADR-025).** `song2vid.exe` picks the fastest encoder the PC has, with no setting in the window: NVIDIA NVENC, then a hardware encoder through Media Foundation (AMD or Intel), then Microsoft's software H.264. The finished message and the JSON result name the encoder used. If a hardware encoder fails to start, the tool falls back once and says so. FFmpeg is a small LGPL build: no x264 or x265.
- **Codec (ADR-026):** a Codec picker in the window, H.264 or HEVC. It remembers the last choice; H.264 on first run. HEVC is disabled with a short reason on a PC with no hardware HEVC encoder, since Windows' software HEVC needs a paid Store extension. The command gets a matching `--codec` option.
- **The Mac gains HEVC in the same release (ADR-026):** the Mac app and Mac command get the same picker and `--codec`, through AVFoundation.
- **Test machines:** Titan (Windows 11 Pro, RTX 4090: NVENC) and the DeskMini (Windows 10, AMD Ryzen 5 3400G with Vega graphics: AMD hardware through Media Foundation). Intel hardware stays unverified and is listed so in the release notes.
- **Where checks run:** the DeskMini is the test PC. Every check that opens a Song2Vid window (crash recovery, the installed-app check, the focus sampler) runs there whenever needed. Titan runs headless checks and NVENC encodes only, and opens a window only when the owner says it is free.
- **Reaching the DeskMini:** over Tailscale at its tagged address (`deskmini`). Its SSH server is not answering yet (port 22 timed out on 2026-11-22), so the owner turns on Windows' OpenSSH Server there. DeskMini checks wait for that; nothing else does.
- **Release (ADR-027):** one GitHub release, **Song2Vid 1.2.0**, with a Mac zip and a Windows zip. The download page offers both. `--version` and `--update` behave the same on both systems.
- **Command on PATH:** like the Mac, a documented step. The Agent Guide and docs page give one PowerShell line that adds the installed command's folder to the user's PATH. The installer never changes PATH.
- **Scope and place:** the window app **and** `song2vid.exe` for people and agents to put on PATH, so the Agent Guide covers Windows too. The code lives in `windows/` in this repository and shares `SPEC.md`, `GLOSSARY.md` and `ADR.md`.

Settled while writing SPEC Part 4: the contract grows by addition within `api_version` 1, with `encoders`, `preview` and `--cancel-on-eof` added to both commands (ADR-028); the Windows command is Rust over a bundled FFmpeg, with frame math proven identical to the Swift code by a shared fixture file (ADR-029).

Defaults taken from the skill or earlier phases (stated, not asked; the owner can change any):

- The Windows app is dark on first run (the skill's rule for every desktop app). The Mac app's look is unchanged.
- Installed per user under `%LOCALAPPDATA%\Programs\Song2Vid`, unsigned. The download page says how to get past SmartScreen ("More info", then "Run anyway"), as it already explains Open Anyway on the Mac.
- Every change made to the starter's files, and every rule or process step cut, goes in `windows/SKILL-NOTES.md`, so the outside-developer run doubles as feedback for the skill.
- Same build workflow as Phases 2 and 3: chief-of-staff with Sonnet builders, commits as `devin`.

## Not in scope

- Several songs at once, editing tools. Parked in `Ideas.md` as update ideas.
- Paid Apple signing (ADR-005).

## Open questions

None. Phase 3 round 3 answers: JSON Lines progress (a), `--update` reports only (a), and the recommended short options.

## Discovery progress

- Workflow: Grill to Build (default).
- Phase 2: 3 of 5 rounds, 10 of 20 questions. Discovery closed; plan approved 2026-11-18.
- Phase 3: 3 of 5 rounds, 10 of 20 questions. Discovery closed 2026-11-21.
- Windows: 3 of 5 rounds, 12 of 20 questions (2026-11-22). Discovery closed. SPEC Part 4 (sections 22 to 32), ADR-028 and ADR-029 (settled while writing it) and tickets S2V-022 to S2V-034 written; waiting for the owner's go-ahead to build. Planning branch `plan/windows`, cut from `ticket/S2V-021`, because `build/agent-ready-site` is not on GitHub yet. SPEC Part 2 and tickets S2V-010 to S2V-018 written; waiting for the owner's go-ahead to build.
- **Plan approved 2026-11-18**, with changes: drag and drop (with the replace dialog) and an app icon were added.
- **Build workflow:** the owner asked for Matt Pocock's `chief-of-staff` skill, installed in this repo under `.claude/skills/`. Opus coordinates, verifies and writes the docs. Sonnet subagents on high reasoning build each ticket.

## System model

```mermaid
flowchart LR
  A[Audio file] --> APP[Song2Vid app]
  I[Image file] --> APP
  O[Frame Shape + Resolution + Crop] --> APP
  APP --> V[MP4 video saved where the person chooses]
  PAGE[Download page on pages.dev] -->|link| DL[App download]
  DL --> APP
  APP -. contains .-> CLI[song2vid command]
  AG[Agent on the Mac] -->|runs| CLI
  CLI --> V
  GUIDE[Agent Guide agent.md on pages.dev] --> AG
  PAGE -->|link| WDL[Windows download]
  WDL --> WAPP[Song2Vid for Windows: Electron shell + React page]
  WAPP -->|runs, reads JSON lines| WCLI[song2vid.exe]
  WAG[Agent on Windows] -->|runs| WCLI
  WCLI -->|NVENC / Media Foundation / software| V
  GUIDE --> WAG
  PAGE -->|Agent Handoff prompt| CHAT[ChatGPT / Claude / Grok Bot / Muse]
  CHAT -->|reads| GUIDE
```
