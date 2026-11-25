# S2V-033 - Site, Agent Guide and docs for 1.2.0

Status: resolved
Blocked by: S2V-023, S2V-027, S2V-032

## Goal

People and agents can find, install and use Song2Vid on either system from the site (SPEC §30).

## Scope

- Download page: two downloads with their requirements and first-open steps, HEVC mentioned once, version 1.2.0; the Agent Handoff unchanged.
- Agent Guide: Windows install and PATH line, the Windows window route, `--codec`, `encoders`, `preview`, how to choose a Codec.
- Docs page: every SPEC §24 addition, the key table with versions, the Windows install.
- Section 20 fact 2 and the site checks updated; generated files rebuilt.

## Acceptance Criteria

- `scripts/check.sh` passes, including the updated facts and the `--help` coverage check against both commands.
- `song2vid --skill` on each system prints the published `agent.md` byte for byte.
- Nothing about later versions or unreleased work appears on the site.

## Dependencies

S2V-023, S2V-027, S2V-032.

## Comments

- 2026-11-25 (builder): Built the 1.2.0 site, Agent Guide and docs for both systems. Branch `ticket/S2V-033`; not merged, not deployed.
  - Download page (`site/index.html`): two downloads (`Song2Vid-1.2.0.zip`, `Song2Vid-1.2.0-windows-x64.zip`, both through `releases/latest/download/`), each with its requirement ("Requires macOS 14 or later", "Requires Windows 10 or 11, 64-bit"), one version line (Free, Version 1.2.0), and per-system steps with the first-open step (Open Anyway; More info, then Run anyway; `Install Song2Vid.cmd`, no administrator rights). HEVC is mentioned once, in one sentence under the steps. The Agent Handoff is unchanged. On small screens the two downloads sit side by side so the handoff still fits at 320 x 667 (the Copy button ends at 636 px; the 1.1 page ended at 608) and at 390 x 844.
  - Agent Guide (`skills/song2vid/SKILL.md`, copied to `site/agent.md`): Windows install and the SPEC 29 PATH line (with the full path to use before a new terminal), the first-open rule for both systems, Codec choice (H.264 unless HEVC or smaller files are asked for, and only if `encoders` says it is available, else make H.264 and say so), `output_in_use`, and the app's window route on Windows by control name in SPEC 27.2 order (Choose Audio…, Choose Image…, Frame Shape, Resolution, Codec, Crop position, Reset to Center, Make Video, the save dialog, "Saved … to …", Show in File Explorer, Cancel). `--cancel-on-eof` stays documented for programs only. The Mac route is unchanged apart from moving the Codec sentence.
  - Docs page (`site/docs/index.html`): Install for Mac and Windows (installer, uninstall, SmartScreen, PATH line, command path), a new "Codecs and encoders" section (Codec, `hvc1`, encoder order per system, Windows fallback, `encoders` text and JSON, `codec_unavailable`), Windows values for `encoder` and `encoder_fallback` in the key table, `output_in_use` explained, the Windows console note, the window section for both systems. Every addition of SPEC 24 and the "Added in" column were already there from S2V-023 and are kept.
  - Checks: SPEC 20 fact 2 now reads both requirements and 1.2.0 (SPEC text, `scripts/check-site-ready.py`: both requirements, both asset links, version equal to `--version`, exactly one HEVC mention). `scripts/check-site.sh` now takes options from the Mac command's help and the saved Windows help texts (`windows/tool/src/help/`), requires those five texts to equal the Mac command's output byte for byte, and requires every option on the docs page (30 spellings). `scripts/test-check-site.sh` gained five cases (Windows requirement, Windows download, HEVC twice, an option missing from the docs, a Windows help text that differs).
  - Ran on this Mac: `python3 -I -B scripts/build-site.py` (0), `scripts/check-site.sh` on the built command (0), `scripts/test-check-site.sh` (0; all 25 cases failed on their broken copies as required), `scripts/check.sh` (0; includes the safety scan, Swift package tests, Xcode tests, universal build, `--skill` equal to `skills/song2vid/SKILL.md`, and the site checks). Headless Chromium at 1280 px and 390 px and 320 px, light and dark: no horizontal page scroll on either page, and the screenshots were read by eye.
  - Not checked: `song2vid --skill` on Windows (it reads `SKILL.md` beside the exe, so S2V-032's package must copy the current `skills/song2vid/SKILL.md`; the byte-for-byte check on Windows belongs to S2V-032/S2V-034); the Windows window route was written from SPEC 27 and `windows/app/src`, not by driving a packaged app; the separate-agent site proof and the outside checks after the deploy (S2V-034). No SPEC change besides the section 20 fact 2 and section 30 text.
