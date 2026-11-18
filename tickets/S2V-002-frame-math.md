# S2V-002 - Frame size and placement rules

Status: ready-for-agent
Blocked by: S2V-001

## Goal

One tested place that turns an image size, a Frame Shape, a Resolution and a crop position into the exact output size and image placement.

## Scope

- The section 5 table, the Original rules, Fit with bars placement, and Crop limits (SPEC §4–5).

## Acceptance Criteria

- Unit tests cover every table cell, the Original rules (exact size, under 1% trim, over 1% scale, odd size, too small, portrait limit), and Crop position limits. All pass.

## Dependencies

S2V-001.
