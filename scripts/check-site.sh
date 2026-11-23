#!/bin/bash
# Checks the site against the command (S2V-015):
#   1. site/agent.md is the skill, byte for byte.
#   2. Every option in the command's --help (long and short spelling) is on the docs page.
#   3. _headers serves /agent.md as Markdown text.
#   4. The agent-ready checks of SPEC section 20 (scripts/check-site-ready.py): generated files equal a fresh build,
#      canonical links, dates, facts, links, sitemap, llms.txt, robots.txt, content types, 404 page, publish list.
# Usage: scripts/check-site.sh <path to the built song2vid command>
# SITE_DIR and SKILL_FILE can point at other copies, which is how the checks are shown to fail.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
command="${1:?usage: scripts/check-site.sh <song2vid command>}"
site="${SITE_DIR:-site}"
skill="${SKILL_FILE:-skills/song2vid/SKILL.md}"
fail=0

if ! cmp -s "$skill" "$site/agent.md"; then
  echo "check-site: $site/agent.md differs from $skill. Run scripts/build-agent-md.sh" >&2
  fail=1
fi

docs="$site/docs/index.html"
[[ -f "$docs" ]] || { echo "check-site: $docs is missing" >&2; exit 1; }
# Every "-x | --long" and "-x | --long <value>" spelling in the help texts.
options=$( { "$command" --help; "$command" check --help; "$command" make --help; "$command" encoders --help; "$command" preview --help; } \
  | grep -oE '(^|[[:space:]])-[A-Za-z] \| --[a-z-]+' | tr -d '|' | tr -s ' ' '\n' | grep -E '^-' | sort -u)
[[ $(printf '%s\n' "$options" | grep -c '^--') -ge 12 ]] || { echo "check-site: found too few options in --help" >&2; exit 1; }
for option in $options; do
  if ! grep -qF "<code>$option</code>" "$docs"; then
    echo "check-site: $docs does not mention $option" >&2
    fail=1
  fi
done

if ! grep -A3 '^/agent.md' "$site/_headers" | grep -qiF 'Content-Type: text/markdown; charset=utf-8'; then
  echo "check-site: $site/_headers does not serve /agent.md as text/markdown; charset=utf-8" >&2
  fail=1
fi

version=$("$command" --version | awk '{print $2}')
python3 -I -B scripts/check-site-ready.py "$site" "$version" || fail=1

(( fail == 0 )) || exit 1
echo "check-site: agent.md matches the skill; the docs page lists every option ($(printf '%s\n' "$options" | wc -l | tr -d ' ') spellings); the site is agent-ready (SPEC 20)"
