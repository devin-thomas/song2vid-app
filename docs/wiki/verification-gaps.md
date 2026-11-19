# Verification gaps

- On 2026-11-19, the coordinator accepted S2V-004 based on screenshots in which the files had been loaded through a launch argument, not the Choose buttons. The Choose Audio/Image buttons were in fact broken, and S2V-005 found and fixed them. Lesson: a UI ticket's verification must go through the real controls a person uses (buttons, panels, drag) rather than debug shortcuts. Implementer briefs since S2V-005 ask for "the actual UI path".
- On 2026-11-19, S2V-005 found that export failed in the sandboxed app, though the S2V-003 integration tests passed. Those tests run outside the sandbox. Lesson: export behavior is proven only by a run of the real app.
- Retro candidate (chief-of-staff): add a smoke check that launches the built app and loads a file through the Choose button, so this class of break is caught by `scripts/check.sh`.
