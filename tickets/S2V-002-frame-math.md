# S2V-002 - Frame size and placement rules

Status: resolved
Blocked by: S2V-001

## Goal

One tested place that turns an image size, a Frame Shape, a Resolution and a crop position into the exact output size and image placement.

## Scope

- The section 5 table, the Original rules, Fit with bars placement, and Crop limits (SPEC §4–5).

## Acceptance Criteria

- Unit tests cover every table cell, the Original rules (exact size, under 1% trim, over 1% scale, odd size, too small, portrait limit), and Crop position limits. All pass.

## Dependencies

S2V-001.

## Comments

Implemented in Song2VidCore (`OutputFrame`, `CropPosition`, `FrameError`) with 45 package tests. Implementation commit: 9cfbc3a.

Decisions on points the SPEC leaves open:
- Crop position is two fractions from 0 to 1 (0.5 is centre), so it survives a Resolution change; values past an edge are clamped.
- Original is rejected when either side is under 16 pixels.
- When a trim removes an odd number of pixels, the extra one comes off the right or bottom edge.
- Placements are exact fractional values; rounding for drawing is left to the export ticket.
