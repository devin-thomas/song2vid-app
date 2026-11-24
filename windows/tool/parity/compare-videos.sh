#!/bin/bash
# Compares the videos song2vid.exe made with the Mac command's (SPEC sections 22 and 31): the same
# pixel size, a length within 0.1 s, and a midpoint frame with an SSIM of at least 0.95, measured
# with FFmpeg's ssim filter. Run on the Mac after windows/scripts/check.ps1, with its folder of
# videos copied here.
#
#   windows/tool/parity/compare-videos.sh <parity bundle> <folder of the Windows videos>
set -uo pipefail
bundle="${1:?usage: compare-videos.sh <parity bundle> <folder of the Windows videos>}"
windows="${2:?usage: compare-videos.sh <parity bundle> <folder of the Windows videos>}"
limit=0.95
failures=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fact() { ffprobe -v error -select_streams "$1" -show_entries "$2" -of csv=p=0 "$3" | head -1; }

printf '%-22s %-10s %-10s %-9s %-9s %s\n' video "size" "Mac size" "length" "Mac" SSIM
while IFS=$'\t' read -r id _song _image _shape _resolution; do
  mac="$bundle/videos/$id.mp4"; win="$windows/$id.mp4"
  if [[ ! -f "$win" ]]; then printf '%-22s missing\n' "$id"; failures=$((failures + 1)); continue; fi
  size="$(fact v:0 stream=width,height "$win" | tr , x)"; macsize="$(fact v:0 stream=width,height "$mac" | tr , x)"
  length="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$win")"
  maclength="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$mac")"
  middle="$(python3 -c "print(float('$maclength') / 2)")"
  ffmpeg -hide_banner -loglevel error -nostdin -y -ss "$middle" -i "$mac" -frames:v 1 "$tmp/mac.png"
  ffmpeg -hide_banner -loglevel error -nostdin -y -ss "$middle" -i "$win" -frames:v 1 "$tmp/win.png"
  ssim="$(ffmpeg -hide_banner -nostdin -i "$tmp/mac.png" -i "$tmp/win.png" -lavfi "[0:v][1:v]ssim" -f null - 2>&1 | grep -o 'All:[0-9.]*' | cut -d: -f2)"
  verdict=""
  [[ "$size" == "$macsize" ]] || verdict="$verdict size"
  python3 -c "import sys; sys.exit(0 if abs(float('$length') - float('$maclength')) <= 0.1 else 1)" || verdict="$verdict length"
  python3 -c "import sys; sys.exit(0 if float('${ssim:-0}') >= $limit else 1)" || verdict="$verdict ssim"
  printf '%-22s %-10s %-10s %-9.3f %-9.3f %s%s\n' "$id" "$size" "$macsize" "$length" "$maclength" "${ssim:-none}" "${verdict:+  FAIL:$verdict}"
  [[ -z "$verdict" ]] || failures=$((failures + 1))
done < "$bundle/videos.tsv"
if [[ "$failures" -ne 0 ]]; then echo "compare-videos: $failures video(s) differ"; exit 1; fi
echo "compare-videos: every video matches (SSIM at least $limit, same size, length within 0.1 s)"
