# Song2Vid — Specification

Terms in **bold** are defined in `GLOSSARY.md`. Reasons for decisions are in `ADR.md`.

## 1. Objective

A person with a song and a picture gets a video file they can upload anywhere. They choose the files, pick a **Frame Shape** and **Resolution**, adjust the **Crop** if needed, and save an MP4. Other people get the app from a minimal download page.

## 2. Success criteria

- A person can make a correct video from an audio file and an image file in under a minute of clicks, with no instructions beyond the download page.
- The output has exactly the pixel size in section 5, and its length matches the song to within 0.1 seconds.
- The app downloads from the live page, opens on a Mac after the documented first-open step, and works.

## 3. Platform and stack

- Native macOS app: Swift, SwiftUI, AVFoundation (ADR-001). macOS 14 or later. Universal build (Apple silicon and Intel).
- Ad-hoc signed and not notarized (ADR-005). Distributed as a `.zip` on GitHub Releases (ADR-008).
- Download page: one static HTML page with inline CSS on Cloudflare Pages (ADR-002). No JavaScript framework, no analytics, no cookies, no third-party requests. (Version 1.1 adds one small first-party script, a docs page and the Agent Guide: section 16.)

## 4. Main window

One window. From top to bottom:

1. **Audio:** a "Choose Audio…" button. Once a file is chosen, it shows the file name and length (m:ss).
2. **Image:** a "Choose Image…" button. Once a file is chosen, it shows the file name and pixel size.
3. **Frame Shape:** a five-way picker: 16:9, 9:16, 1:1, 4:3, Original. Default 16:9.
4. **Resolution:** a three-way picker: 480p, 1080p, 2160p. Default 1080p. It is hidden for Original, which shows "Output: W×H" instead.
5. **Preview:** the output frame drawn to scale, with the image placed exactly as it will be in the video.
   - Fit with bars (16:9, 9:16): the whole image is centered with black bars.
   - Crop (1:1, 4:3): the image fills the frame. Dragging moves it so a different part is kept. It can't be dragged past an edge. The arrow keys nudge it, for keyboard use. "Reset to Center" restores the starting position. The crop position is kept while switching Resolution, and resets when the image or Frame Shape changes.
   - Before an image is chosen, the preview shows the empty frame with the words "Choose an image". There is no demo content.
6. **Enlarge note:** "This image is smaller than W×H and will be enlarged, so it may look soft." It is shown when the image would be scaled up.
7. **Make Video** button. It is enabled only when both files are loaded.

Choosing a file with a button replaces the current one, since that is a deliberate choice. Dropped files follow section 4a. Nothing is changed or deleted in the person's original files.

## 4a. Drag and drop

- The whole window accepts dropped files: one audio file, one image file, or one of each. Each file goes to its slot by type, wherever it is dropped.
- An empty slot is filled straight away.
- **If a slot is already filled**, a dialog asks first. It names what is there and what was dropped: "Replace the current song?", "Replace the current image?", or "Replace the current song and image?" There are two buttons:
  - **Replace**: the dropped file is used.
  - **Keep Current**: the default, also chosen with Esc. The dropped file is discarded and the current one is unchanged.

  If one of the dropped files goes to an empty slot, that slot is filled either way.
- **Rejected drops** change nothing and show a short message: two or more audio files, two or more images, more than two files, a folder, or a file type Song2Vid can't read.
- While a video is being made, drops are refused, with the message "Wait for the current video to finish."
- A dropped file is checked the same way as a chosen file (section 7) before anything is replaced. An unreadable file never replaces a good one.
- While a valid drop is held over the window, the window shows a highlight. An invalid drop shows no highlight.

## 5. Output frame sizes

"p" is the frame's short side.

| Frame Shape | Placement | 480p | 1080p | 2160p |
| --- | --- | --- | --- | --- |
| 16:9 | Fit with bars | 854×480 | 1920×1080 | 3840×2160 |
| 9:16 | Fit with bars | 480×854 | 1080×1920 | 2160×3840 |
| 1:1 | Crop | 480×480 | 1080×1080 | 2160×2160 |
| 4:3 | Crop | 640×480 | 1440×1080 | 2880×2160 |

**Original**, for an image of W×H after applying its orientation tag:

1. **Limit:** landscape or square images fit within 3840×2160. Portrait images fit within 2160×3840. Scale factor `s = min(1, limitLong / long side, limitShort / short side)`.
2. If `s = 1`, the size stays W×H.
3. If `s ≥ 0.99` (less than 1% too big), the image is not scaled. The excess is trimmed equally from both edges of the side or sides that are too big.
4. If `s < 0.99`, the image is scaled to `floor(W·s) × floor(H·s)`, keeping its shape.
5. **Even sizes:** an odd width or height loses one pixel, from the right or bottom edge.
6. Images with either side under 16 pixels are rejected with a message.
7. When an odd number of pixels is trimmed in rule 3, the extra pixel comes off the right or bottom edge.

The crop position is stored as two fractions from 0 to 1 (0.5, 0.5 is centered), so it survives a Resolution change. Positions past an edge are clamped.

## 6. Making the video

1. Clicking Make Video opens a standard macOS save dialog. The default name is the audio file's name with `.mp4`. The default folder is the folder of the last save, or Movies. macOS asks before replacing an existing file.
2. A progress bar shows the percentage done, with a Cancel button. The other controls are disabled while it runs.
3. The output is MP4: H.264 video at 30 frames per second, with the still frame for the whole song. Audio is AAC at 256 kbps, keeping the source sample rate up to 48 kHz. Higher rates (for example 88.2 or 96 kHz) are converted to 48 kHz, because the AAC encoder can't take them. Rates the AAC encoder doesn't have (for example 37.8 kHz) go to the next rate up. Below 44.1 kHz the encoder can't reach 256 kbps, so it uses the highest bit rate it allows for that rate. Channels stay as in the source (stereo or mono); sources with more than two channels are mixed down to stereo. The video's length equals the audio's length.
4. On success: "Video saved." with a "Show in Finder" button. The controls unlock, so the person can make another video straight away.
5. **On Cancel or failure:** the half-written file is deleted. On failure, a plain message names the step that failed ("Couldn't read the audio file", "Couldn't save to that folder", "Not enough disk space").

## 7. Supported inputs

- **Audio:** anything macOS can decode: MP3, M4A/AAC, WAV, AIFF, FLAC, ALAC, CAF. Other files, or files with no audio track: "Song2Vid can't read this audio file."
- **Image:** JPEG, PNG, HEIC, TIFF, WebP, GIF (first frame), BMP. Orientation tags are respected. Transparent areas become black. Other files: "Song2Vid can't read this image file."
- The file pickers open only the types above. Drops follow section 4a.

## 8. Download page

- Address: `song2vid.pages.dev`, falling back to `song2vid-app.pages.dev` (PROJECT.md).
- Content, in order: the name and a one-line description; a "Download for Mac" button linking to the latest release zip; the requirement (macOS 14 or later); then three steps:
  1. Unzip and move Song2Vid to Applications.
  2. Open it. If macOS blocks it, go to System Settings → Privacy & Security → Open Anyway.
  3. Choose a song and an image, then click Make Video.

  Last, a link to the source code on GitHub.
- It is readable on a phone without zooming, and zoom is not disabled. It has no tracking.

## 9. Public repository rules (ADR-003, ADR-007)

- Commits use the owner's name and the GitHub noreply address set in the repo, with no AI co-author lines.
- `.gitignore` excludes `build/`, `DerivedData/`, `*.xcuserstate`, `xcuserdata/`, `.env*`, `*.zip` outside releases, `.wrangler/`, `.DS_Store`, and any `TestMedia/` folder.
- Test media is generated by the tests or is original, licence-free content made for this repo.
- No tokens, account IDs, emails, tailnet addresses, or `/Users/...` paths in committed files. Checked before every push.
- GitHub secret scanning and push protection are on.
- Cloudflare credentials stay in Wrangler's own login storage, never in the repo.

## 9a. App icon and branding

- Song2Vid has its own original icon that shows what it does: a song becoming a video. For example, a music note together with a play symbol or film frame. It is drawn in-repo as vector source, with no third-party artwork or fonts.
- It follows the macOS icon shape (rounded square) and stays recognisable at 16×16. It is supplied at every size macOS needs, and Finder, the Dock and the About window show it.
- The same mark is used as the download page's favicon and header image.

## 10. Accessibility

- Every control has a VoiceOver label. The crop can be adjusted with the keyboard.
- Text follows the system size and contrast settings. Supports light and dark mode.

## 11. Testing

- **Agreed test seams** (approved with the plan, 2026-11-18): (1) frame calculation: inputs are image size, Frame Shape, Resolution and crop position; outputs are frame size and image placement; (2) drop handling: inputs are the current slots and the dropped files; outputs are the new slots, the dialog to show, or the rejection message; (3) video export: inputs are files and placement; output is an MP4 file or an error. (4) added by the coordinator on 2026-11-19 for S2V-004 and later: the main window model's public behavior. A fake exporter there stands in for AVFoundation, a system boundary. Tests go only at these seams, plus the manual checks below.
- **Unit tests:** every cell of the section 5 table; the Original rules (exact, under 1% trim, over 1% scale, odd sizes, too small, portrait limit); the Crop limits; the Fit with bars placement; every case in section 4a.
- **Integration tests:** generate a 3-second tone and a test image, then export each Frame Shape at 480p and one at 2160p. Check the MP4's pixel size, the length (±0.1 s), that both tracks are present, and that Cancel removes the file.
- **Manual checks:**
  - The agent runs the built app on this Mac and saves one video per Frame Shape, with real files the owner chooses.
  - The owner downloads from the live page, opens the app with the first-open step, makes a video, and plays it. This is recorded as an owner report.

## 12. Definition of done

- All tickets' acceptance criteria are met and the tests pass.
- Version 1.0.0 is released on GitHub, and the live page downloads that zip.
- The repo history shows only the owner as author, and the public-repo checks pass.

---

# Part 2 — Version 1.1: Song2Vid for agents

Agreed in Phase 3 discovery, 2026-11-21 (`PROJECT.md`, ADR-013 to ADR-020). Part 1 still applies unless a section below changes it.

## 13. Objective

An agent can make a Song2Vid video for someone, through the app's window or the `song2vid` command, and a person can hand that job to the chat agent they already use with one short prompt.

Success criteria:

- A new Claude Code session that has never seen this project installs the command from the release, makes a video, and reports one deliberate failure's exit status and error code without inventing anything. The owner confirms the result.
- A command run never leaves anyone waiting with no sign of progress, headed or headless.
- Every feature of the command works headless.

## 14. The `song2vid` command

### 14.1 Where it lives

- Built from the same `Song2VidCore` package as the app. It calls the same frame, drop-check and export code; no logic is copied.
- Shipped inside the app at `Song2Vid.app/Contents/Helpers/song2vid` (not `Contents/MacOS`, where its name would clash with `Song2Vid` on a case-insensitive disk).
- Signed ad hoc **without** the app sandbox, so it can read files named on the command line (ADR-013). The app itself keeps the sandbox, and version 1.1.0 drops the `get-task-allow` entitlement.
- Install, for people and agents:

  ```
  mkdir -p ~/.local/bin
  ln -sf /Applications/Song2Vid.app/Contents/Helpers/song2vid ~/.local/bin/song2vid
  ```

  If `~/.local/bin` is not on `PATH`, the Agent Guide and docs page say how to add it for zsh.

### 14.2 Usage

```
song2vid check <audio> <image> [-j]
song2vid make  <audio> <image> [-o <file.mp4>] [-s <shape>] [-r <resolution>] [-c <h,v>] [-w] [-n] [-j] [-q]
song2vid -h | -v | -S | -R | -u
```

| Option | Short | Applies to | Meaning |
| --- | --- | --- | --- |
| `--help` | `-h` | all | Help for the command or subcommand it follows. |
| `--version` | `-v` | none | Prints `song2vid 1.1.0`. |
| `--skill` | `-S` | none | Prints the agent skill (`skills/song2vid/SKILL.md`, bundled in the app). |
| `--repo` | `-R` | none | Prints `https://github.com/devin-thomas/song2vid-app`. |
| `--update` | `-u` | none | Reports whether a newer release exists (14.7). |
| `--shape` | `-s` | make | `16:9` (default), `9:16`, `1:1`, `4:3`, `original`. |
| `--resolution` | `-r` | make | `480p`, `1080p` (default), `2160p`. A usage error with `original`. |
| `--crop` | `-c` | make | Crop position as two fractions, `h,v`, each 0 to 1. Default `0.5,0.5`. A usage error unless the shape is `1:1` or `4:3`. Values outside 0–1 are a usage error, not clamped. |
| `--out` | `-o` | make | Output file. Default: the audio file's name with `.mp4`, in the current folder. Must end in `.mp4`. |
| `--overwrite` | `-w` | make | Allows replacing an existing output (ADR-014). |
| `--dry-run` | `-n` | make | Checks everything and reports what would be made. Writes nothing. |
| `--json` | `-j` | check, make, `-u` | Machine-readable output (14.5). |
| `--quiet` | `-q` | make | No progress output. The result and errors still print. |

- Short options can't be combined into one cluster (`-wn` is a usage error), so each letter means one thing.
- An unknown option or command is a usage error: "Unknown option. Run 'song2vid --help'." The unknown text is **not** echoed. If one known option is within two edits, the message adds "Did you mean --overwrite?" (a known name, so nothing the person typed is echoed).
- `--help` text has: what the command does, usage, two or three examples, and the exit statuses table.

### 14.3 `check`

Reads both files and reports, without writing anything:

- Audio: file name (no folder), length, sample rate, channels.
- Image: file name, pixel size after its orientation tag.
- For every Frame Shape and Resolution: the output size, the placement (Fit with bars or Crop), and whether the image would be enlarged. For Original, one size, or "too small" if a side is under 16 px.

### 14.4 `make`

1. Validates everything first, before encoding: options, both input files (the section 7 rules), the image size for `original`, and the output (ends in `.mp4`, folder exists and is writable, file absent unless `--overwrite`). Any failure stops here with nothing written.
2. With `--dry-run`, it reports the planned output (name, size, placement, enlarged, song length) and exits 0.
3. Otherwise it exports with the Part 1 rules (section 6.3), writing to a temporary file in the output folder and moving it into place at the end, so a half-made video never appears under the final name.
4. `--overwrite` replaces an existing file only at that final step. Without it, if the file appeared during the run, the run fails with exit 4 and the new video is deleted.
5. **Ctrl-C** (SIGINT) or SIGTERM cancels: the temporary file is deleted, a "Cancelled." line goes to stderr (or a JSON error line with code `cancelled`), and the exit status is 130.
6. The person's audio and image files are never changed.

### 14.5 Output and progress (ADR-018, ADR-019)

**Streams.** Results go to stdout. Progress, messages and errors go to stderr, except under `--json`, where everything is a JSON line on stdout and stderr is empty.

**Headed** (stderr is a terminal, no `--json`, no `-q`):

- A one-line live display, redrawn at least 10 times a second: the stage, a bar, the percent, elapsed time and time left, for example `Encoding  ████████░░░░░░░░  52%  0:04 elapsed · about 0:04 left`.
- Stages: `Checking files`, `Preparing`, `Encoding`, `Finishing`. While the percent is not known yet (Checking files, Preparing), a spinner moves instead of the bar, so the display never looks stalled.
- Time left appears once encoding has run for one second; before that it says "estimating".
- On finish, the line is replaced by the result. Colour is used only when `NO_COLOR` is unset and `TERM` is not `dumb`.

**Headless, plain** (stderr is not a terminal, no `--json`): a plain line at each stage change and at least every 2 seconds, such as `Encoding 52% (0:04 elapsed, about 0:04 left)`. No control characters.

**Headless, `--json`:** JSON Lines on stdout. Every line has `"api_version": "1"` and a `"type"`.

```json
{"api_version":"1","type":"progress","stage":"encoding","percent":52.0,"elapsed_seconds":4.1,"remaining_seconds":3.8}
{"api_version":"1","type":"result","command":"make","output":{"name":"song.mp4","width":1920,"height":1080,"duration_seconds":144.0,"bytes":6153216},"placement":"fit","enlarged":false,"dry_run":false}
{"api_version":"1","type":"error","error":{"code":"output_exists","message":"The output file already exists. Use --overwrite to replace it."}}
```

- `stage` is `checking`, `preparing`, `encoding` or `finishing`. `percent` and `remaining_seconds` are `null` until known.
- A progress line is written at each stage change and at least every 0.5 seconds. The last line is always exactly one `result` or `error` line.
- `check --json` and `--update --json` write a single `result` or `error` line.
- Every key is from a fixed allowlist, documented on the docs page. Keys change only with a new `api_version`.
- **Quiet period and beat** (settled in S2V-013): `Checking files` is shown only if it lasts more than 0.15 seconds, so a run that fails at once (a missing file) shows only its error. Every later stage is shown the moment it begins. After that the latest state is written every 0.08 s in the live display, every 0.25 s with `--json`, and every 1 s in plain headless mode. A dry run and `check` show no progress.
- Progress goes through the command's own copies of stdout and stderr, so nothing macOS prints can mix into it. `--quiet` shows none in any mode; with `--json` it still prints the final result or error line.
- No output, in any mode, contains a folder path, an environment variable's value, or file contents. File names appear without their folder.

### 14.6 Exit statuses and error codes

| Status | Meaning | Error codes |
| --- | --- | --- |
| 0 | Success (including `--dry-run` and `check`). | — |
| 1 | An input file does not exist. | `audio_not_found`, `image_not_found` |
| 2 | Usage error. | `usage` |
| 3 | An input can't be read or isn't usable. | `audio_unreadable`, `image_unreadable`, `image_too_small` |
| 4 | The output can't be written. | `output_exists`, `output_not_writable`, `output_not_mp4`, `disk_full` |
| 5 | Making the video failed after it started, or the update check failed. | `export_failed`, `network` |
| 130 | Cancelled. | `cancelled` |

Human error messages are one line on stderr and use the Part 1 wording where it exists (section 7).

### 14.7 `--update`

- Reads the latest release from the GitHub API for `devin-thomas/song2vid-app`. Sends no data about the person.
- Prints either "Song2Vid 1.1.0 is up to date." or "Song2Vid 1.2.0 is available (you have 1.1.0). Download it from https://song2vid.pages.dev." With `--json`: `{"api_version":"1","type":"result","command":"update","current":"1.1.0","latest":"1.2.0","update_available":true,"download_page":"https://song2vid.pages.dev"}`.
- Downloads and replaces nothing (ADR-020). No network: exit 5, code `network`.

## 15. Agent skill and Agent Guide

- Source: `skills/song2vid/SKILL.md`, written with the `writing-for-agents` skill. It is also bundled in the app for `--skill`, and published unchanged as `song2vid.pages.dev/agent.md` (ADR-015), served as `text/markdown; charset=utf-8`.
- It tells an agent how to make a video for someone by either route, and to pick the one it can do:
  - **The app's window**, for agents that operate apps: the controls by their VoiceOver labels, in order, and the first-open step.
  - **The command**, for agents with a terminal: install, `check`, `make`, reading JSON Lines progress from a background run, exit statuses and error codes.
- Rules it gives the agent: ask the person before `--overwrite`; never change the person's input files; report the real result or error, never a guessed one; the first-open step (Open Anyway) is the person's to do.
- A copy in the repo and the published page must match; the release check compares them.

## 16. Download site additions

- **Agent Handoff** on the landing page (ADR-016, ADR-017), near the Download button and visible without scrolling at 320 × 667 and 390 × 844:
  - Agents: **ChatGPT, Claude, Grok Bot, Muse**, each with its authentic mark and its name. None may be dropped. Artwork: ChatGPT, Claude and Grok Bot from the owner's `agent-prompts` set; Muse from LobeHub Icons 1.104.0 (MIT). Credits and licence notices are published beside the artwork (`site/brands/credits.txt`).
  - Prompt (one resolved payload for preview, clipboard and any link): `Use Song2Vid to make a video from my song and image. Instructions: https://song2vid.pages.dev/agent.md`
  - An agent picker with a `Copy for {Agent}` button. "Copied" shows only after the clipboard write succeeds; on failure, a dialog shows the full text to copy by hand. Open-in links are offered only for agents whose prompt-link format is verified on the day, each with a copy fallback.
  - Built with the `agent-prompt` skill's interaction contract: keyboard use, light and dark, reduced motion.
- **Docs page** at `/docs`, for people using the command directly: install, every command and option with its short form, examples, the progress modes, the JSON keys, exit statuses and error codes, and the app's window route in brief. A check fails if any option in `--help` is missing from the page.
- The landing page links to `/docs`. It keeps its three steps.
- Section 3 changes: the site may use one small first-party script for the handoff (no framework, no third-party requests). The CSP allows `script-src 'self'` and nothing else new.

## 17. Release 1.1.0

- One zip on GitHub Releases, as in 1.0.0, containing the app with the command inside. Universal, ad hoc signed, with its SHA-256 in the release notes.
- The app keeps the sandbox and loses `get-task-allow`; this is checked with `codesign -d --entitlements`.
- The site deploy publishes `agent.md`, `/docs` and the handoff together with the release.

## 18. Testing (adds to section 11)

- **Seam 5, the command's public behavior:** inputs are arguments, environment and stdin/stdout terminal status; outputs are stdout, stderr, exit status and files written. Tests run the built `song2vid` binary as a separate process.
- **Automated, with generated media:** `--help`/`--version`/`--repo`/`--skill`; `check` text and JSON; `make` for each shape at 480p; `--dry-run` writes nothing; `--overwrite` refused and allowed; every exit status in 14.6 except `disk_full` and `network`; unknown option not echoed; JSON Lines (every line parses, progress at least every 0.5 s, exactly one final line); plain headless lines; SIGINT gives 130 and leaves no file; a planted fake secret in the environment and the test folder path appear in no output.
- **Headed progress** is checked by running in a pseudo-terminal and by eye on this Mac (spinner moves during Preparing; bar, percent, elapsed and time left during Encoding).
- **Owner's sample media** (ADR-012): the coordinator makes one video per Frame Shape with the command, from files in the owner's sample folder passed by path argument, outside the repo. ffprobe checks size, length and both tracks.
- **Release check:** download the 1.1.0 zip anonymously, unzip into a clean folder, approve with Open Anyway, link the command, and repeat `--version`, `check` and one `make` from a folder outside the repo.
- **Phase 3 proof:** a new Claude Code session that has never seen this repo runs the installed command: one `check --json`, one `make --json` to a 480p 1:1 video, and one `make` with a missing image. It reports the real values and the failing run's exit status (1) and error code (`image_not_found`). The owner confirms.

## 19. Definition of done (1.1)

- Tickets S2V-010 to S2V-018 meet their acceptance criteria and the tests pass.
- 1.1.0 is on GitHub Releases, and `song2vid.pages.dev` serves the handoff, `/docs` and `agent.md`.
- The Phase 3 proof passes and the owner confirms it.
- The repo history shows only the owner as author, and the public-repo checks pass.

# Part 3 - Agent-ready download site

## 20. Agent-ready download site (ADR-021)

Goal: an agent that has only `https://song2vid.pages.dev` can find the public pages, answer from them with a link, and say so when the site does not publish something. This is the Starter Pack Level 1 readiness milestone (`agent-ready-website`). It changes only `site/`. There is no new app release.

**Public pages.** `/` (the home page), `/docs/` (the docs page) and `/agent.md` (the Agent Guide). Each page has one address. `/docs` redirects permanently to `/docs/`, and every link uses `/docs/`.

**Three facts a visitor may ask an agent, and where each lives in the HTML the server sends (no script needed):**
1. What Song2Vid is, and that it is free: `/`.
2. That it needs macOS 14 or later, and the current version (1.1.0): `/`. The version shown must equal `song2vid --version`.
3. How to make a video with the command, and the exit status and error code when it fails: `/docs/` and `/agent.md`.

**What must stay out of every page and file:** plans for later versions, anything not yet released, the owner's sample files and their names, tokens, emails, IP addresses and local paths. The site has no drafts and no private records, and a check keeps it that way (see the allowlist below).

**Each HTML page** has a canonical link to its own address, a `<link rel="alternate" type="text/markdown">` to its Markdown copy, and a visible "Updated" date in a `<time datetime>` element.

**Generated files (one script, `scripts/build-site.py`, from the two HTML pages and the skill):**
- `index.md` and `docs.md`: Markdown copies of the pages. Parts of a page that only work in a browser (the picker, the Copy button, the manual-copy dialog) are marked `data-md="skip"` and left out; the prompt text stays. Each copy ends with the page's canonical address and updated date.
- `llms.txt`: what Song2Vid is in one sentence, then the live public pages, each with a short description taken from the page's own `<meta name="description">`.
- `sitemap.xml`: the two HTML pages at their canonical addresses, `lastmod` equal to the page's updated date.
- `agent.md`: unchanged (a copy of the skill, ADR-015); `scripts/build-agent-md.sh` stays.
- `robots.txt` is written by hand: it allows everything and points to the sitemap.

**Allowlist.** `scripts/build-site.py` holds the list of files that may be published. `scripts/check-site.sh` fails if `site/` holds a file that is not on the list, or if a listed file is missing.

**Served as.** HTML pages `text/html`; `index.md`, `docs.md`, `agent.md`, `llms.txt` and `robots.txt` as text (`text/markdown; charset=utf-8` for the Markdown ones, `text/plain; charset=utf-8` for the other two); `sitemap.xml` as XML. Set in `site/_headers`.

**Checks (added to `scripts/check-site.sh`, so `scripts/check.sh` runs them):**
- Regenerating every generated file gives exactly the committed file.
- Each HTML page: one canonical link equal to its own address; the Markdown alternate exists; the updated date equals the sitemap `lastmod`; the visible version equals `song2vid --version`.
- Every address in `sitemap.xml` and `llms.txt` is a file in `site/`; each live page appears once in the sitemap; `robots.txt` names the sitemap and blocks nothing.
- Every internal link in the HTML pages points to a file or folder in `site/`; no link uses `/docs` without the trailing slash.
- Each of the three facts is present in the HTML source as text.
- The allowlist holds.
- Each check is shown to fail on a deliberately broken copy (`SITE_DIR`).

**Outside checks (after the deploy), with `curl` against `song2vid.pages.dev`:** `/` and `/docs/` return 200, `text/html`, with their own canonical link; `/docs` redirects permanently (308) to `/docs/`; `/llms.txt`, `/sitemap.xml`, `/robots.txt`, `/index.md`, `/docs.md`, `/agent.md` return 200 with the types above; the three facts are in the served HTML; a made-up address (for example `/roadmap`) is not a 200 page of unpublished content; no response contains a local path, email or the sample files' names.

**Proof with a separate agent.** A new Claude Code session that has not seen this repo gets only the site's address and two questions. (1) "Using only https://song2vid.pages.dev, what version of Song2Vid is current and what macOS does it need? Give the address of the page you used." It must answer 1.1.0 and macOS 14 or later, and cite `/`. (2) "What changes are planned for the next version of Song2Vid?" It must say the site does not publish that, without guessing. The coordinator opens the cited page and confirms the fact is there. On a pass, the `agent-ready-website` step gets its `verification` object in the private progress file.

## 21. Definition of done (agent-ready site)

- Tickets S2V-019 to S2V-021 meet their acceptance criteria and `scripts/check.sh` passes.
- `song2vid.pages.dev` serves everything in section 20 and the outside checks pass against the live site.
- The separate-agent proof passes and the owner confirms it.
- The `agent-ready-website` verification is saved in the private progress file.

