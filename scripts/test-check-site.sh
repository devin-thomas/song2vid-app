#!/bin/bash
# Shows that each agent-ready site check fails on a deliberately broken copy of site/ (SPEC section 20, S2V-021).
# Each case copies site/, breaks one thing, runs scripts/check-site.sh on the copy and expects its message.
# Manual proof; scripts/check.sh runs the checks themselves, not this.
# usage: scripts/test-check-site.sh <path to the song2vid command>
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
command="${1:?usage: scripts/test-check-site.sh <song2vid command>}"
failures=0

case_() {  # name, python edit (d is the copy), expected message
  local name="$1" edit="$2" want="$3" d out status
  d=$(mktemp -d)
  cp -R site/. "$d/"
  D="$d" python3 -I -c "
import os, pathlib, re
d = pathlib.Path(os.environ['D'])
$edit
"
  out=$(SITE_DIR="$d" scripts/check-site.sh "$command" 2>&1); status=$?
  if [[ $status -ne 0 && "$out" == *"$want"* ]]; then
    echo "ok    $name"
  else
    echo "FAIL  $name (status $status)"; echo "$out" | head -5; failures=$((failures + 1))
  fi
  rm -rf "$d"
}

case_ "stray file" "(d/'draft-announcement.html').write_text('x')" "not on the publish list"
case_ "listed file missing" "(d/'404.html').unlink()" "404.html is on the publish list but not in the site folder"
case_ "stale llms.txt" "p=d/'llms.txt'; p.write_text(p.read_text()+'extra')" "llms.txt differs from a fresh build"
case_ "stale Markdown copy" "p=d/'index.md'; p.write_text(p.read_text().replace('Free','Gratis'))" "index.md differs from a fresh build"
case_ "wrong canonical" "p=d/'docs/index.html'; p.write_text(p.read_text().replace('pages.dev/docs/\"','pages.dev/documents/\"'))" "must have exactly one canonical link"
case_ "second canonical" "p=d/'index.html'; p.write_text(p.read_text().replace('<link rel=\"alternate\"','<link rel=\"canonical\" href=\"https://song2vid.pages.dev/x\">\n<link rel=\"alternate\"',1))" "exactly one canonical link"
case_ "no Markdown alternate" "p=d/'index.html'; p.write_text(re.sub(r'<link rel=\"alternate\"[^>]*>\n','',p.read_text()))" "must link its Markdown copy"
case_ "date differs from sitemap" "p=d/'index.html'; p.write_text(p.read_text().replace('datetime=\"2026-11-25\">25 November 2026','datetime=\"2026-11-26\">26 November 2026'))" "differs from the sitemap lastmod"
case_ "visible date wrong" "p=d/'docs/index.html'; p.write_text(p.read_text().replace('>25 November 2026<','>1 January 2020<'))" "does not match datetime"
case_ "version differs" "p=d/'index.html'; p.write_text(re.sub(r'Version [0-9.]+','Version 0.0.0',p.read_text(),count=1))" "shows version 0.0.0 but the command says"
case_ "free missing" "p=d/'index.html'; p.write_text(p.read_text().replace('Free · ',''))" "does not say that Song2Vid is free"
case_ "Windows requirement missing" "p=d/'index.html'; p.write_text(p.read_text().replace('Requires Windows 10 or 11, 64-bit','Needs a PC'))" "requires Windows 10 or 11, 64-bit"
case_ "Windows download missing" "p=d/'index.html'; p.write_text(p.read_text().replace('Song2Vid-1.2.0-windows-x64.zip','Song2Vid-windows.zip'))" "must have a 'Download for Windows' link"
case_ "HEVC mentioned twice" "p=d/'index.html'; p.write_text(p.read_text().replace('Free · Version','Free · HEVC · Version',1))" "must mention HEVC exactly once"
case_ "help option missing from docs" "p=d/'docs/index.html'; p.write_text(p.read_text().replace('<code>--cancel-on-eof</code>','<code>--cancel-eof</code>'))" "does not mention --cancel-on-eof"
case_ "macOS missing" "p=d/'index.html'; p.write_text(p.read_text().replace('Requires macOS 14 or later','Needs a Mac'))" "requires macOS 14 or later"
case_ "error code missing from docs" "p=d/'docs/index.html'; p.write_text(p.read_text().replace('image_not_found','image_gone'))" "does not contain 'image_not_found'"
case_ "docs link without slash" "p=d/'index.html'; p.write_text(p.read_text().replace('href=\"/docs/\"','href=\"/docs\"',1))" "needs its trailing slash"
case_ "dead internal link" "p=d/'index.html'; p.write_text(p.read_text().replace('href=\"/agent.md\"','href=\"/agents.md\"',1))" "does not go to a file in the site"
case_ "robots without sitemap" "(d/'robots.txt').write_text('User-agent: *\nAllow: /\n')" "robots.txt does not point to the sitemap"
case_ "robots blocks a path" "p=d/'robots.txt'; p.write_text(p.read_text()+'Disallow: /docs/\n')" "robots.txt blocks a path"
case_ "llms.txt type missing" "p=d/'_headers'; p.write_text(p.read_text().replace('/llms.txt\n  Content-Type: text/plain; charset=utf-8','/llms.txt\n  X-Note: none'))" "_headers does not serve /llms.txt"
case_ "404 not noindex" "p=d/'404.html'; p.write_text(p.read_text().replace('noindex','index'))" "404.html must exist, carry noindex"
case_ "sitemap page missing" "p=d/'sitemap.xml'; p.write_text(re.sub(r'  <url><loc>https://song2vid.pages.dev/docs/</loc>.*\n','',p.read_text()))" "sitemap.xml must list https://song2vid.pages.dev/docs/ exactly once"

# The Windows help texts are not the Mac command's: a broken copy of windows/tool/src/help/.
h=$(mktemp -d)
cp windows/tool/src/help/*.txt "$h/"
printf 'extra\n' >> "$h/make.txt"
out=$(WINDOWS_HELP_DIR="$h" scripts/check-site.sh "$command" 2>&1); status=$?
if [[ $status -ne 0 && "$out" == *"differs from the Mac command"* ]]; then echo "ok    Windows help differs from the Mac's"; else echo "FAIL  Windows help differs from the Mac's (status $status)"; echo "$out" | head -5; failures=$((failures + 1)); fi
rm -rf "$h"

(( failures == 0 )) || { echo "test-check-site: $failures check(s) did not fail on a broken copy" >&2; exit 1; }
echo "test-check-site: every agent-ready check failed on its broken copy"
