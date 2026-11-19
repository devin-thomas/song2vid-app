# S2V-006 - Version 1.0.0 release

Status: ready-for-agent
Blocked by: S2V-005, S2V-009

## Goal

A downloadable app zip on GitHub Releases.

## Scope

- Make a release build (universal, ad-hoc signed) and zip it as `Song2Vid-1.0.0.zip`, with a SHA-256 checksum.
- Publish GitHub Release `v1.0.0` with short notes and the first-open instructions.

## Acceptance Criteria

- The release asset downloads anonymously.
- After a fresh download and unzip, the app is universal (`lipo -info`), its signature is valid (`codesign --verify`), and it opens on this Mac after the first-open step.

- In the sandboxed release build, saving over an existing MP4 through the real save panel works on the internal disk and on an external volume, and a 96 kHz source makes a 48 kHz AAC track (these were checked on the review-fixes build; repeat on the release build).

## Dependencies

S2V-005, S2V-009.
