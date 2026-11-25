#!/bin/bash
# Checks the site against the command (S2V-015):
#   1. site/agent.md is the skill, byte for byte.
#   2. Every option in both commands' --help (the Mac command, and the Windows help texts saved in windows/tool/src/help/;
#      the two must match byte for byte) is on the docs page, in its long and short spelling.
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
# Every "-x | --long" and "-x | --long <value>" spelling in the help texts of both commands. The Mac command's help is read
# live. The Windows command's help texts are saved in windows/tool/src/help/ (its tests prove the program prints them), and
# they must equal the Mac command's help byte for byte, so the one docs page covers both.
windows_help="${WINDOWS_HELP_DIR:-windows/tool/src/help}"
helps=(global:--help check:"check --help" make:"make --help" encoders:"encoders --help" preview:"preview --help")
for entry in "${helps[@]}"; do
  name="${entry%%:*}"; args="${entry#*:}"
  saved="$windows_help/$name.txt"
  [[ -f "$saved" ]] || { echo "check-site: $saved is missing" >&2; fail=1; continue; }
  # shellcheck disable=SC2086
  if ! "$command" $args 2>&1 | cmp -s - "$saved"; then
    echo "check-site: the Windows help text $saved differs from the Mac command's '$args' output" >&2
    fail=1
  fi
done
options=$( { "$command" --help; "$command" check --help; "$command" make --help; "$command" encoders --help; "$command" preview --help; cat "$windows_help"/*.txt; } \
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
