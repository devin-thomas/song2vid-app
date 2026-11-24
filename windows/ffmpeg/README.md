# Windows FFmpeg and FFprobe

`./windows/ffmpeg/build.sh` uses Docker on the Mac to cross-build the
Windows x64 binaries. The Linux arm64 toolchain uses a pinned Debian
image and package snapshot. Each invocation downloads and verifies the
two pinned source archives and compiles in a fresh container.
`compile.sh` holds the source URLs, SHA-256 digests and configure arguments.

The default output follows the desktop-app starter's staging layout.

```text
windows/app/staging/
  bin/win32-x64/ffmpeg.exe
  bin/win32-x64/ffprobe.exe
  THIRD-PARTY-NOTICES.txt
```

The starter packager in `windows/app/` copies the two helpers into
`resources/bin/win32-x64/`.
Use the notice generated with the staged pair as the FFmpeg section of the
package's `third-party/THIRD-PARTY-NOTICES.txt` on each package run. It
contains the configure line and the licenses from the actual source and
toolchain. The build accepts a different staging directory as its only
argument, relative to your working directory or absolute.

The programs import Windows system DLLs. They load Media Foundation and
NVENC on demand. The pinned NVIDIA headers require driver 551.76 or later
on Windows. FFmpeg can still start and use Media Foundation without an
NVIDIA driver.

Downstream commands can use the `image2pipe` muxer and PNG encoder for
preview. For HEIC with a Tile Grid stream group, FFprobe's
`-show_stream_groups` reports the assembled dimensions. Pass the group to
a complex filter, for example `-filter_complex "[0:g:0]format=rgb24[image]"
-map "[image]"` for the first group's preview. Mapping an individual stream
would give just one tile.

## Headless acceptance checks

On the Mac, build again into a second directory and generate fixtures
with FFmpeg (with libmp3lame), ImageMagick and libheif's `heif-enc`.

```sh
./windows/ffmpeg/build.sh
./windows/ffmpeg/build.sh build/ffmpeg-repeat
./windows/ffmpeg/test-media.sh build/ffmpeg-media
```

Copy the two staging directories, the generated media and `check.ps1` to
a Windows scratch folder and run the check on Titan.

```powershell
.\check.ps1 -Staging staging -SecondStaging ffmpeg-repeat -Media ffmpeg-media -Machine Titan
```

Run the same command with `-Machine DeskMini` on the DeskMini. It requires
hardware encoding for both Media Foundation encoders. The Titan check
uses NVENC for H.264 and HEVC and the software Media Foundation H.264
encoder. The script also decodes the generated input set, checks two
builds' configurations and feature lists, and reports the total size of
the two executables.
