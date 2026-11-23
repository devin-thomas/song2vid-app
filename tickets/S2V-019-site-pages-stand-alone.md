# S2V-019 - Each page states the facts and its own address

Status: ready-for-agent
Blocked by: none

## Goal

Each public page gives one address, its facts in plain HTML, a visible updated date and a link to its Markdown copy (SPEC §20).

## Scope

- `site/index.html`: canonical link to `https://song2vid.pages.dev/`; a visible line "Free · Version 1.1.0 · Requires macOS 14 or later" in place of the current requirements line; "Updated" date in a `<time datetime>`; `<link rel="alternate" type="text/markdown" href="/index.md">`; the footer links to the Agent Guide (`/agent.md`), the Markdown copy and `/docs/`.
- `site/docs/index.html`: canonical link to `https://song2vid.pages.dev/docs/`; "Updated" date; the Markdown alternate (`/docs.md`); a footer link to the Markdown copy.
- Every internal link to the docs page uses `/docs/`.
- Parts that work only in a browser (picker, Copy button, status line, manual-copy dialog) get `data-md="skip"`.
- The layout, handoff behavior and CSP do not change; the page keeps its three steps.

## Acceptance Criteria

- Both pages have exactly one canonical link equal to their own address.
- The version in the page equals `song2vid --version`.
- The three facts of SPEC §20 are text in the HTML source (checked with `curl` and `grep`, no script run).
- No internal link to `/docs` without the trailing slash.
- The pages look the same as before at 320 × 667, 390 × 844 and desktop, light and dark, with no horizontal scroll; the handoff still works (picker, Copy, manual-copy fallback).

## Dependencies

None.

## Comments
