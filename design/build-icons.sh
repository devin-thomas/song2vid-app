#!/bin/bash
# Regenerates every icon output from the vector sources design/icon.svg and design/icon-small.svg.
# Needs only a stock Mac with Xcode: swiftc, and AppKit renders the SVG.
#
# Outputs:
#   Song2Vid/Assets.xcassets/AppIcon.appiconset   the macOS app icon set
#   site/favicon.svg, site/logo.svg                the mark for the download page
#   site/apple-touch-icon.png                      180 px, full-bleed (iOS rounds the corners itself)
#   design/preview.png                             preview sheet at 1024, 128, 32 and 16 px
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

src=design/icon.svg
small=design/icon-small.svg # heavier, edge-to-edge variant used up to 64 px
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

swiftc -O design/render.swift -o "$work/render"
swiftc -O design/preview.swift -o "$work/preview"

# --- App icon set -------------------------------------------------------------------------
set_dir=Song2Vid/Assets.xcassets/AppIcon.appiconset
mkdir -p "$set_dir"
rm -f "$set_dir"/*.png
for px in 16 32 64 128 256 512 1024; do
  if (( px <= 64 )); then variant=$small; else variant=$src; fi
  "$work/render" "$variant" "$set_dir/icon_${px}.png" "$px"
done
cat > Song2Vid/Assets.xcassets/Contents.json <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
cat > "$set_dir/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_64.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png",  "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

# --- Download page assets ------------------------------------------------------------------
# The macOS icon grid leaves 100 px of margin on a 1024 canvas; the page assets crop to the shape.
mkdir -p site
sed 's|viewBox="0 0 1024 1024" width="1024" height="1024"|viewBox="100 100 824 824" width="512" height="512"|' "$src" > site/favicon.svg
cp site/favicon.svg site/logo.svg
# The favicon is tiny in a browser tab, so it uses the heavier small-size variant.
sed 's|viewBox="60 60 904 904" width="1024" height="1024"|viewBox="100 100 824 824" width="64" height="64"|' "$small" > site/favicon.svg
# Full-bleed variant (square corners) for the apple touch icon.
sed -e 's|viewBox="0 0 1024 1024" width="1024" height="1024"|viewBox="100 100 824 824" width="824" height="824"|' \
    -e 's|rx="185"|rx="0"|g' "$src" > "$work/bleed.svg"
"$work/render" "$work/bleed.svg" site/apple-touch-icon.png 180 opaque

# --- Preview sheet -------------------------------------------------------------------------
"$work/render" "$src" "$work/p1024.png" 1024
"$work/render" "$src" "$work/p128.png" 128
"$work/render" "$small" "$work/p32.png" 32
"$work/render" "$small" "$work/p16.png" 16
"$work/preview" "$work" design/preview.png
echo "icons regenerated"
