# S2V-007 - Download page live on Cloudflare Pages

Status: ready-for-agent
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
