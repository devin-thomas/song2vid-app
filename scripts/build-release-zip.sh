#!/bin/bash
# Builds a release-style zip of the app with the song2vid command inside (SPEC section 17).
#
#   scripts/build-release-zip.sh <folder> [zip-name]
#
# A clean Release build, universal (arm64 and x86_64) and ad-hoc signed, is zipped with
# `ditto -c -k --keepParent` into <folder>, which must be outside the repo. The default name is
# Song2Vid-<version>.zip. It builds in a fresh temporary folder each time and removes it afterwards.
# Nothing is published.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

out=${1:?usage: scripts/build-release-zip.sh <folder> [zip-name]}
mkdir -p "$out"
out=$(cd "$out" && pwd -P)
case "$out/" in
  "$(pwd -P)/"*) echo "build-release-zip: the folder must be outside the repo" >&2; exit 1 ;;
esac

derived=$(mktemp -d)
trap 'rm -rf "$derived"' EXIT

xcodebuild build \
  -project Song2Vid.xcodeproj \
  -scheme Song2Vid \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived" \
  -quiet

app="$derived/Build/Products/Release/Song2Vid.app"
command="$app/Contents/Helpers/song2vid"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
zip_name=${2:-Song2Vid-$version.zip}

for file in "$app/Contents/MacOS/Song2Vid" "$command"; do
  archs=$(lipo -archs "$file")
  for arch in arm64 x86_64; do
    [[ " $archs " == *" $arch "* ]] || { echo "build-release-zip: $(basename "$file") is missing the $arch slice" >&2; exit 1; }
  done
done
codesign --verify --deep --strict "$app"
app_entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null)
cmd_entitlements=$(codesign -d --entitlements - --xml "$command" 2>/dev/null)
[[ "$app_entitlements" == *"com.apple.security.app-sandbox"* ]] || { echo "build-release-zip: the app lost its sandbox" >&2; exit 1; }
[[ "$app_entitlements$cmd_entitlements" != *"get-task-allow"* ]] || { echo "build-release-zip: get-task-allow is present" >&2; exit 1; }
[[ "$cmd_entitlements" != *"com.apple.security.app-sandbox"* ]] || { echo "build-release-zip: the command is sandboxed" >&2; exit 1; }

rm -f "$out/$zip_name"
ditto -c -k --keepParent "$app" "$out/$zip_name"
echo "Built $zip_name ($version) in the folder you gave."
shasum -a 256 "$out/$zip_name" | cut -d' ' -f1
