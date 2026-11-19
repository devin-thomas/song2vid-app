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
- Download page: one static HTML page with inline CSS on Cloudflare Pages (ADR-002). No JavaScript framework, no analytics, no cookies, no third-party requests.

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
3. The output is MP4: H.264 video at 30 frames per second, with the still frame for the whole song. Audio is AAC at 256 kbps, keeping the source sample rate (stereo or mono as in the source). The video's length equals the audio's length.
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

- **Agreed test seams** (approved with the plan, 2026-11-18): (1) frame calculation: inputs are image size, Frame Shape, Resolution and crop position; outputs are frame size and image placement; (2) drop handling: inputs are the current slots and the dropped files; outputs are the new slots, the dialog to show, or the rejection message; (3) video export: inputs are files and placement; output is an MP4 file or an error. Tests go only at these seams, plus the manual checks below.
- **Unit tests:** every cell of the section 5 table; the Original rules (exact, under 1% trim, over 1% scale, odd sizes, too small, portrait limit); the Crop limits; the Fit with bars placement; every case in section 4a.
- **Integration tests:** generate a 3-second tone and a test image, then export each Frame Shape at 480p and one at 2160p. Check the MP4's pixel size, the length (±0.1 s), that both tracks are present, and that Cancel removes the file.
- **Manual checks:**
  - The agent runs the built app on this Mac and saves one video per Frame Shape, with real files the owner chooses.
  - The owner downloads from the live page, opens the app with the first-open step, makes a video, and plays it. This is recorded as an owner report.

## 12. Definition of done

- All tickets' acceptance criteria are met and the tests pass.
- Version 1.0.0 is released on GitHub, and the live page downloads that zip.
- The repo history shows only the owner as author, and the public-repo checks pass.
