# Song2Vid design critique (round 1, as the critic wrote it)

Process step 3 of SPEC 28, run in S2V-031 on the pictures of S2V-030 (`windows/app/qa/baselines`, taken by `qa:shots`). The critic saw only the pictures. Its text follows unchanged; the last section, "What was done", is the builder's, written after the fixes.

Reviewed from screenshots only: all 46 in `560x760@1x-dark/`, a sample of `480x640@1x-dark/`, `560x760@1x-light/` and `zoom-200/`.

Overall: the bones are good. The app is calm and compact, and most copy is plain. The shell is quiet and correctly dark, with a good command palette and a sensible toolbar. Several things stop it feeling premium: it reads as a settings form, nothing separates an error from a status line, the progress and done states are weak, there is no accent colour, text and buttons get cut off at the minimum window and at 200% zoom, and the light theme appears not to exist in the captures.

## Must fix

1. **The light theme was never captured, or does not work.**
   - Files: everything in `560x760@1x-light/` (checked 01, 04, 17, 22, 40, 42) and `zoom-200/*-light.png` (04). All are pixel-identical to the dark set, and the palette still offers "Use the light theme".
   - Either the theme switch did nothing or the capture never switched. Light must be verified with real screenshots before anyone calls it done.

2. **200% zoom is broken: whole sections vanish and text is clipped.**
   - Files: `zoom-200/01-empty-dark`, `04-both-dark`, `17-making-dark`, `22-done-dark`, `32-error-output-exists-dark`.
   - The Resolution row, the Codec row and the entire preview are gone. Nothing indicates they are scrollable.
   - "Original" drops onto a second line inside the segmented control.
   - File names shrink to "Song.m…" and "C…".
   - Footer buttons are cut off: "ave As.", "ance", "ow in File Explore".
   - The footer text is truncated: "Saved Song.mp4 t…", "Using the NVIDIA enc…".
   - Fix:
     - Let the middle region scroll, with a visible scrollbar.
     - Stack the footer: the message gets the full width and the button sits on its own row below it.
     - Give buttons `white-space: nowrap` and a min-width so labels are never cut.
     - Keep the preview.
     - Let the Frame Shape control become a 3+2 grid or scroll instead of orphaning "Original".

3. **Error and status text is truncated at the minimum window, and it is the text the user most needs.**
   - Files: `480x640@1x-dark/32-error-output-exists` ("…while the video was bein…"), `17-making` ("…about 10 seco…").
   - The footer message must wrap to as many lines as it needs. It must never ellipsise. Let the footer grow, or put the button under the text at narrow widths.

4. **Errors look exactly like normal status.**
   - Files: `23`, `24`, `25`, `26`, `27`, `29`–`35` (the error footers).
   - A failed save and "Ready to make your video." share the same white 14px text and the same position. There is no icon, no colour and no change of container. The only difference is a light-filled button appearing at the right.
   - A user glancing at the window will not register that something failed.
   - Fix:
     - Give the footer a distinct error treatment, for example a 16px warning glyph and a tinted strip with a 2px left edge in a muted red or amber.
     - Make the first line semibold.
     - Keep the second line (the "work is safe" line) in a secondary colour.
     - Use the same pattern in every error.

5. **The wrong controls stay live after an error, or contradict the message.**
   - `23-error-audio-not-found` / `24-error-image-not-found` / `25` / `26`: the message says the file is gone or unreadable, yet the Audio or Image row still shows "Song.mp3 2:24" or "Cover.png 1600×900". The preview still shows the image. "Make Video" is still enabled, so the next click fails the same way. The row should show the problem state (the name struck through or in the warning colour with "Can't find it"), and Make Video should be disabled until fixed.
   - `16-preview-failed`: the preview says "Song2Vid can't read this image file", but the status says "Ready to make your video.", Make Video is enabled, and the "smaller than 1920×1080" note is still showing. Four elements disagree. Disable Make Video, hide the note, put the failure in the footer with a "Choose Image…" button, and show the row as failed.
   - `13-original-too-small`: "Ready to make your video." sits under a disabled Make Video and an image-too-small message. The status should say what is blocking.
   - `38-tool-missing` / `39-tool-turns-missing`: the footer says "Choose a song and an image to begin." or "Ready to make your video." on a screen that can make nothing. Replace the footer with the blocking message, or hide it.

6. **A filled "Copy Details" button is the primary action on the repeated error.**
   - File: `35-error-repeated`.
   - It is a filled primary button, labelled "Details", and it does not fix anything. It is also the button that takes focus. It needs to be secondary (outline), with a real fix as primary. Offer "Choose Another Folder…" or "Save As…" beside it.
   - The same applies to `38`/`39` "Copy Details" (outlined, which is acceptable there). In `35` keep Copy Details as a quiet text button, and make the primary "Save As…".

7. **The done state is too weak, and it uses jargon.**
   - Files: `22-done`, `480x640@1x-dark/22-done`.
   - "Saved Song.mp4 to Videos." does not say where. "Videos" could be any of several folders. It should show the real folder name, or the shortened path ("Videos › Song2Vid"), at least in a tooltip.
   - The second line, "H.264 · NVIDIA encoder · 2:24", leaks an implementation term (NVIDIA encoder). Change it to "H.264 · 1080p · 2:24" or to the file size.
   - There is no success mark. The same white text, grey footer and unchanged main area mean idle and done look the same at a glance.
   - Fix: a check glyph, a bolder first line, and a "Show in File Explorer" button as the primary action in this state. Consider a secondary "Play" action.

8. **Making state: the progress is a toy.**
   - Files: `17-making`, `18-making-early`, `19-making-stalled`, `20-cancelling`.
   - The bar is about 96px wide, squeezed between the text and Cancel, with the percentage repeated in the text. For the most important state in the app, the progress should span the footer or sit directly above "Make Video". Better still, "Make Video" itself becomes the progress surface.
   - "Using the NVIDIA encoder" is a hardware or library name. Say "Making the video · about 10 seconds left".
   - In `18-making-early` "Getting ready" is not vertically centred on the Cancel button. It sits about 10px higher because the second line is missing. The footer reflows between one and two lines, so the text jumps.
   - `20-cancelling`: the bar empties, and then the state flips to `21-cancelled`. Keep the last value, or show a pulse while cancelling.

9. **No accent colour, so the primary action is a pale grey slab.**
   - Files: all, especially `04-both`, `21`, `22`.
   - Enabled "Make Video" is a light grey fill that reads like a disabled or secondary control. The disabled version is dark grey, so the contrast between ready and not ready is unclear.
   - The same pale slab is used for every footer action, which makes five different primaries look identical.
   - The only colour in the whole UI is the blue focus ring and the progress bar.
   - Fix: pick one accent (Windows-blue or the product accent) and use it for the single primary action per state. "Make Video" should be an obvious accent button when ready, and disabled should be clearly a ghost.

10. **Heavy focus rings are visible on mouse-less default states and look like errors.**
    - Files: `01-empty`, `02-audio-only`, `03-image-only`, `04-both`, `21-cancelled` (Make Video), `22-done` (Show in File Explorer), all error states.
    - A blue ring around "Choose Audio…" appears on first paint of the empty state. It makes the first screen look like a form with a validation highlight.
    - The row label also brightens when its button is focused (e.g. "Audio" and "Image" turn white), and "Frame Shape" turns white in 06, 08 and 09. This is inconsistent, because Resolution and Codec labels never do it.
    - Fix: use `:focus-visible` only (keyboard), do not move focus programmatically after clicks or on launch, and drop the label brightening.

11. **The drop-refused state shows no refusal.**
    - File: `45-drop-refused`.
    - The footer reads "Drop one song, one image, or one of each." It looks like the normal idle hint. It does not say what was rejected or why.
    - Fix: "That file isn't a song or an image Song2Vid can use." Use the same error treatment as item 4, and name the file where it is short.

## Should fix

12. **It still looks like a web form.**
    - Files: `01`, `04`.
    - A table of grey labels on the left, boxed buttons in a second column, and hairline separators between four rows. The first two rows (Audio, Image) are file pickers, the next three are options, and all five have identical weight. A premium app would give the song and the image the main stage: a large drop target holding the cover, with the song as a one-line player-style row.
    - At minimum, group them: pickers on top, then the three options as a compact 3-up, with the preview getting more height.
    - `01-empty`: the empty state is a large dark rectangle saying "Choose an image". It should be the drop target and say so ("Drop a song and an image here, or choose them"). The drop hint only appears while dragging (`44`).

13. **Layout jumps between states.**
    - `05`/`06`/`08` (preview region 293–590) vs `01`/`04`/`09` (301–583): the preview moves about 8px depending on the shape.
    - `11-hevc-disabled`: the HEVC note pushes the preview down by about 16px and shrinks it.
    - `03`/`04` vs `01`: the Reset to Center row grows a two-line note.
    - Reserve fixed space for the notes and keep the preview rectangle in the same place. The Frame Shape change to "Original" (`09`) replaces the Resolution segmented control with the text "Output: 1600×900"; keep a control-sized slot.

14. **The preview in 9:16 is unreadable.**
    - File: `05-shape-9x16`.
    - A tall black frame with a thin strip of the image in the middle, about 170px wide. The image is letterboxed and there is no indication whether that is the crop or the result. For 9:16 consider cropping by default, with drag-to-reposition as in 1:1.
    - If it is letterboxing, say so ("Black bars will be added at the top and bottom") and let the person choose between filling and fitting.

15. **Crop has no affordance.**
    - Files: `06`, `07`, `08`.
    - Nothing says the image can be dragged. The cursor is the only cue. There is no dimmed overlay showing what will be cut off, so the person cannot tell what is lost. Add a small "Drag to reposition" hint (visible on first use), show the cropped-out part dimmed, and use a grab cursor.
    - In 07 the focused preview gets a thick blue ring that looks like a selection error.

16. **Image notes are pushed to the side and crowd the Reset button.**
    - Files: `03`, `04`, `06`, `12`.
    - "This image is smaller than 1920×1080 and will be enlarged, so it may look soft." wraps to two lines beside "Reset to Center" and stays at the 12px grey size. It is shown on every state, including all errors, where it is noise. Shorten to "Smaller than 1920×1080, so it may look soft." Put it as a single line under the preview, aligned with the left edge. Hide it in error states.
    - "Reset to Center" is a disabled-looking low-contrast button (`01`, `09`, `14`) that appears even when there is nothing to reset. Hide it, or show it only when the crop has moved.
    - "Reset to Center" (button) vs "Reset Crop to Center" (palette): pick one wording.

17. **File names truncate in the middle of a word and lose the extension.**
    - File: `14-long-names`.
    - "A very long photograph na…" with the dimensions pushed to the far right edge, which is inconsistent with the other rows, where the dimensions sit next to the name. Use middle ellipsis ("A very long photo…ame.jpg") so the extension stays, give it a tooltip with the full name, and keep the dimensions next to it.

18. **Status bar and hierarchy.**
    - Files: all.
    - The footer sits on a separate band below the card. "Ready to make your video." at 14px and the second-line grey at 13px are not clearly different. Make the first line one weight up and the second smaller and dimmer. Keep the footer height constant so the card does not shift between one-line and two-line messages (`17` vs `22`).

19. **Wording that needs work.**
    - `33`/`34`: "The video couldn't be made. Your files are unchanged." gives no reason and the identical text appears for an unknown error. A person cannot decide what to do. If the reason is unknown, say so and offer something different: "Try a lower resolution" or "Choose another folder". Do not show identical messages for different codes.
    - `29`: "Couldn't save to that folder." Add why in plain words: "You may not have permission to save there."
    - `30`: "Not enough disk space." Say how much is needed, and which drive.
    - `31`: "Another app is using that file." Which file? Name it. "Close it, then try again" is good.
    - `32`: "A file with that name appeared while the video was being made. It was kept, and the new video wasn't saved." This explains the implementation race and implies the finished video was thrown away. Better: "A file named Song.mp4 was added to that folder while the video was being made. Your existing file is untouched." If the video really was made, offer to save it under a new name. The primary "Save As…" is correct.
    - `28`: "This computer can't make HEVC videos." followed by a button "Use H.264". Good, but add that nothing was lost.
    - `13`: "Output: not available" tells the user nothing. Say "Image too small" in that row.
    - `38`/`39`: "Song2Vid is missing part of itself." is cutesy and vague. Say "Song2Vid can't make videos because a component it needs is missing. Reinstall to fix this." The two states have different footers for the same screen. The body is a huge empty card with no icon.
    - `22`: avoid "encoder".
    - `42` About: "Licence" (British) next to "MIT License" (American). "Repository" is developer jargon. "Third-party notices" appears twice (label plus the first line of the text box). The box mentions "FFmpeg", "LGPL", "the one configure line this copy was built with", which is internal. Keep the legal text but start it with a plain line ("Song2Vid uses open-source software. Details below.").
    - The version row repeats the app name ("Version / Song2Vid 1.2.0"). Show "1.2.0".

20. **About dialog craft.**
    - File: `42-about`.
    - The GitHub link has a hard rectangular focus ring that touches the "Repository" label. There is no app icon. The monospace box is cut at the bottom with no scroll indicator or fade, so the user cannot tell it scrolls.
    - The Close button is neutral, which is fine, but the dialog is more of a document than a product About. Add the app icon, the name and the version as a header.
    - At 200% (`zoom-200/42-about-dark`) the title is scrolled out of view and the link wraps inside a box.

21. **Replace dialog.**
    - File: `43-replace-question`.
    - Four lines of "Song now: …, Dropped song: …" are hard to scan. Use two columns ("Now" and "New") or a two-row list with icons. "Keep Current" is the default and filled, "Replace" outline, which is right. The labels should be sentence case: "Keep current". Windows dialogs use verbs: "Replace" / "Keep current".

22. **Command palette.**
    - Files: `40`, `41`.
    - Good overall, but: it is nearly the full window width and its top edge sits very close to the toolbar; the dim behind it is weak; disabled commands (Cancel, Show in File Explorer, Copy Details, Reset Crop) are mixed in with enabled ones and could be hidden or moved to the bottom; "Esc" appears both on the input and on "Cancel", which is confusing (Esc closes the palette, but the row suggests it cancels the render). There is no way to change shape, resolution or codec from here, which is the obvious thing to type ("1080p", "HEVC").
    - The group labels ("File", "View", "App") are sentence case and fine, not eyebrows, but "App" holds one item.

23. **Toolbar.**
    - The "Commands Ctrl+K" pill is a fine pattern, but the sun icon next to it has no label and no tooltip in the screenshots. Add a tooltip and an `aria-label`.
    - The app icon next to "Song2Vid" is a play button in a black rounded square, which suggests a video player, not a song-plus-image maker.

24. **Segmented controls.**
    - The selected state is only a slightly lighter fill, about 1.4:1 against the track in the dark theme (`01`, `04`). It is hard to see which of 480p / 1080p / 2160p is selected in a quick glance. Raise the contrast, or add a 1px inner border.
    - There is no hint of what each option costs (file size, time). "2160p" for a 1600×900 image should be flagged.
    - "Frame Shape" would be better as "Shape" or "Aspect ratio", but that is minor.

25. **`46-window-inactive`.**
    - The focus ring stays at full strength on "Choose Image…" in an inactive window. Dim or remove it when the window loses focus.

## Fine

- Dark theme palette and surface layering are calm and consistent; the card, the footer band and the toolbar relate well.
- Font choice (a clean grotesque) and sizes are readable at 560×760; row heights and left alignment of labels are consistent (`01`, `04`).
- Titlebar is clean, with the empty right side reserved for the Windows caption buttons.
- Primary flow is short and clear: pick audio, pick image, make video, with plain wording on the buttons (`04`).
- "Cancelled. Nothing was saved." (`21`) is the model for an error line: what happened and whether work is safe.
- "The video couldn't be made. Your files are unchanged." (`33`) states safety (although it needs a reason, see item 19).
- Fix buttons in the error footers are the right idea: "Use H.264" (`28`), "Choose Another Folder…" (`29`, `30`), "Save As…" (`32`), "Choose Audio…" / "Choose Image…" (`23`–`26`), "Try Again" (`31`, `33`).
- Command palette contents, shortcuts as keycaps, and the empty-search message with suggestions (`41`) are good.
- The drop highlight (`44`) is clear and sets expectations ("Drop a song or an image").
- Replace dialog correctly defaults to the safe choice (`43`).
- No slogan headings and no uppercase eyebrow labels were found anywhere in the screenshots.
- 480×640 layout of the normal states (`04`, `06`, `22`) holds together, and the "Make Video" hint drops cleanly. The problems there are the truncations in item 3.

## What was done (S2V-031)

Every pass or fail below is by the gates in `windows/app/qa/audit.ts`, run on the S2V-030 build and on the fixed one, and by looking at the new pictures (dark, light, 480x640, 200% zoom). The decisions are D-028 in `windows/app/docs/DECISIONS.md`.

### Must fix

| # | Finding | Result |
| --- | --- | --- |
| 1 | The light theme was never captured | Cause: the page takes its theme from the saved choice (D-020), and the capture set only the browser's colour scheme, so every "light" picture and audit run was dark. Fixed in `qa/lib.ts`; `load` throws when a page shows another theme than it was opened for; `qa/shots.ts` fails when a light picture equals its dark one (36 light pictures checked); the audit has a `theme` gate. The light theme was then audited for real and its contrast findings fixed |
| 2 | 200% zoom hides rows and clips text | The work area scrolls and a "More below" strip says so; Frame Shape reflows to 3 + 2; names and facts take their own line; the status bar's button takes its own line; the blocked state scrolls. New gates `reach`, `truncated`, and a `clipped` that no longer accepts a mask as a cue. On the S2V-030 build they report 47 scroll areas with no cue, 170 cut labels or sentences, and buttons whose label is wider than the button ("Cancel" 49 > 32, "Show in File Explorer" 130 > 107); on the fixed build, none |
| 3 | Error and status text is cut at the minimum window | Sentences wrap; the status bar is as tall as its longest message at its width, in every state (the `stable` gate holds at all four sizes) |
| 4 | Errors look like status | A tone, a mark, a tint, a 3px edge and a semibold first line for failures (danger) and refusals (warning); a success mark for a saved video. `distinct` gate: 84 failures on the S2V-030 build, none now |
| 5 | Controls contradict messages | A slot whose file the tool could not find or read, or whose preview failed, is marked in its row, in the preview and in the bar; Make Video waits; the enlarge note goes; a missing tool leaves the bar empty; an image too small is said in the bar. `messages` gate: 24 failures on the S2V-030 build, none now |
| 6 | Filled Copy Details on a repeat | Rejected: SPEC 27.5 and premium rules 50 and 69 require it |
| 7 | Done is weak | The folder's own name was already said (the picture's fixture used "Videos"); a success mark, tone and weight added; Show in File Explorer stays filled. Rejected part: the encoder line stays (SPEC 27.4) |
| 8 | Progress is a toy | A bar across the top edge of the status bar, the full width, the percent said once; one bar height in every state; the encoder's name stays (rejected part) |
| 9 | No accent colour | The token `accent` fills Make Video and each state's button; disabled is an outline. Contrast computed in both themes (`tokens` gate): 4.98:1 light, 8.12:1 dark for the text on the fill |
| 10 | Focus rings on first paint and after a mouse click | Ring for keyboard modality only, none in an inactive window; the row label no longer brightens. `ring` gate: 10 failures on the S2V-030 build, none now |
| 11 | Drop refused shows no refusal | Two lines in the warning tone: what was refused (naming the file when one was dropped) and what to do instead |

### Should fix

Done: 13 (the enlarge note's room is reserved and the preview does not move when it appears; "Output: image too small" replaces "not available"), 16 (the note is whole and on its own line, never cut), 17 (names are cut in the middle, the extension stays, the facts sit next to the name), 18 (first line one weight up, second smaller and dimmer, constant height), 19 in part (About: one spelling "License", the version row shows the number once; the notes below), 24 (the chosen item has a line as well as a fill), 25 (no ring in an inactive window), 22 in part (the palette's list has the "More below" cue).

Left, with the reason:

- 12 (a different layout with a large drop target): a redesign of SPEC 27.2's order, which the SPEC fixes; the empty preview already says "Choose an image".
- 14 (9:16 fit with bars): SPEC section 4 says fit with bars for 16:9 and 9:16.
- 15 (a crop hint and a dimmed cut-off): the grab cursor and the slider are in place; a hint is a new element of SPEC 27.2; the owner's use decides.
- 16 (hide Reset to Center when there is nothing to reset; one wording): SPEC 27.2 names the button, and hiding it moves focus; the two wordings are SPEC 27.2 ("Reset to Center") and 27.7 ("Reset Crop to Center").
- 19 (wording of the errors, "Licence" is now "License"): the table's sentences are SPEC 27.5 and the banned-terms gate covers them; the reasons the critic asks for are the tool's text, which only Copy Details carries.
- 20 (About: icon header, notices fade), 21 (Replace dialog in two columns; sentence case): "Keep Current" and "Replace" are SPEC 4a's words; the rest is polish for the owner's use.
- 22 (palette commands for shape, resolution, codec; hide disabled commands): SPEC 27.7 lists the commands.
- 23 (title bar icon): the icon is the repository's `design/icon.svg`.
- 24 (cost hints on 2160p): a new element.
