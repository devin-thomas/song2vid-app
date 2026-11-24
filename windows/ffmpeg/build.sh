#!/usr/bin/env bash
# Cross-build two Windows x64 executables in a disposable Linux container.
set -euo pipefail
recipe=$(cd "$(dirname "$0")" && pwd -P)
if (( $# > 1 )); then
  echo "usage: $0 [staging-directory]" >&2
  exit 2
fi

staging=${1:-$recipe/../app/staging}
mkdir -p "$staging"
staging=$(cd "$staging" && pwd -P)
artifacts=$(mktemp -d "$staging/.ffmpeg.XXXXXX")
trap 'rm -rf "$artifacts"' EXIT

# Use the same toolchain architecture even on a host with a different CPU.
image=$(docker build --platform linux/arm64 --quiet "$recipe")
docker run --rm --platform linux/arm64 --user "$(id -u):$(id -g)" \
  -v "$recipe:/recipe:ro" -v "$artifacts:/out" "$image" bash /recipe/compile.sh

mkdir -p "$staging/bin/win32-x64"
for binary in ffmpeg.exe ffprobe.exe; do
  mv "$artifacts/$binary" "$staging/bin/win32-x64/$binary"
done
mv "$artifacts/THIRD-PARTY-NOTICES.txt" "$staging/THIRD-PARTY-NOTICES.txt"
