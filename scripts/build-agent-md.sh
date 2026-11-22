#!/bin/bash
# Makes site/agent.md, the public Agent Guide, from the skill (SPEC section 15, ADR-015).
# It is a plain copy. Never edit site/agent.md by hand: change skills/song2vid/SKILL.md and run this.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
cp skills/song2vid/SKILL.md site/agent.md
echo "build-agent-md: site/agent.md written from skills/song2vid/SKILL.md"
