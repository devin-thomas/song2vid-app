#!/bin/bash
# The one check command: public-safety scan, package tests, then the Xcode build and tests.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== Public-safety scan"
scripts/safety-scan.sh
# The commit messages on this branch, when main is there to compare with (a one-commit checkout has no main).
if base=$(git merge-base origin/main HEAD 2>/dev/null) && [[ -n "$base" ]]; then
  scripts/safety-scan.sh --log "$base..HEAD"
fi
case "$(git config core.hooksPath || true)" in
  *.githooks) ;;
  *) echo "check: warning: the commit hooks are not on here. Run: git config core.hooksPath .githooks" >&2 ;;
esac

echo "== Swift package tests (Song2VidCore)"
(cd Song2VidCore && swift test)

mkdir -p build
derived=build/DerivedData
app="$derived/Build/Products/Debug/Song2Vid.app"

# Xcode builds package dependencies for the destination's architecture only, so the test run is
# pinned to the host architecture. The universal build below covers both slices.
host=$(uname -m)
echo "== Xcode tests ($host)"
xcodebuild test \
  -project Song2Vid.xcodeproj \
  -scheme Song2Vid \
  -destination "platform=macOS,arch=$host" \
  -derivedDataPath "$derived-$host" \
  ARCHS="$host" \
  | tee "$derived-$host.log" | grep -E "Test run with|Test Suite .* (passed|failed)|error:|TEST (SUCCEEDED|FAILED)"
grep -q "TEST SUCCEEDED" "$derived-$host.log"
# Both Xcode test targets must have run at least one test.
ran=$(grep -c "Test run with [1-9][0-9]* test" "$derived-$host.log" || true)
(( ran >= 2 )) || { echo "check: expected 2 test targets to run tests, saw $ran" >&2; exit 1; }

echo "== Xcode universal build (arm64 + x86_64, ad-hoc signed)"
xcodebuild build \
  -project Song2Vid.xcodeproj \
  -scheme Song2Vid \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived" \
  -quiet

archs=$(lipo -archs "$app/Contents/MacOS/Song2Vid")
echo "App architectures: $archs"
for arch in arm64 x86_64; do
  [[ " $archs " == *" $arch "* ]] || { echo "check: app is missing the $arch slice" >&2; exit 1; }
done
codesign --verify --deep --strict "$app"
codesign -dv "$app" 2>&1 | grep -E "Signature|TeamIdentifier"

echo "check: all passed"
