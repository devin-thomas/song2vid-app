#!/bin/bash
# Public-repo safety scan (SPEC section 9). Fails on home-folder paths, emails other than the
# owner's noreply address, token-shaped strings, IP addresses, and secret/env files.
#
#   scripts/safety-scan.sh            scan every tracked and untracked-but-not-ignored file
#   scripts/safety-scan.sh --staged   scan the staged versions of changed files (used by the hook)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

ALLOWED_EMAIL='127160473+devin-thomas@users.noreply.github.com'

# Patterns are written so that this file does not match itself.
PATTERNS=(
  'home-folder path|/Users/[A-Za-z0-9_][A-Za-z0-9_.-]*'
  'IP address|\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'
  'GitHub token|\bgh[pousr]_[A-Za-z0-9]{20,}'
  'GitHub token|\bgithub_pat_[A-Za-z0-9_]{20,}'
  'AWS key|\bAKIA[0-9A-Z]{16}\b'
  'API secret key|\bsk-[A-Za-z0-9_-]{20,}'
  'Slack token|\bxox[baprs]-[A-Za-z0-9-]{10,}'
  'private key|-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'hard-coded secret|(api[_-]?key|secret|token|passw(or)?d)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'[:space:]]{12,}["'"'"']'
)
EMAIL_PATTERN='[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+'
BAD_PATHS='(^|/)\.env($|\.)|\.(pem|p12|key|mobileprovision)$'

failures=0
fail() { echo "safety-scan: $1" >&2; failures=$((failures + 1)); }

scan_file() { # label realpath
  local label="$1" real="$2" name pattern hits
  if [[ "$label" =~ $BAD_PATHS ]]; then fail "$label: secret or env file must not be committed"; fi
  for entry in "${PATTERNS[@]}"; do
    name="${entry%%|*}"; pattern="${entry#*|}"
    if hits=$(grep -nIE -e "$pattern" "$real" 2>/dev/null); then
      while IFS= read -r line; do fail "$label:${line%%:*}: $name"; done <<< "$hits"
    fi
  done
  if hits=$(grep -noIE -e "$EMAIL_PATTERN" "$real" 2>/dev/null | grep -vF -- "$ALLOWED_EMAIL"); then
    while IFS= read -r line; do fail "$label:${line%%:*}: email address"; done <<< "$hits"
  fi
  return 0
}

if [[ "${1:-}" == "--staged" ]]; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  while IFS= read -r -d '' f; do
    git show ":$f" > "$tmp/staged" 2>/dev/null || continue
    scan_file "$f" "$tmp/staged"
  done < <(git diff --cached --name-only --diff-filter=ACMR -z)
else
  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    scan_file "$f" "$f"
  done < <(git ls-files -co --exclude-standard -z)
fi

if (( failures > 0 )); then
  echo "safety-scan: $failures problem(s) found" >&2
  exit 1
fi
echo "safety-scan: clean"
