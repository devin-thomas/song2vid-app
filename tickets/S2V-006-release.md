# S2V-006 - Version 1.0.0 release

Status: resolved
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

## Comments

Released as tag `v1.0.0` (annotated, on commit e4ba1db): https://github.com/devin-thomas/song2vid-app/releases/tag/v1.0.0

Asset `Song2Vid-1.0.0.zip`, SHA-256 `9b10afeccef816280129449bfbdd0a20d85d9ba99c2134b9f090d7b436ea7458` (also attached as `Song2Vid-1.0.0.zip.sha256`). Built in the Release configuration, universal (arm64 and x86_64), ad-hoc signed, zipped with `ditto -c -k --keepParent`.

Checked: the bundle has version 1.0.0, the expected bundle ID and the app icon. After an anonymous download, the checksum matches and `lipo` and `codesign --verify --deep --strict` pass. A quarantined copy is rejected by `spctl` (expected, ADR-005). With quarantine cleared on that copy only, the app opens its window.

Not repeated on the release build: the sandboxed save-over-an-existing-MP4 check (internal disk and external volume) and the 96 kHz source check from the acceptance criteria. Both still need a manual run. The Release build also carries the `get-task-allow` entitlement that Xcode adds to ad-hoc builds; turning that off with `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` removed the sandbox entitlements too, so it was left as built.
