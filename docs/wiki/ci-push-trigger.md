# CI did not run on push

- On 2026-11-19, the S2V-001 implementer reported that pushes to `main` and `build/v1` did not start the `check` workflow (`.github/workflows/check.yml` as of `90c7639`, with `on: push` for all branches). Actions were enabled for the repo. The two recorded runs were started by hand with `workflow_dispatch`, and both passed.
- On 2026-11-19, the coordinator pushed a docs commit to `build/v1` to test whether a push now triggers a run. The result is recorded below.
