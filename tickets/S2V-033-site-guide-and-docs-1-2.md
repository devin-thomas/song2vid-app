# S2V-033 - Site, Agent Guide and docs for 1.2.0

Status: open
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
