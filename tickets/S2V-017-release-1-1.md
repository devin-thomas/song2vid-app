# S2V-017 - Release 1.1.0 and deploy the site

Status: ready-for-agent
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
