# S2V-009 - App icon and brand mark

Status: resolved
Blocked by: S2V-001

## Goal

Song2Vid has an original icon that shows a song becoming a video, at every size macOS needs.

## Scope

- Vector source in `design/` (SVG or a drawing script), rendered to the app's AppIcon set, a favicon and a header image for `site/` (SPEC §9a).

## Acceptance Criteria

- The built app shows the icon in Finder and the Dock.
- At 16×16 it is still recognisable. It looks right on light and dark backgrounds.
- No third-party artwork or fonts are used. The source and the rendering step are committed, so the icon can be rebuilt.

## Dependencies

S2V-001.

## Comments

- Resolved in d7b4615 on branch ticket/S2V-009. Rebuild every output with `design/build-icons.sh` (sources: `design/icon.svg`, `design/icon-small.svg`). Preview sheet: `design/preview.png`. scripts/check.sh passed; the built app carries `CFBundleIconName` AppIcon with all ten sizes in Assets.car and an AppIcon.icns.
