#!/bin/bash
# Public-repo safety scan (SPEC section 9). Fails on home-folder paths, emails other than the
# owner's noreply address, token-shaped strings, IP addresses, secret/env files, and (in commit
# messages) co-author lines.
#
#   scripts/safety-scan.sh                  scan every tracked and untracked-but-not-ignored file
#   scripts/safety-scan.sh --staged         scan the staged versions of changed files (pre-commit hook)
#   scripts/safety-scan.sh --message FILE   scan one commit message (commit-msg hook)
#   scripts/safety-scan.sh --log RANGE      scan the message of every commit in RANGE, e.g. origin/main..HEAD
#
# Binary files are scanned too: a PNG through its metadata chunks (scripts/png-metadata.py), anything else through
# its text strings.
#
# Sample media (ADR-012): names of the owner's real files must not appear in the repo, in its file names or in
# its commit messages. The names are not written down here. Put one per line in a file kept outside the repo and
# point S2V_DENYLIST at it. Blank lines and lines starting with # are ignored, and case is ignored.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

ALLOWED_EMAIL='127160473+devin-thomas@users.noreply.github.com'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

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

# What a commit message must not carry (CLAUDE.md: no AI or other co-author lines). Matched ignoring case.
MESSAGE_PATTERNS=(
  'co-author line|^[[:space:]]*co-authored-by:'
  'generated-with line|generated with \[?claude'
)

failures=0
fail() { echo "safety-scan: $1" >&2; failures=$((failures + 1)); }

denylist=""
# Default: a list kept inside .git (never committed), so the hook checks it without any setup.
if [[ -z "${S2V_DENYLIST:-}" ]]; then
  default_list="$(git rev-parse --git-common-dir 2>/dev/null)/info/s2v-denylist"
  [[ -f "$default_list" ]] && S2V_DENYLIST="$default_list"
fi
if [[ -n "${S2V_DENYLIST:-}" ]]; then
  [[ -f "$S2V_DENYLIST" ]] || { echo "safety-scan: S2V_DENYLIST names a file that does not exist" >&2; exit 1; }
  grep -vE '^[[:space:]]*(#|$)' "$S2V_DENYLIST" > "$work/denylist" || true
  if [[ -s "$work/denylist" ]]; then denylist="$work/denylist"; fi
else
  echo "safety-scan: note: S2V_DENYLIST is not set, so sample-media names are not checked" >&2
fi

# Checks a text file (labelled $1) for every pattern that applies to any text, and for denied names.
scan_text() { # label textfile
  local label="$1" real="$2" entry name pattern hits line
  for entry in "${PATTERNS[@]}"; do
    name="${entry%%|*}"; pattern="${entry#*|}"
    if hits=$(grep -nE -e "$pattern" "$real" 2>/dev/null); then
      while IFS= read -r line; do fail "$label:${line%%:*}: $name"; done <<< "$hits"
    fi
  done
  if hits=$(grep -noE -e "$EMAIL_PATTERN" "$real" 2>/dev/null | grep -vF -- "$ALLOWED_EMAIL"); then
    while IFS= read -r line; do fail "$label:${line%%:*}: email address"; done <<< "$hits"
  fi
  if [[ -n "$denylist" ]] && hits=$(grep -niFf "$denylist" "$real" 2>/dev/null); then
    while IFS= read -r line; do fail "$label:${line%%:*}: sample-media name"; done <<< "$hits"
  fi
  return 0
}

scan_file() { # label realpath
  local label="$1" real="$2" text="$2"
  if [[ "$label" =~ $BAD_PATHS ]]; then fail "$label: secret or env file must not be committed"; fi
  if [[ -n "$denylist" ]] && printf '%s\n' "$label" | grep -qiFf "$denylist"; then
    fail "$label: sample-media name in the file name"
  fi
  # A binary file is scanned as the text inside it. For a PNG that is its metadata chunks (the picture data is
  # compressed noise that can look like an address by chance); for anything else, its longer text strings.
  if [[ -s "$real" ]] && ! grep -qI -e '' "$real" 2>/dev/null; then
    text="$work/binary-text"
    if ! python3 -I scripts/png-metadata.py "$real" > "$text" 2>/dev/null; then
      strings -a -n 16 "$real" > "$text" 2>/dev/null || : > "$text"
    fi
  fi
  scan_text "$label" "$text"
}

scan_message() { # label file
  local label="$1" real="$2" entry name pattern hits line
  for entry in "${MESSAGE_PATTERNS[@]}"; do
    name="${entry%%|*}"; pattern="${entry#*|}"
    if hits=$(grep -niE -e "$pattern" "$real" 2>/dev/null); then
      while IFS= read -r line; do fail "$label:${line%%:*}: $name"; done <<< "$hits"
    fi
  done
  scan_text "$label" "$real"
}

case "${1:-}" in
  --staged)
    while IFS= read -r -d '' f; do
      git show ":$f" > "$work/staged" 2>/dev/null || continue
      scan_file "$f" "$work/staged"
    done < <(git diff --cached --name-only --diff-filter=ACMR -z)
    ;;
  --message)
    [[ -f "${2:-}" ]] || { echo "safety-scan: --message needs the message file" >&2; exit 1; }
    # Comment lines are git's own and not part of the message.
    grep -v '^#' "$2" > "$work/message" || true
    scan_message "commit message" "$work/message"
    ;;
  --log)
    [[ -n "${2:-}" ]] || { echo "safety-scan: --log needs a commit range" >&2; exit 1; }
    while IFS= read -r commit; do
      git log -1 --format=%B "$commit" > "$work/message"
      scan_message "commit ${commit:0:9}" "$work/message"
    done < <(git rev-list "$2")
    ;;
  "")
    while IFS= read -r -d '' f; do
      [[ -f "$f" ]] || continue
      scan_file "$f" "$f"
    done < <(git ls-files -co --exclude-standard -z)
    ;;
  *)
    echo "safety-scan: unknown option $1" >&2
    exit 1
    ;;
esac

if (( failures > 0 )); then
  echo "safety-scan: $failures problem(s) found" >&2
  exit 1
fi
echo "safety-scan: clean"
