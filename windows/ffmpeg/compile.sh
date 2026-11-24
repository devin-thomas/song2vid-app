#!/usr/bin/env bash
# Runs inside the pinned Linux toolchain image. Paths are fixed between builds.
set -euo pipefail
export LC_ALL=C

ffmpeg_version=8.1.3
ffmpeg_url=https://ffmpeg.org/releases/ffmpeg-$ffmpeg_version.tar.xz
ffmpeg_sha=7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3
nv_version=n12.2.72.0
nv_rev=c69278340ab1d5559c7d7bf0edf615dc33ddbba7
nv_url=https://codeload.github.com/FFmpeg/nv-codec-headers/tar.gz/$nv_rev
nv_sha=0d06ccc7410671e8ea075f29abb7c1f6c793574d8c768dc1bc96b142797b6628

mkdir /tmp/song2vid-ffmpeg
cd /tmp/song2vid-ffmpeg
download() {
  local url=$1 sha=$2 archive=$3
  curl --fail --silent --show-error --location --retry 3 -o "$archive" "$url"
  printf '%s  %s\n' "$sha" "$archive" | sha256sum --check
}
download "$ffmpeg_url" "$ffmpeg_sha" ffmpeg.tar.xz
download "$nv_url" "$nv_sha" nv-codec-headers.tar.gz
tar -xf ffmpeg.tar.xz
tar -xf nv-codec-headers.tar.gz
headers=$PWD/nv-codec-headers-$nv_rev
make -C "$headers" PREFIX="$PWD/nv" install
export PKG_CONFIG_LIBDIR="$PWD/nv/lib/pkgconfig:/usr/x86_64-w64-mingw32/lib/pkgconfig"

cd "ffmpeg-$ffmpeg_version"
# The MOV demuxer reads M4A and HEIC. xstack assembles tiled HEIC items.
# The GIF parser assembles complete frames from the GIF demuxer.
# PNG encoding and the image muxers are needed for the preview command.
# The Media Foundation encoder in this release compiles D3D11 helpers.
decoders=mp3,aac,aac_latm,flac,alac,adpcm_ima_qt,adpcm_ima_wav,adpcm_ms
decoders+=,pcm_s8,pcm_u8,pcm_s16be,pcm_s16le,pcm_s24be,pcm_s24le,pcm_s32be,pcm_s32le,pcm_s64le
decoders+=,pcm_f32be,pcm_f32le,pcm_f64be,pcm_f64le,pcm_alaw,pcm_mulaw
decoders+=,mjpeg,png,hevc,tiff,webp,gif,bmp,h264
configure=(
  --target-os=mingw32 --arch=x86_64 --cross-prefix=x86_64-w64-mingw32-
  --enable-cross-compile --pkg-config=pkg-config --disable-autodetect --disable-everything
  --disable-network --disable-avdevice --disable-doc --disable-ffplay --disable-debug
  --disable-gpl --disable-nonfree --disable-shared --enable-static
  --extra-ldflags='-static -Wl,--no-insert-timestamp'
  --enable-zlib --enable-ffnvcodec --enable-nvenc --enable-mediafoundation --enable-d3d11va
  "--enable-protocol=file,pipe"
  "--enable-demuxer=mp3,aac,mov,wav,aiff,flac,caf,image2,image2pipe,image_jpeg_pipe,image_png_pipe,image_tiff_pipe,image_webp_pipe,gif,image_bmp_pipe"
  "--enable-parser=aac,aac_latm,flac,gif,hevc,h264,mjpeg,png,webp"
  "--enable-decoder=$decoders"
  "--enable-encoder=h264_nvenc,hevc_nvenc,h264_mf,hevc_mf,aac,png"
  "--enable-muxer=mp4,image2,image2pipe"
  "--enable-filter=aresample,scale,pad,crop,format,setsar,xstack,color,overlay"
)
if ! ./configure "${configure[@]}"; then
  grep -Ei 'pkg-config|ffnvcodec|mediafoundation|mftransform|MFCreateAlignedMemoryBuffer' ffbuild/config.log | tail -70 >&2
  tail -12 ffbuild/config.log >&2
  exit 1
fi

# Fail the build if configure dropped a requested encoder or changed the license tier.
for encoder in H264_NVENC HEVC_NVENC H264_MF HEVC_MF AAC PNG; do
  grep -qx "#define CONFIG_${encoder}_ENCODER 1" config_components.h
done
for image in JPEG PNG TIFF WEBP BMP; do
  grep -qx "#define CONFIG_IMAGE_${image}_PIPE_DEMUXER 1" config_components.h
done
grep -qx '#define CONFIG_GIF_PARSER 1' config_components.h
grep -qx '#define CONFIG_GPL 0' config.h
grep -qx '#define CONFIG_NONFREE 0' config.h
if ! make -j4 > make.log 2>&1; then
  tail -100 make.log >&2
  exit 1
fi

for binary in ffmpeg.exe ffprobe.exe; do
  x86_64-w64-mingw32-strip "$binary"
  # System DLL imports only. NVENC and Media Foundation are loaded on demand.
  x86_64-w64-mingw32-objdump -p "$binary" | awk '/DLL Name:/ {print tolower($3)}' > "$binary.imports"
  [[ -s "$binary.imports" ]]
  if grep -vxE '(advapi32|bcrypt|kernel32|msvcrt|ole32|psapi|shell32|user32)\.dll' "$binary.imports"; then
    echo "Unexpected DLL import in $binary" >&2
    exit 1
  fi
  install -m 755 "$binary" /out/
done

# Keep the notice tied to the actual configure arguments and installed runtimes.
{
  cat <<NOTICE
Song2Vid bundles unmodified FFmpeg and FFprobe $ffmpeg_version as separate
command-line programs under the GNU Lesser General Public License, version
2.1 or later (LGPL-2.1-or-later).

FFmpeg source: $ffmpeg_url
FFmpeg source SHA-256: $ffmpeg_sha

nv-codec-headers $nv_version (MIT)
Source: $nv_url
Source SHA-256: $nv_sha
The headers are used to load NVENC from the NVIDIA display driver at run time.
The driver and Microsoft Media Foundation components come from the host.

Build recipe: https://github.com/devin-thomas/song2vid-app/tree/build/v3/windows/ffmpeg
Static runtime and zlib packages from the Debian snapshot pinned in Dockerfile:
NOTICE
  dpkg-query -W gcc-mingw-w64-x86-64-win32-runtime mingw-w64-x86-64-dev libz-mingw-w64-dev
  printf '\nFFmpeg configure line:\n./configure'
  for flag in "${configure[@]}"; do
    printf ' %q' "$flag"
  done
  printf '\n\n--- FFmpeg LGPL text ---\n'
  cat COPYING.LGPLv2.1
  for header in "$headers"/include/ffnvcodec/*.h; do
    printf '\n--- nv-codec-headers: %s ---\n' "${header##*/}"
    sed '/^ \*\//q' "$header"
  done
  for package in gcc-mingw-w64-x86-64-win32-runtime mingw-w64-x86-64-dev libz-mingw-w64-dev; do
    printf '\n--- Debian %s copyright and license ---\n' "$package"
    cat "/usr/share/doc/$package/copyright"
  done
  for license in LGPL-2 GPL-2 GPL-3; do
    printf '\n--- GNU %s (referenced in the notices above) ---\n' "$license"
    cat "/usr/share/common-licenses/$license"
  done
} > /out/THIRD-PARTY-NOTICES.txt
wc -c /out/ffmpeg.exe /out/ffprobe.exe
