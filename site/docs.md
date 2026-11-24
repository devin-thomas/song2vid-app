# The song2vid command

Song2Vid is also a command for Terminal, for scripts and for agents. It comes inside the app and makes the same video as the window does.

## Install

Download Song2Vid from [the download page](https://song2vid.pages.dev/), move it to Applications and open it once (see the first-open step below). Then link the command onto your path:

```
mkdir -p ~/.local/bin
ln -sf /Applications/Song2Vid.app/Contents/Helpers/song2vid ~/.local/bin/song2vid
song2vid --version
```

If Terminal says `command not found`, add the folder to your path for zsh, then open a new Terminal window:

```
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

**First open.** The app is not signed with a paid Apple developer account. The first time, macOS says "Song2Vid.app Not Opened". Go to System Settings → Privacy & Security and click **Open Anyway**. The command works after that.

## Commands

```
song2vid check <audio> <image> [-j]
song2vid check <file> [-j]
song2vid make  <audio> <image> [-o <file.mp4>] [-s <shape>] [-r <resolution>] [-c <h,v>] [-C <codec>] [-w] [-n] [-j] [-q] [-E]
song2vid encoders [-j]
song2vid preview <image> -o <file.png> [-w] [-j] [-E]
song2vid -h | -v | -S | -R | -u
```

- `check` reads a song and an image and reports what Song2Vid would make from them. It writes nothing. With one file, it reports only that file: the song's facts, or the image's size and every output size. The kind comes from what is inside the file.
- `make` makes the video: the image for the whole length of the song. It never changes your files and never replaces a file unless you say so.
- `encoders` reports which Codecs are available on this computer.
- `preview` writes an oriented PNG within 2048 by 2048 pixels. Smaller images keep their size. Transparency becomes black.
- `--help` prints help. After a command it prints that command's help.
- `--version` prints the version, for example `song2vid 1.2.0`.
- `--skill` prints the [agent instructions](https://song2vid.pages.dev/agent.md).
- `--repo` prints the project address.
- `--update` says whether a newer Song2Vid is out. It downloads and changes nothing; installing it is your step.

## Options

| Long | Short | Applies to | Meaning |
| --- | --- | --- | --- |
| `--help` | `-h` | all | Help for the command it follows. |
| `--version` | `-v` | alone | Prints `song2vid 1.2.0`. |
| `--skill` | `-S` | alone | Prints the agent skill that ships in the app. |
| `--repo` | `-R` | alone | Prints the project address. |
| `--update` | `-u` | alone | Says whether a newer release exists. Works with `--json`. |
| `--shape` | `-s` | make | `16:9` (default), `9:16`, `1:1`, `4:3` or `original`. |
| `--resolution` | `-r` | make | `480p`, `1080p` (default) or `2160p`. Not with `original`. |
| `--crop` | `-c` | make | Which part a `1:1` or `4:3` frame keeps, as two fractions `h,v` from 0 to 1. Default `0.5,0.5`, the middle. Values outside 0 to 1 are an error. |
| `--codec` | `-C` | make | `h264` (default) or `hevc`. Check availability with `encoders`. |
| `--out` | `-o` | make, preview | An MP4 for `make`, which defaults to the song's name in the current folder. `preview` requires a PNG path. |
| `--overwrite` | `-w` | make, preview | Replace the output if it exists. Without it, an existing file is an error. |
| `--cancel-on-eof` | `-E` | make, preview | For programs running the command. Cancel when standard input closes or sends a line containing only `cancel`. Standard input is read only with this option. |
| `--dry-run` | `-n` | make | Checks everything and reports what would be made. Writes nothing. |
| `--json` | `-j` | check, make, encoders, preview, `--update` | One JSON object per line instead of text. |
| `--quiet` | `-q` | make | No progress output. The result and any error still print. |

Write each short option on its own: `-w -n`, not `-wn`. An option the command does not know is a usage error, and the message does not repeat what you typed. When you are one typo from a real option, it says which.

## Frame shapes and sizes

The `p` in a resolution is the short side of the frame.

| Shape | Placement | 480p | 1080p | 2160p |
| --- | --- | --- | --- | --- |
| `16:9` | Whole image, with black bars | 854×480 | 1920×1080 | 3840×2160 |
| `9:16` | Whole image, with black bars | 480×854 | 1080×1920 | 2160×3840 |
| `1:1` | Fills the frame; the rest is cut | 480×480 | 1080×1080 | 2160×2160 |
| `4:3` | Fills the frame; the rest is cut | 640×480 | 1440×1080 | 2880×2160 |

`original` keeps the image's own size, up to 3840×2160 (or 2160×3840 for a tall image). Larger images are scaled down, and an odd size loses one pixel because video needs even sizes. An image smaller than the chosen size is enlarged and may look soft; `check` and the result say so with `enlarged`.

## Examples

```
# What would Song2Vid make from these two files?
song2vid check song.mp3 cover.png

# A 1080p 16:9 video next to the song, named after it
song2vid make song.mp3 cover.png

# A square 480p preview, keeping the upper part of the picture
song2vid make song.mp3 cover.png -s 1:1 -r 480p -c 0.5,0.2 -o preview.mp4

# Plan it without writing anything, as JSON
song2vid make song.mp3 cover.png --dry-run --json

# Check HEVC availability, then make an HEVC video
song2vid encoders --json
song2vid make song.mp3 cover.png --codec hevc -o video.mp4

# Save a PNG preview from a photo
song2vid preview photo.heic -o cover.png
```

## Progress

`make` never leaves you wondering whether it works. The stages are `Checking files`, `Preparing`, `Encoding` and `Finishing`.

- **In a terminal** one line is redrawn at least ten times a second: a spinner while the percent is not known yet, then a bar with the percent, the time elapsed and the time left. It is replaced by the result when the video is done. Colour is used unless `NO_COLOR` is set or `TERM` is `dumb`.
- **In a log or a pipe** a plain line is written at each stage change and every second, such as `Encoding 52% (0:04 elapsed, about 0:04 left)`. It has no control characters.
- **With `--json`** progress is JSON Lines on standard output, at each stage change and four times a second, and standard error stays empty. A run in the background can be read at any moment by looking at its newest line.
- `--quiet` shows no progress. `Checking files` is shown only if it takes more than a moment, so a mistyped file name gives just its error.

Results go to standard output. Progress, messages and errors go to standard error, except with `--json`, where everything is a JSON line on standard output.

## JSON output

Every line has `"api_version":"1"` and a `"type"` of `progress`, `result` or `error`. The last line of a run is exactly one `result` or `error`. New keys, line types and commands may be added within an `api_version`. Existing keys keep their names and meanings. Consumers ignore unknown keys.

```
{"api_version":"1","type":"progress","stage":"encoding","percent":52.0,"elapsed_seconds":4.1,"remaining_seconds":3.8,"encoder":"apple"}
{"api_version":"1","type":"result","command":"make","output":{"name":"song.mp4","width":1920,"height":1080,"duration_seconds":144.0,"bytes":6153216},"placement":"fit","enlarged":false,"dry_run":false,"codec":"h264","encoder":"apple","encoder_fallback":false}
{"api_version":"1","type":"error","error":{"code":"output_exists","message":"The output file already exists. Use --overwrite to replace it."}}
```

| Line | Keys | Added in |
| --- | --- | --- |
| All lines | `api_version`, `type` | 1.1.0 |
| `progress` | `stage` (`checking`, `preparing`, `encoding`, `finishing`), `percent` (0 to 100, or `null`), `elapsed_seconds`, `remaining_seconds` (or `null`) | 1.1.0 |
| `make` result | `command`, `output` (`name`, `width`, `height`, `duration_seconds`, `bytes`), `placement` (`fit` or `crop`), `enlarged`, `dry_run`. `bytes` is `null` for a dry run. | 1.1.0 |
| `check` result | `command`, `audio` (`name`, `duration_seconds`, `sample_rate`, `channels`), `image` (`name`, `width`, `height`), `frames`: one for every shape and resolution with `shape`, `resolution`, `width`, `height`, `placement`, `enlarged`, `too_small`. With one file, only that file's keys: `audio`, or `image` and `frames` | 1.1.0; one file 1.2.0 |
| `--update` result | `command`, `current`, `latest`, `update_available`, `download_page` | 1.1.0 |
| `error` | `error` (`code`, `message`) | 1.1.0 |
| `progress` | `encoder` from the `encoding` stage onward | 1.2.0 |
| `make` result | `codec` (`h264` or `hevc`), `encoder` (`apple` on Mac), `encoder_fallback` (always `false` on Mac) | 1.2.0 |
| `encoders` result | `codecs` contains `h264` and `hevc`, each with `available` and `encoder` (`null` if unavailable) | 1.2.0 |
| `preview` result | `output` (`name`, `width`, `height`) and `source` (oriented `width` and `height` before scaling) | 1.2.0 |

No output, in any mode, contains a folder path, an environment variable or the contents of your files. File names are given without their folder.

## Exit statuses and error codes

| Status | Meaning | Error codes |
| --- | --- | --- |
| 0 | Success, including `--dry-run` and `check`. |  |
| 1 | An input file does not exist. | `audio_not_found`, `image_not_found` |
| 2 | Usage error. | `usage` |
| 3 | An input can't be used or the chosen Codec is unavailable. | `audio_unreadable`, `image_unreadable`, `image_too_small`, `codec_unavailable` |
| 4 | The output can't be written. | `output_exists`, `output_not_writable`, `output_not_mp4`, `disk_full`, `output_in_use` (Windows only) |
| 5 | Making the video or preview failed, or `--update` could not reach GitHub. | `export_failed`, `network` |
| 130 | Cancelled by a signal or by standard input with `--cancel-on-eof`. The unfinished file is deleted. | `cancelled` |

Everything is checked before anything is made. The video is built in a hidden temporary file beside the output and moved into place when it is complete, so a half-made video never has the final name.

## The app's window

The window does the same job without Terminal: choose or drop in a song and an image, pick a **Frame Shape**, a **Resolution** and a **Codec**, drag the preview to choose the crop, press **Make Video** and choose where to save. It is described step by step, by its control names, in the [agent instructions](https://song2vid.pages.dev/agent.md).

## For agents

An agent can read [song2vid.pages.dev/agent.md](https://song2vid.pages.dev/agent.md), or run `song2vid --skill` for the same text. It covers both routes, the window and the command, and the rules an agent follows: ask before `--overwrite`, leave the input files alone, report only what the command printed, and leave the first-open step to the person.

---

This is the Markdown copy of https://song2vid.pages.dev/docs/. Updated 2026-11-22.
