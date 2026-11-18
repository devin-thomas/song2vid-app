# S2V-001 - Public repo and app skeleton

Status: claimed
Blocked by: none

## Goal

A public `song2vid-app` repo containing the plan files and a macOS app that builds and opens an empty window.

## Scope

- Set the repo-local git identity to the owner (ADR-007). Add `.gitignore` and the licence (SPEC §9), and a short README that links to the plan files.
- Xcode project: a SwiftUI app plus unit-test and integration-test targets. macOS 14+, universal, ad-hoc signing.
- Keep `project.pbxproj` stable while tickets run in parallel. Put all logic in a local Swift package (`Song2VidCore`, testable with `swift test`), and use synchronized folder groups for the app target, so new source files don't edit the project file.
- One check command, `scripts/check.sh`: build, all tests, and the public-safety scan (no `/Users/`, emails other than the noreply address, tokens, IP addresses, `.env` files).
- A tracked git hook (`.githooks/pre-commit`, enabled with `core.hooksPath`) that runs the safety scan and refuses commits whose author isn't the repo-local identity.
- A GitHub Actions workflow on a macOS runner that runs `scripts/check.sh` on every push and pull request.
- Create the public GitHub repo, push `main` and the integration branch `build/v1`, and turn on secret scanning and push protection.

## Acceptance Criteria

- `scripts/check.sh` passes from a clean clone, and CI passes on GitHub.
- A deliberately bad commit (a fake token, or the wrong author) is refused by the hook. This is tested, then discarded.
- `git log --format='%an <%ae>'` shows only the owner's name and noreply address.
- A scan of the repo finds no `/Users/`, emails, tokens, or IP addresses.
- The repo is public, and its `main` branch matches the local branch.

## Dependencies

None.
