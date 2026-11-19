# Ticket log

- 2026-11-18: S2V-001 was dispatched to a Sonnet implementer.
- 2026-11-19: S2V-001 was resolved at `devin-thomas/song2vid-app@90c7639`. The coordinator checked it: a fresh clone of `build/v1` passes `scripts/check.sh` (universal, ad-hoc signed build, all tests, safety scan); every commit author is `devin` with no AI co-author lines; the repo is public with secret scanning and push protection on. The implementer reported the hook refusing a fake token, wrong authors, a home path, an IP and an email; the coordinator did not re-run those cases.
- 2026-11-19: Open issue from S2V-001: pushes did not trigger the `check` workflow, although `on: push` was configured, and CI was started by hand with `workflow_dispatch`. See [ci-push-trigger](ci-push-trigger.md).
- 2026-11-19: S2V-009 (icon) merged into `build/v1` at `a88e95b`. The coordinator viewed `design/preview.png`: a white music note whose flag is a play triangle, on a violet-to-pink rounded square, readable at 16 px on light and dark. The Finder and Dock appearance was not checked by eye.
- 2026-11-19: S2V-002 (frame math) merged into `build/v1`. The coordinator recomputed three Original cases by hand (3879×2160 → 3840×2138, 3880×2160 → 3840×2136, 4000×2000 → 3840×1920), and all matched the tests. The implementer resolved four small ambiguities, which were folded into SPEC §5.
