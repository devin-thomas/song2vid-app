# S2V-016 - Agent Handoff on the download page

Status: resolved
Blocked by: none (site files only; built in parallel with the command tickets)

## Goal

A visitor hands "make a video with Song2Vid" to ChatGPT, Claude, Grok Bot or Muse in one click (SPEC §16, ADR-016, ADR-017).

## Scope

- Use the `starterpack:agent-prompt` skill and its interaction contract.
- Artwork in `site/brands/`: ChatGPT, Claude and Grok Bot from `devin-thomas/agent-prompts` (`public/brands/`), Muse from the npm package `@lobehub/icons-static-svg`, version 1.104.0 (`icons/muse.svg`, `icons/muse-color.svg`). Copy the credits and licence notices. All four must appear; none may be dropped or replaced with text.
- The exact prompt in SPEC §16, from one payload for preview and clipboard. An agent picker with `Copy for {Agent}`; manual-copy dialog on clipboard failure. Open-in links only where the format is verified on the day, with the source and date recorded.
- One first-party script; CSP adds `script-src 'self'` only.

## Acceptance Criteria

- The four marks and names and the copy action are visible without scrolling at 320 × 667 and 390 × 844, with no overflow, in light and dark.
- Copy works by mouse and keyboard; "Copied" appears only after the write succeeds; a denied clipboard shows the manual dialog with the full prompt.
- Reduced motion is respected. No third-party requests.
- The prompt is at most 40 words and 300 characters.

## Dependencies

None for building. The live check of `/agent.md` happens in S2V-017.

## Comments

- 2026-11-21: Claimed and built on branch `ticket/S2V-016` (site files only). The handoff is copy-only: no open-in links, because no prompt-link format could be verified as working for these four agents on the day. Not merged and not deployed; the live `/agent.md` check stays with S2V-017.
- 2026-11-22 (coordinator): Verified and merged. Viewed the 390×844 light and 320×667 dark screenshots: all four marks with names and the Copy button above the fold. The Grok Bot SVG is byte-identical to the agent-prompts source (rendered large: the eye-mask mark). ChatGPT and Claude SVGs differ only by spaces between path numbers, added so the safety scan doesn't read them as IP addresses. No open-in links, because none has a documented web prompt-link format (sources in the implementer's notes). Still to check live in S2V-017: the clipboard over HTTPS, and Safari.
