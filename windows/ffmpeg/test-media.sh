#!/usr/bin/env bash
# The host tools are only used to generate media, never shipped.
set -euo pipefail
if (( $# != 1 )); then
  echo "usage: $0 <sample-directory>" >&2
  exit 2
fi
mkdir -p "$1"
cd "$1"

ff() {
  ffmpeg -hide_banner -loglevel error -nostdin -y "$@"
}

magick -size 320x240 gradient:navy-gold PNG24:still.png
for extension in jpg tif webp gif bmp; do
  magick still.png "still.$extension"
done
heif-enc -o still.heic still.png

# A tiled HEIC requires assembling the primary image instead of reading one tile.
magick -size 160x240 xc:navy PNG24:tile-0-0.png
magick -size 160x240 xc:gold PNG24:tile-0-1.png
heif-enc -T -o tiled.heic tile-0-0.png
rm tile-0-0.png tile-0-1.png

ff -f lavfi -i sine=frequency=440:sample_rate=44100 -t 10 tone.wav
ff -i tone.wav -c:a libmp3lame tone.mp3
ff -i tone.wav -c:a aac tone.m4a
ff -i tone.wav -c:a aac tone.aac
ff -i tone.wav -c:a alac lossless.m4a
ff -i tone.wav -c:a flac tone.flac
ff -i tone.wav -c:a pcm_s24be tone.aiff
ff -i tone.wav -c:a pcm_f32le tone.caf
