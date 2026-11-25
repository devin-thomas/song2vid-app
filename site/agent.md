---
name: song2vid
description: Make an MP4 from one song and one image with Song2Vid, an app for Mac and Windows that also has a `song2vid` command. Use when asked to turn a song or audio file plus a picture into a video, or to use Song2Vid.
---

# Song2Vid

Song2Vid turns one audio file and one image into an MP4: the image stays on screen for the whole song. Source: https://github.com/devin-thomas/song2vid-app. Download: https://song2vid.pages.dev.

Pick the route you can do. **Terminal** (you can run commands): the command. **App** (you operate apps by screen): the window. Both make the same video, on a Mac and on Windows 10 or 11 (64-bit). Use the steps for the system you are on.

## Rules

- Report what you saw. The result or error line, the exit status and the file name come from the run itself; a value you did not read is a value you do not give.
- Ask the person before using `--overwrite`, and before choosing a Frame Shape or Resolution they did not mention when it matters to them (the defaults are 16:9 and 1080p).
- Leave the person's song and image as they are. Song2Vid only reads them.
- The first open of the app is the person's step. On a Mac, macOS shows "Song2Vid.app Not Opened", and they allow it in System Settings → Privacy & Security → **Open Anyway**. On Windows, SmartScreen shows "Windows protected your PC", and they click **More info**, then **Run anyway**. Ask them to do it, then carry on.

## Route 1: the command

1. Find it. Mac (Terminal): `command -v song2vid`. Windows (PowerShell): `Get-Command song2vid`. If it prints a path, go to step 3.
2. Install it, then check it answers.

   **Mac.** Link it from the app:

   ```
   mkdir -p ~/.local/bin
   ln -sf /Applications/Song2Vid.app/Contents/Helpers/song2vid ~/.local/bin/song2vid
   song2vid --version
   ```

   - No app in `/Applications`: send the person to https://song2vid.pages.dev (unzip, move Song2Vid to Applications, do the first open), then repeat this step.
   - `song2vid: command not found` after linking: add `~/.local/bin` to `PATH` for the shell, for zsh `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc`, and use `~/.local/bin/song2vid` in the meantime.
   - macOS blocks it with "Not Opened": the first-open rule above.

   **Windows.** The command is `song2vid.exe` inside the installed app. Run this line once in PowerShell to put it on the user's `PATH`, then open a new terminal and run `song2vid --version`:

   ```powershell
   [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ";$env:LOCALAPPDATA\Programs\Song2Vid\resources\bin\win32-x64", 'User')
   ```

   - The app is not installed (no `%LOCALAPPDATA%\Programs\Song2Vid` folder): send the person to https://song2vid.pages.dev to download Song2Vid for Windows, unzip it and run `Install Song2Vid.cmd`, then repeat this step. The installer needs no administrator rights and never changes `PATH`.
   - `song2vid` is not recognized after the line: the terminal is older than the change. Open a new one. Until then, run `& "$env:LOCALAPPDATA\Programs\Song2Vid\resources\bin\win32-x64\song2vid.exe"` in place of `song2vid`.
   - Windows blocks the app with "Windows protected your PC": the first-open rule above.
3. Look at the files first (a quick, safe step that also shows which sizes would be enlarged): `song2vid check <audio> <image> --json`. This step is done when you hold one `result` line with the song's length and the image's size, or an `error` line (see Errors).
4. Make the video: `song2vid make <audio> <image> -o <name.mp4> -s <shape> -r <resolution> --json`. The output folder must exist. Choose the Codec this way: H.264 (the default) unless the person asks for HEVC or for smaller files. Then run `song2vid encoders --json` and add `--codec hevc` only if `codecs.hevc.available` is true. If it is false, make the H.264 video and say that HEVC was unavailable. For a long song, run it in the background if your tools allow, and read the newest line of its output now and then: a `progress` line has `stage`, `percent` (0 to 100) and `remaining_seconds`. This step is done when the last line is a `result` or an `error` line and the command has exited.
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
| 4 | `output_in_use` | Windows only: another program has the existing output open. Ask the person to close it, then run again. |
| 4 | `output_not_writable`, `output_not_mp4`, `disk_full` | Choose another `-o`, or tell the person the disk is full. |
| 5 | `export_failed` | Report it as it came; try once more. |
| 5 | `network` | From `--update` only: the person is offline. |
| 130 | `cancelled` | The run was stopped. No file was left behind. |

Is a newer Song2Vid out? `song2vid --update` says so and downloads nothing; installing it is the person's step.

## Route 2: the app's window

The window is the same on both systems: a song, an image, a **Frame Shape**, a **Resolution**, a **Codec** (H.264 or HEVC), a preview and **Make Video**. Dropping files on the window works too; when a slot is full, a dialog offers Replace or Keep Current. The window remembers the last Codec. Leave it on H.264 unless the person asks for HEVC or smaller files. If HEVC is greyed out, the note under the picker says "This computer can't make HEVC videos.", so stay on H.264.

### On a Mac

1. Open Song2Vid.
2. Press **Choose Audio**, pick the song. Press **Choose Image**, pick the picture.
3. Set **Frame Shape** and **Resolution**. For `1:1` and `4:3`, drag the preview to choose the part that stays; **Reset to Center** undoes it. Set **Codec**.
4. Press **Make Video**. In the save dialog, choose the name and folder.
5. Wait for "Video saved." The progress bar is labelled "Making video" with a percent, and **Cancel** stops it. This step is done when "Video saved." and **Show in Finder** are on screen. The line beside them, "Made as H.264." or "Made as HEVC.", names the Codec.

Tell the person the saved file's name and folder as the dialog showed them.

### On Windows

1. Open Song2Vid from the Start menu. The controls come in this order: **Choose Audio…**, **Choose Image…**, **Frame Shape**, **Resolution**, **Codec**, the preview, **Make Video**.
2. Press **Choose Audio…** and pick the song in the Windows open dialog, by typing its full path into the file name box if you cannot browse. Press **Choose Image…** and pick the picture the same way. The window then shows the song's length and the image's size.
3. Set **Frame Shape** and **Resolution**. For Original, the window shows "Output: W×H" in place of Resolution. For `1:1` and `4:3`, the preview is one control named **Crop position**, whose value reads like "50% across, 30% down": drag it, or focus it and use the arrow keys (Shift for bigger steps). **Reset to Center** puts it back.
4. Set **Codec**.
5. Press **Make Video**. In the Windows save dialog, choose the name and folder. If Windows asks whether to replace a file, that is the person's choice to confirm.
6. Wait for "Saved <name> to <place>." The status bar shows the stage and a percent while it runs, and **Cancel** stops it with "Cancelled. Nothing was saved." This step is done when "Saved…" and **Show in File Explorer** are on screen. The second line, such as "H.264 · NVIDIA encoder · 0:06", names the Codec, the encoder and the length.

If an error sentence appears, give the person that sentence and press the button beside it, or report it as it came. Tell the person the saved file's name and folder as the window showed them.
