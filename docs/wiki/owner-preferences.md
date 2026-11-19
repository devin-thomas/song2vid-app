# Owner preferences

- On 2026-11-18, the owner asked that every GitHub commit show their own name (`devin`) and account, never Claude or a bot. The machine's global git name was a bot name, so each repo sets its own identity. See [public-repo-safety](public-repo-safety.md), ADR-007.
- On 2026-11-18, the owner chose Grill to Build for planning, not Quick Build. Source: PROJECT.md "Discovery progress".
- On 2026-11-18, the owner asked that the build be done by Sonnet subagents on high reasoning, with the Opus coordinator limited to verifying and writing docs. See [build-workflow](build-workflow.md).
- On 2026-11-18, the owner made drag and drop "non-negotiable", with a Replace / Keep Current dialog before anything is replaced. Source: SPEC.md §4a.
- On 2026-11-18, the owner asked for this wiki to be public in `docs/wiki/`, because the repo is meant to teach others how to plan and build this way.
- On 2026-11-18, the owner confirmed the purpose of the whole repo: a public demonstration of building with AI using the Grill to Build planning process and the Starter Pack. The plan files, `docs/`, this wiki and `.claude/skills/` stay public on purpose, so someone can see the full setup, or start from this point and find the chief-of-staff skill and everything it depends on. The README should show a newcomer how to do this.
