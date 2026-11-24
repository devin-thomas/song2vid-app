#!/bin/bash
# Builds the parity bundle for the Windows command check (S2V-025): generated media, the list of
# command lines (cases.tsv), and what the Mac `song2vid` command printed for each one. The bundle is
# copied to the Windows machine and read by windows/scripts/check.ps1, which runs the same command
# lines through song2vid.exe and compares. Host tools only generate media; nothing here is shipped.
#
#   windows/tool/parity/make-bundle.sh <mac song2vid command> <new folder> [--perf]
#
# --perf adds the large files for the timing and process checks (about 170 MB).
set -euo pipefail
command="${1:?usage: make-bundle.sh <mac song2vid command> <new folder> [--perf]}"
bundle="${2:?usage: make-bundle.sh <mac song2vid command> <new folder> [--perf]}"
perf="${3:-}"
command="$(cd "$(dirname "$command")" && pwd)/$(basename "$command")"
here="$(cd "$(dirname "$0")" && pwd)"
[[ ! -e "$bundle" ]] || { echo "make-bundle: $bundle exists" >&2; exit 1; }
mkdir -p "$bundle/expected"
tool="$(mktemp -d)"
trap 'rm -rf "$tool"' EXIT

swiftc -O "$here/media.swift" -o "$tool/media"
"$tool/media" "$bundle/media"
media="$bundle/media"
# The skill the command prints with --skill is the repository's, byte for byte.
cp "$here/../../../skills/song2vid/SKILL.md" "$bundle/SKILL.md"
mkdir -p "$media/out"

ff() { ffmpeg -hide_banner -loglevel error -nostdin -y "$@"; }
ff -i "$media/tone-44k-mono.caf" -c:a libmp3lame "$media/tone.mp3"
ff -i "$media/tone-44k-mono.caf" -c:a flac "$media/tone.flac"
ff -i "$media/fit-1000x800.png" -c:v libwebp -lossless 1 "$media/still.webp"

if [[ "$perf" == "--perf" ]]; then
  mkdir -p "$bundle/perf"
  # A 50 MB picture: random pixels do not compress.
  magick -size 4000x4000 xc: +noise Random -depth 8 "PNG24:$bundle/perf/noise-50mb.png"
  # A ten-minute song in each container that needs counting by decoding.
  ff -f lavfi -i "sine=frequency=440:sample_rate=44100" -t 600 "$bundle/perf/ten-minutes.wav"
  ff -i "$bundle/perf/ten-minutes.wav" -c:a libmp3lame -b:a 192k "$bundle/perf/ten-minutes.mp3"
  ff -i "$bundle/perf/ten-minutes.wav" -c:a aac -b:a 256k "$bundle/perf/ten-minutes.m4a"
  # Small to store and slow to decode: a picture of 196 million pixels, for the process checks.
  ff -f lavfi -i "color=c=0x336699:s=14000x14000" -frames:v 1 "$bundle/perf/slow-14000.png"
fi

cases="$bundle/cases.tsv"
: > "$cases"
add() { # mode id args...
  local mode="$1" id="$2"; shift 2
  local IFS=$'\t'
  printf '%s\t%s\t%s\n' "$mode" "$id" "$*" >> "$cases"
}

images=(fit-1000x800.png wide-1920x1080.png tall-1000x5000.png big-4000x3000.png trim-3860x2160.png
  scale-4000x2000.png odd-1001x801.png small-16x16.png tiny-15x40.png square-640x640.png
  preview-3001x2000.jpg or1.jpg or6.jpg or8.jpg or5.tiff or7.tiff or3.png or6.png or8.png
  or2.heic or6.heic or8.heic grid-or1.heic grid-or6.heic grid-or8.heic
  still.gif still.bmp still.tiff still.webp transparent.png picture-named-like-a-song.mp3)
exact_songs=(tone-22k-mono.wav tone-44k-stereo.wav tone-8k-stereo.wav tone-48k-stereo.aiff tone-44k-mono.caf
  tone-aac.m4a tone-alac.m4a tone.flac song-named-like-a-picture.png)

# Two files.
for image in "${images[@]}"; do
  add exact "check-text-$image" check tone-44k-stereo.wav "$image"
  add exact "check-json-$image" check tone-44k-stereo.wav "$image" --json
done
for song in "${exact_songs[@]}"; do
  add exact "check-text-$song" check "$song" fit-1000x800.png
  add exact "check-json-$song" check "$song" fit-1000x800.png -j
done
# MP3 headers carry encoder padding that the Mac counts and FFmpeg does not: the length may differ by a little.
add approx-length "check-json-tone.mp3" check tone.mp3 fit-1000x800.png --json

# One file, each kind, as text and JSON.
for file in "${exact_songs[@]}" "${images[@]}"; do
  add exact "one-text-$file" check "$file"
  add exact "one-json-$file" check "$file" --json
done
add approx-length "one-json-tone.mp3" check tone.mp3 --json

# Errors: missing, unreadable, folders, both missing, order of checks.
for name in gone.wav gone.png gone no-extension not-a-song.mp3 not-a-picture.png notes.txt a-folder a-folder.wav; do
  add exact "one-error-$name" check "$name"
  add exact "one-error-json-$name" check "$name" --json
done
for pair in "gone.wav fit-1000x800.png" "tone-44k-stereo.wav gone.png" "gone.wav gone.png" "not-a-song.mp3 fit-1000x800.png" \
  "tone-44k-stereo.wav not-a-picture.png" "a-folder fit-1000x800.png" "tone-44k-stereo.wav a-folder" "not-a-song.mp3 gone.png" \
  "fit-1000x800.png tone-44k-stereo.wav" "tone-44k-stereo.wav tone-22k-mono.wav"; do
  read -r first second <<< "$pair"
  add exact "two-error-$first-$second" check "$first" "$second"
  add exact "two-error-json-$first-$second" check "$first" "$second" --json
done

# Usage errors and the global options.
add exact usage-none
add exact usage-check-none check
add exact usage-check-three check one two three
add exact usage-check-three-json check one two three -j
for option in --frobnicate -Z -vh -- -U -X - -jj -hj "--zzz-typed-text"; do
  add exact "usage-global-$option" "$option"
  add exact "usage-check-$option" check tone-44k-stereo.wav fit-1000x800.png "$option"
  add exact "usage-check-json-$option" check tone-44k-stereo.wav fit-1000x800.png "$option" --json
done
for option in --versoin --hlep --version=2 --repoo --jsno --jsonn --json=1; do
  add exact "usage-near-$option" "$option"
  add exact "usage-check-near-$option" check tone-44k-stereo.wav fit-1000x800.png "$option"
done
add exact usage-command frobnicate-the-widget
add exact usage-two-options --version --help
add exact usage-json-alone --json
add exact usage-json-alone-short -j
add exact usage-json-version --version --json
for option in --version -v --repo -R -o --out -s -n -q --overwrite -S --skill -u --update; do
  add exact "usage-check-scope-$option" check tone-44k-stereo.wav fit-1000x800.png "$option"
done
add exact global-version --version
add exact global-version-short -v
add exact global-repo --repo
add exact global-repo-short -R
add exact global-help --help
add exact global-help-short -h
for word in check make encoders preview; do
  add exact "help-$word" "$word" --help
  add exact "help-$word-short" "$word" -h
done
add exact help-wins check -h nothing nothing-else
add exact help-wins-json check --json -h
# make and encoders: only their usage rules are in this ticket.
add exact make-usage-two make tone-44k-stereo.wav
add exact make-usage-shape make tone-44k-stereo.wav fit-1000x800.png -s 5:4 -j
add exact make-usage-resolution make tone-44k-stereo.wav fit-1000x800.png -r 720p
add exact make-usage-original-resolution make tone-44k-stereo.wav fit-1000x800.png -s original -r 480p -j
add exact make-usage-crop make tone-44k-stereo.wav fit-1000x800.png -c 0.5,0.5
add exact make-usage-crop-range make tone-44k-stereo.wav fit-1000x800.png -s 1:1 --crop=1.5,0
add exact make-usage-codec make tone-44k-stereo.wav fit-1000x800.png -C av1 -j
add exact make-usage-clustered make tone-44k-stereo.wav fit-1000x800.png -wn
add exact make-usage-twice make tone-44k-stereo.wav fit-1000x800.png -s 1:1 -s 4:3
add exact make-usage-missing-value make tone-44k-stereo.wav fit-1000x800.png -o -w
add exact encoders-usage encoders unused -j

# Preview: the JSON or text, and the picture, compared by the colour of each quadrant.
previews=(preview-3000x1500.png preview-3001x2000.jpg big-4000x3000.png fit-1000x800.png tiny-15x40.png
  or1.jpg or2.jpg or3.jpg or4.jpg or5.jpg or6.jpg or7.jpg or8.jpg or5.tiff or6.tiff or7.tiff or8.tiff
  or3.png or6.png or8.png or1.heic or2.heic or3.heic or4.heic or5.heic or6.heic or7.heic or8.heic
  grid-or1.heic grid-or6.heic grid-or8.heic transparent.png half-transparent.png still.gif still.bmp still.tiff still.webp)
for image in "${previews[@]}"; do
  add preview "preview-json-$image" preview "$image" -o "out/preview-json-$image.png" -w --json
done
add preview preview-text preview or6.jpg -o out/preview-text.png -w
add preview preview-long-option preview or6.jpg --out out/preview-long-option.png --overwrite
add preview preview-attached preview or6.jpg --out=out/preview-attached.png -w
add exact preview-usage-no-out preview or6.jpg -j
add exact preview-usage-no-image preview -o out/x.png -j
add exact preview-usage-two preview or6.jpg fit-1000x800.png -o out/x.png -j
add exact preview-usage-extension preview or6.jpg -o out/x.jpg -j
add exact preview-usage-short-name preview or6.jpg -o .png -j
add exact preview-missing preview gone.jpg -o out/x.png -w -j
add exact preview-unreadable preview not-a-picture.png -o out/x.png -w -j
add exact preview-folder preview a-folder -o out/x.png -w -j
add exact preview-song-as-image preview tone-22k-mono.wav -o out/x.png -w -j
add exact preview-folder-missing preview or6.jpg -o missing-folder/x.png -w -j
add exact preview-output-is-input preview fit-1000x800.png -o fit-1000x800.png -w -j
add exact preview-cancel-on-closed-stdin preview or6.jpg -o out/x.png -w -j -E

# Run every case with the Mac command in the media folder.
while IFS=$'\t' read -r mode id args; do
  IFS=$'\t' read -r -a argv <<< "$args"
  (cd "$media" && "$command" ${argv[@]+"${argv[@]}"} > "$bundle/expected/$id.out" 2> "$bundle/expected/$id.err" < /dev/null; echo $? > "$bundle/expected/$id.status") || true
  if [[ "$mode" == preview && -f "$media/out/$id.png" ]]; then mv "$media/out/$id.png" "$bundle/expected/$id.png"; fi
done < "$cases"
echo "make-bundle: $(wc -l < "$cases" | tr -d ' ') cases in $bundle"
