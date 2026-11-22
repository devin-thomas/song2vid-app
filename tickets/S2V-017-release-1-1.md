# S2V-017 - Release 1.1.0 and deploy the site

Status: ready-for-human
Blocked by: S2V-016

## Goal

1.1.0 is downloadable and the site serves the handoff, docs and Agent Guide (SPEC §17).

## Scope

- Build, sign and zip as in 1.0.0, with the command inside. Publish the GitHub release with its SHA-256. Update the Download link to the 1.1.0 zip.
- Deploy `site/` to the `song2vid` Pages project with Wrangler, run only from this repo.
- The coordinator makes one video per Frame Shape with the command from the owner's sample folder (path passed as an argument; nothing committed) and checks each with ffprobe.

## Acceptance Criteria

- The release check in SPEC §18 passes from a clean folder outside the repo.
- `https://song2vid.pages.dev/agent.md` returns the skill as Markdown; `/docs` and the handoff work live.
- The five sample-media videos have the right sizes, lengths and both tracks.
- Releasing and deploying are confirmed with the owner before they happen.
- The owner approves the downloaded 1.1.0 app with Open Anyway (also closing S2V-010's after-approval check), then the coordinator runs the command from Terminal and records the result.

## Dependencies

S2V-016.

## Comments

- 2026-11-22 (coordinator): Everything that can be done without publishing is done. `scripts/build-release-zip.sh` built `Song2Vid-1.1.0.zip` (2.1 MB; universal app and command, ad hoc signed, sandboxed app without `get-task-allow`, unsandboxed command). Unzipped into a clean folder outside the repo, the command printed `song2vid 1.1.0` and `--skill` matched `skills/song2vid/SKILL.md`. The coordinator made one video per Frame Shape with that unzipped command from the owner's sample folder (paths passed as arguments, outputs outside the repo, nothing committed): 16:9 1080p (1920×1080), 9:16 1080p (1080×1920), 1:1 480p (480×480), 4:3 2160p cropped to the bottom (2880×2160, enlarged) and Original (1002×1002 from a 1003×1003 image). ffprobe: H.264 High at 30 fps and AAC LC in each; lengths 128.000, 125.217, 144.000, 153.600 and 128.000 s against sources of 128.000, 125.217, 144.000, 153.600 and 128.000 s; a full ffmpeg decode of each gave no errors. The 4:3 and 9:16 frames were viewed.
- The Download link on the landing page now points at the 1.1.0 zip and the README describes the command. This is on `build/v2` and not published.
- Waiting for the owner: (1) go-ahead to merge `build/v2` into `main`, tag `v1.1.0`, publish the GitHub release with its SHA-256, and deploy `site/` to the `song2vid` Pages project; (2) after that, Open Anyway on the downloaded 1.1.0 app, so the coordinator can run the command from Terminal and record the result (this also closes S2V-010's after-approval check); (3) the live checks of `/agent.md`, `/docs` and the Copy button over HTTPS.
- 2026-11-22 (coordinator): Released with the owner's go-ahead. `build/v2` was merged into `main` (fast-forward), tagged `v1.1.0` and published as https://github.com/devin-thomas/song2vid-app/releases/tag/v1.1.0 with `Song2Vid-1.1.0.zip` and `Song2Vid-1.1.0.zip.sha256`. SHA-256 `9038942fa41fa948f32bdd6862ca0a6db9713c838765b8c1384c6e764deb0b13`. The zip was rebuilt from the tagged tree; downloaded anonymously through the page's own `releases/latest/download/Song2Vid-1.1.0.zip` link, its SHA-256 matched. Unzipped into a clean folder: `song2vid --version` printed `song2vid 1.1.0`, `--skill` matched the repo file, and `--update` against the real GitHub API said "up to date" (text and JSON). This is the first check of `--update` against the real API.
- **Not deployed.** `wrangler` on this Mac is not logged in to Cloudflare (no token in the environment either), and the login is the owner's to do. Until the site is deployed, the live page still links the 1.0.0 zip (which still exists), `/agent.md` and `/docs` are not live, and the Agent Handoff points at an `agent.md` that returns nothing. After `wrangler login`, the coordinator runs `wrangler pages deploy site --project-name=song2vid` from this repo only (the 1.0.0 lesson) and checks `/agent.md`, `/docs` and the Copy button live.
- Still the owner's: Open Anyway on the downloaded 1.1.0 app, then the coordinator runs the command from Terminal and records the result (also closing S2V-010's after-approval check). `docs/wiki/phase-3-proof.md` has the S2V-018 steps and the prompt.
