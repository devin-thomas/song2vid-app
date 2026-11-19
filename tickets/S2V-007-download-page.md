# S2V-007 - Download page live on Cloudflare Pages

Status: ready-for-human
Blocked by: S2V-006

## Goal

`song2vid.pages.dev` (or the fallback) serves the minimal download page.

## Scope

- One static `site/index.html` (SPEC §8), deployed with Wrangler to the chosen Cloudflare account.
- If the name is held by one of the owner's own projects, show what is there and get the owner's yes before replacing it.

## Acceptance Criteria

- The live URL serves this page, not a login or placeholder page.
- The Download button fetches the v1.0.0 zip.
- The page reads correctly at phone width with zoom allowed, and makes no third-party requests.
- The owner downloads from the live page, opens the app, makes a video and plays it. This is recorded as an owner report, with the device named.

## Dependencies

S2V-006.

## Comments

- 2026-11-19: Deployed to Cloudflare Pages as the `song2vid` project; https://song2vid.pages.dev serves `site/` byte-for-byte. Checked by the coordinator: HTTP 200 with the CSP from `site/_headers`; the Download for Mac link resolves to the v1.0.0 release zip (sha256 matches the release); icons load; no horizontal scroll at 375 px. Waiting on the last criterion, the owner report.
