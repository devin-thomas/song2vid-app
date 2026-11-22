# Song2Vid

Song2Vid is a tiny native macOS app that turns a song and an image into a video. Choose or drop in an audio file and a picture, pick a frame shape and resolution, and save an MP4.

## This repo is a worked example

Song2Vid was planned and built in public as a demonstration of building software with AI, using the [Starter Pack](https://starter.uppercut-labs.com) course (Phase 2) and its Grill to Build planning process. Everything that shaped the build is committed here, not just the code.

## Start from here

Read these in order:

1. [PROJECT.md](PROJECT.md): what is being built, for whom, and what is out of scope.
2. [GLOSSARY.md](GLOSSARY.md): the words used everywhere (Frame Shape, Resolution, Crop, Fit with bars).
3. [ADR.md](ADR.md): each consequential decision and why.
4. [SPEC.md](SPEC.md): the exact behavior the app must have.
5. [tickets/](tickets/): the build broken into ordered work units, with `Status:` and `Blocked by:` lines.
6. [Ideas.md](Ideas.md): what was deliberately left for later.

How it was built:

- **[.claude/skills/](.claude/skills/):** Matt Pocock's [`chief-of-staff`](.claude/skills/chief-of-staff/SKILL.md) skill and the skills it relies on (`implement-spec`, `tdd`, `code-review`, `retro`, `to-spec`, `to-tickets`, `writing-for-agents`, `setup-matt-pocock-skills`). They were copied from `mattpocock/skills@5863806` under its [MIT licence](.claude/skills/LICENSE-mattpocock-skills), and installed in this repo only so they don't affect other projects. One coordinating agent (Claude Opus) dispatches a fresh subagent (Claude Sonnet) per ticket, then checks each result and keeps the docs current.
- **[docs/agents/](docs/agents/):** how agents find tickets and domain docs in this repo.
- **[docs/wiki/](docs/wiki/):** the coordinator's dated record of decisions, problems and verification as the build happened.
- **[CLAUDE.md](CLAUDE.md):** the short note every agent reads first.

To run the same workflow from here, open this repo in Claude Code, read `.claude/skills/chief-of-staff/SKILL.md`, and pick the next ticket whose `Blocked by:` tickets are all resolved.

## Build and check

Requires macOS 14+ and Xcode.

```bash
git config core.hooksPath .githooks
```

```bash
scripts/check.sh
```

The first command enables the commit hooks, which block secrets, personal paths and co-author lines in files and commit messages. The second builds the app, runs all tests and runs the safety scan on the files and on this branch's commit messages.

To also keep the names of real sample media out of the repo, list them one per line in a file outside the repo and set `S2V_DENYLIST` to its path before committing or running the check.

## The `song2vid` command and the Agent Guide

Version 1.1 adds a command that makes the same video as the window. It ships inside the app and is built from the same `Song2VidCore` package.

```bash
mkdir -p ~/.local/bin
ln -sf /Applications/Song2Vid.app/Contents/Helpers/song2vid ~/.local/bin/song2vid
song2vid make song.mp3 cover.png -s 1:1 -r 480p
```

- Every option, the JSON output, the progress modes and the exit statuses are on the docs page, [song2vid.pages.dev/docs](https://song2vid.pages.dev/docs).
- [skills/song2vid/SKILL.md](skills/song2vid/SKILL.md) tells an agent how to make a video by either route, the app's window or the command. `song2vid --skill` prints it, and the site serves the same text at [song2vid.pages.dev/agent.md](https://song2vid.pages.dev/agent.md). `scripts/build-agent-md.sh` makes that copy, and `scripts/check.sh` fails if it drifts.
- The download page has an Agent Handoff: one click copies a short prompt for ChatGPT, Claude, Grok Bot or Muse that points the agent at the guide.

## Licence

[MIT](LICENSE), copyright 2026 devin.
