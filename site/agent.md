---
name: song2vid
description: Make an MP4 from one song and one image with Song2Vid, a Mac app that also has a `song2vid` command. Use when asked to turn a song or audio file plus a picture into a video, or to use Song2Vid.
---

# Song2Vid

Song2Vid turns one audio file and one image into an MP4: the image stays on screen for the whole song. Source: https://github.com/devin-thomas/song2vid-app. Download: https://song2vid.pages.dev.

Pick the route you can do. **Terminal** (you can run commands): the command. **App** (you operate apps by screen): the window. Both make the same video.

## Rules

- Report what you saw. The result or error line, the exit status and the file name come from the run itself; a value you did not read is a value you do not give.
- Ask the person before using `--overwrite`, and before choosing a Frame Shape or Resolution they did not mention when it matters to them (the defaults are 16:9 and 1080p).
- Leave the person's song and image as they are. Song2Vid only reads them.
- The first open of the app is the person's step: macOS shows "Song2Vid.app Not Opened", and they allow it in System Settings → Privacy & Security → **Open Anyway**. Ask them to do it, then carry on.

## Route 1: the command

1. Find it: `command -v song2vid`. If it prints a path, go to step 3.
2. Link it from the app, then check it answers:

   ```
   mkdir -p ~/.local/bin
   ln -sf /Applications/Song2Vid.app/Contents/Helpers/song2vid ~/.local/bin/song2vid
   song2vid --version
   ```

   - No app in `/Applications`: send the person to https://song2vid.pages.dev (unzip, move Song2Vid to Applications, do the first open), then repeat this step.
   - `song2vid: command not found` after linking: add `~/.local/bin` to `PATH` for the shell, for zsh `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc`, and use `~/.local/bin/song2vid` in the meantime.
   - macOS blocks it with "Not Opened": the first-open rule above.
3. Look at the files first (a quick, safe step that also shows which sizes would be enlarged): `song2vid check <audio> <image> --json`. This step is done when you hold one `result` line with the song's length and the image's size, or an `error` line (see Errors).
4. Make the video: `song2vid make <audio> <image> -o <name.mp4> -s <shape> -r <resolution> --json`. The output folder must exist. Use H.264 by default. If the person asks for HEVC or smaller files, run `song2vid encoders --json` and add `--codec hevc` only if `codecs.hevc.available` is true. For a long song, run it in the background if your tools allow, and read the newest line of its output now and then: a `progress` line has `stage`, `percent` (0 to 100) and `remaining_seconds`. This step is done when the last line is a `result` or an `error` line and the command has exited.
5. Tell the person: the file name, pixel size, length, Codec, Encoder, and whether the image was enlarged (`"enlarged": true` means it may look soft). For a failure, give the exit status and the error `code` as they came.

To see the picture with its orientation applied, use `song2vid preview <image> -o <name.png> --json`. Use the PNG named in the result to inspect the picture. It fits within 2048 by 2048 pixels and fills transparency with black.

Try a plan without writing anything: add `--dry-run` to `make`. Everything the command knows is in `song2vid --help` and `song2vid make --help`.

### Options

| Option | Meaning |
| --- | --- |
| `-s`, `--shape` | `16:9` (default), `9:16`, `1:1`, `4:3`, `original` |
| `-r`, `--resolution` | `480p`, `1080p` (default), `2160p`. Not with `original` |
| `-c`, `--crop` | `h,v`, each 0 to 1, which part a `1:1` or `4:3` frame keeps. Default `0.5,0.5` |
| `-C`, `--codec` | `h264` (default) or `hevc` |
| `-o`, `--out` | An MP4 for `make`, which defaults to the song's name in the current folder. `preview` requires a PNG path. |
| `-w`, `--overwrite` | Replace an existing output |
| `-n`, `--dry-run` | Check everything, write nothing |
| `-j`, `--json` | JSON Lines on stdout, stderr empty |
| `-q`, `--quiet` | No progress output |

Programs that run `make` or `preview` can request cancellation on standard input with `--cancel-on-eof`. See the command help for that option.

Write each option separately: `-w -n`, not `-wn`. `16:9` and `9:16` show the whole image with black bars; `1:1` and `4:3` fill the frame and cut the rest; `original` keeps the image's own size, up to 4K.

### Output (`--json`)

Every line has `"api_version":"1"` and a `"type"` of `progress`, `result` or `error`. The last line is exactly one `result` or `error`. Ignore keys you do not recognize.

- `progress`: `stage` (`checking`, `preparing`, `encoding`, `finishing`), `percent` (0 to 100, or `null`), `elapsed_seconds`, `remaining_seconds` (or `null`), and `encoder` from the encoding stage onward.
- `make` `result`: `output` with `name`, `width`, `height`, `duration_seconds`, `bytes`; plus `placement` (`fit` or `crop`), `enlarged`, `dry_run`, `codec`, `encoder`, `encoder_fallback`.
- `check` `result`: `audio`, `image` and `frames`, one per shape and resolution, with `width`, `height`, `placement`, `enlarged`. `song2vid check <file> --json` with one file gives only that file's keys: `audio` for a song, `image` and `frames` for an image.
- `encoders` `result`: `codecs` with `h264` and `hevc`, each with `available` and `encoder`.
- `preview` `result`: `output` has the PNG name and dimensions. `source` has the oriented dimensions before scaling.
- `error`: `error` with `code` and `message`.

Without `--json`, progress goes to stderr and the result to stdout, as plain lines.

### Errors

| Exit | Codes | What to do |
| --- | --- | --- |
| 0 | | Done. |
| 1 | `audio_not_found`, `image_not_found` | Ask for the right path. |
| 2 | `usage` | Fix the command; `song2vid --help` lists every option. |
| 3 | `audio_unreadable`, `image_unreadable`, `image_too_small` | The file is not usable (an image needs 16 pixels on each side for `original`). Ask for another. |
| 3 | `codec_unavailable` | Report that the requested Codec is unavailable on this computer. |
| 4 | `output_exists` | Ask whether to replace it; with a yes, add `-w`. |
| 4 | `output_not_writable`, `output_not_mp4`, `disk_full` | Choose another `-o`, or tell the person the disk is full. |
| 5 | `export_failed` | Report it as it came; try once more. |
| 5 | `network` | From `--update` only: the person is offline. |
| 130 | `cancelled` | The run was stopped. No file was left behind. |

Is a newer Song2Vid out? `song2vid --update` says so and downloads nothing; installing it is the person's step.

## Route 2: the app's window

1. Open Song2Vid. The window has a song slot, an image slot, a **Frame Shape** picker, a **Resolution** picker, a **Codec** picker (H.264 or HEVC), a preview and **Make Video**.
2. Press **Choose Audio**, pick the song. Press **Choose Image**, pick the picture. (Dropping files on the window works too; when a slot is full, a dialog offers Replace or Keep Current.)
3. Set **Frame Shape** and **Resolution**. For `1:1` and `4:3`, drag the preview to choose the part that stays; **Reset to Center** undoes it. Leave **Codec** on H.264 unless the person asks for HEVC; the window remembers the last choice. If HEVC is greyed out, the note under the picker says "This computer can't make HEVC videos.", so stay on H.264.
4. Press **Make Video**. In the save dialog, choose the name and folder.
5. Wait for "Video saved." The progress bar is labelled "Making video" with a percent, and **Cancel** stops it. This step is done when "Video saved." and **Show in Finder** are on screen. The line beside them, "Made as H.264." or "Made as HEVC.", names the Codec.

Tell the person the saved file's name and folder as the dialog showed them.
