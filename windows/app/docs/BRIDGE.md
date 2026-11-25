# The bridge between the page and the shell

`src/bridge.ts` is the whole interface. The page (`src/`) is built against it and against the stand-in in `src/bridge.fake.ts`; the shell (`electron/preload.ts` and `electron/main.ts`) implements it. Neither side changes it alone: a change is a lead decision recorded in `docs/DECISIONS.md`. The tool's contract is not repeated here: it is SPEC sections 14 and 24 (`docs/TOOL-CONTRACT.md` points at it: ADR-024 makes the existing command contract the one contract).

The page holds opaque ids and never a path. That is SPEC 27.2 and the starter's bridge rule.

## Who owns what

| Thing | Owner | Notes |
| --- | --- | --- |
| Which files are loaded | The page holds the ids; the shell holds the id-to-path map | An id is made only from the open dialog, a dropped file or a file opened with the app (SPEC 27.2). An id for a file the person never gave the app does not exist |
| File paths | The shell | A dropped file's location is resolved in the preload with `webUtils.getPathForFile` and goes straight to the main process. No path, no folder and no environment value reaches the page, in a result, an error or a log |
| The save destination | The shell | The Windows save dialog opens inside `makeVideo`. The default name is the audio file's name with `.mp4`; the default folder is the last folder saved to, else the Videos folder. Both stay in the shell. The page learns only the saved file's name and the folder's own name (`MakeDone.where`) |
| `--overwrite` | The shell | Passed only when the person confirmed a replacement in the Windows save dialog (premium bar rule 63). The page cannot ask for it |
| The theme | The page chooses, the shell keeps | `setTheme` tells the shell, which saves it, paints the window in it at the next start and names it in the page's address (`index.html#theme=dark`). Dark until the person changes it |
| The Codec | The page chooses, the shell keeps | `setPreferences({ codec })`. `bootstrap().preferences.codec` is what was remembered, even when this computer cannot make it |
| Last save folder, window size and position | The shell | Never sent to the page |
| The system | The shell | `bootstrap().platform`; the page sets `data-platform` on the root and never reads the user agent |
| Running the tool | The shell | `electron/tool/` runs `song2vid.exe` with `--json` and, for `make` and `preview`, `--cancel-on-eof` (SPEC 27.6). One job at a time. A second `makeVideo` while one runs, or while its save dialog is open, resolves `{ status: 'busy' }`. The tool's own files are the shell's: `service.ts` holds the logic and is tested with the stand-in tool, `index.ts` gives it the Windows dialogs and the channels |
| Dialogs under `--no-activate` | The shell | A launch that asked for no focus opens no dialog (D-010): `chooseAudio`, `chooseImage` and `makeVideo` answer `dismissed`, as if the person had closed it. A development launch (never a packaged one) can answer them with `--qa-pick-audio=`, `--qa-pick-image=` and `--qa-pick-save=` (D-026) |
| Which Encoder | The tool | The page reports the Encoder the tool names and never chooses one (ADR-025). It turns `nvenc`, `media_foundation`, `software` and `apple` into the human names "NVIDIA encoder", "graphics hardware encoder", "software encoder" and "Apple encoder" |
| Words | The page | The shell sends codes and numbers. `Problem.details` and `ToolStatus.details` are developer text: the page only ever copies them (Copy Details) and never shows them. The sentence for each tool code is SPEC 27.5's table |
| Closing during a job | The shell | The shell asks, with its own system dialog, "Stop making the video?" and the buttons Keep Making (default and Esc) and Stop and Close, before it closes the window or quits (the starter's `confirmQuitDuringJob`, reworded). The page is not asked and has no call for it |
| The second-launch hand-off | The shell | `onFilesOpened` delivers a file opened with the app, judged as a drop is |

## The calls

| Call | What it does | Result |
| --- | --- | --- |
| `bootstrap()` | Everything the page needs before first paint | Saved state, the system, the remembered Codec, the app version, the tool's status and the cached Encoder report (`null` when none) |
| `setTheme`, `saveState` | As in the starter | Nothing |
| `setPreferences({ codec })` | Remember the Codec chosen | Nothing. Validated by the shell |
| `chooseAudio()`, `chooseImage()` | The Windows open dialog, filtered to the section 7 types, then one-file `song2vid check <file> --json` (SPEC 24.8) | `chosen` with an `AudioInfo` (id, file name, length) or an `ImageInfo` (id, file name, pixel size, and the section 14.3 table of output sizes with placement and "enlarged"); `dismissed` when the person closed the dialog; `unusable` with the tool's code. Nothing changes unless `chosen`: a choice replaces the current file (SPEC 4) and the page then calls `releaseFiles` for the old id |
| `dropFiles(files)` | Judge a drop (SPEC 4a): by type first, in the Mac app's order (a folder, more than two files, a type Song2Vid can't read, two songs or two images), then each file with one-file `check` | `ok` with the audio and image the drop holds (either may be `null`), each already checked, or `rejected` with a reason: `more-audio`, `more-images`, `too-many`, `folder`, `unsupported`, `unreadable`. A drop is judged as a whole: when one file fails the check the reason is `unreadable`, the other file's id is released at once and nothing is held (the Mac app applies the good file and names the bad one; this bridge has no way to say which) The shell changes nothing and the page decides: an empty slot is filled, a filled slot gets the page's Replace dialog, and an id the person did not keep goes to `releaseFiles`. While a video is being made the page refuses a drop itself, with "Wait for the current video to finish." for 3 seconds in the status bar, and does not call it |
| `onFilesOpened(listener)` | The same judgement for a file opened with the app | The same `DropResult` |
| `releaseFiles(ids)` | Free ids the page will not use | Nothing |
| `previewImage(imageId)` | `song2vid preview` (SPEC 24.3): the image as the video will see it, any supported type | `ready` with an `src` and its pixel size, or `failed` with a problem. `src` is a `data:image/png;base64,` address (the page's policy allows `img-src data:`); the picture file is removed as soon as it is read. Releasing the image stops a preview still being made (`failed`, code `cancelled`) |
| `onEncoders(listener)` | A fresh `encoders` answer after the launch refresh (SPEC 27.6) | One `EncoderReport` per refresh |
| `onToolStatus(listener)` | The tool's status changed after `bootstrap()`: a tool the cached answer called ready failed this launch's version check (S2V-030, D-026) | One `ToolStatus` (`damaged`). The page then shows the one blocking state |
| `makeVideo(request)` | Open the save dialog (`destination: 'ask'`), or reuse the last destination (`'same'`, for Try Again), then start the job | `started` with a job id as soon as it is recorded; `dismissed` when the person closed the save dialog; `busy` |
| `cancelJob(jobId)` | Close the tool's stdin (SPEC 24.4), then kill it after 3 s; a tool that had to be killed may have left its `.song2vid-<32 hex>.tmp`, and the shell removes the one that is new in the output folder | Nothing. The job ends with a `cancelled` update. The page shows "Cancelling" on the next frame without waiting |
| `onJob(listener)` | The job's updates, one at a time, in order | `running` (stage, percent or `null`, elapsed seconds, remaining seconds or `null`, the Encoder from the encoding stage, `stalled` after 30 s with no line), then exactly one of `done`, `cancelled`, `failed`. The first `running` update comes at once, at stage `checking` with no percent. The percent never goes back and stays under 100 until `done`. The shell withholds the remaining seconds (`null`) until encoding has run 1 second and passed 5%, and gives the tool's number, changing at most once a second and never up by more than a second at a time; the page applies the same rule again |
| `showInFolder(outputId)` | Open File Explorer on the saved file, selected | Nothing |
| `openLink(which)` | Open the repository, or the download page, in the person's browser. The addresses are the shell's own | Nothing |
| `notices()` | The text of `THIRD-PARTY-NOTICES.txt` for About (SPEC 27.8) | The text |
| `onMenuCommand`, `setMenuState` | As in the starter. The ids are the keys of `shortcuts.json` | Nothing |

## Rules for the page

- **Text.** The six sentences of SPEC 27.5 and every other word are the page's. `qa/banned-terms.json` lists words a person never sees.
- **Repeated failure.** A failure with the same inputs twice in a row says "It failed again." and the filled button becomes Copy Details (premium bar rule 69). The page counts the repeat.
- **Filled buttons.** Each code's filled button that can succeed is in SPEC 27.5. "Choose Another Folder…" and "Save As…" call `makeVideo` with `destination: 'ask'`; "Try Again" calls it with `'same'`.
- **HEVC.** When `encoders.hevc.available` is false the page disables the HEVC choice and shows "This computer can't make HEVC videos." under the picker. The remembered Codec stays HEVC and the page starts on H.264.
- **The tool missing, damaged or the wrong version.** `bootstrap().tool.state` is `damaged`: the one blocking state of SPEC 27.5, with Open Download Page (`openLink('download-page')`).
- **Time left.** Shown once encoding has run 1 second and passed 5% (SPEC 27.4, a recorded exception to rule 66).

## Shell codes

Codes the shell itself sends in a `Problem` or a `ToolStatus` (a tool error code is SPEC 14.6 and 24.6). Any code the page does not know gets "The video couldn't be made. Your files are unchanged." with Try Again.

| Code | When |
| --- | --- |
| `TOOL_NOT_FOUND` | No runnable `song2vid.exe` where the app expects it |
| `TOOL_INCOMPATIBLE` | The tool's `--version` is not `song2vid 1.2.0`, or a line says an `api_version` other than `"1"` |
| `TOOL_CRASHED` | The tool ended without exactly one final line, or exited non-zero after its result. **Not a `Problem.code`**: SPEC 27.6 ends the job as `export_failed`, so the code the page gets is `export_failed` and this name is `fault` in `details` (D-024) |
| `TOOL_PROTOCOL` | A line that is not JSON, a line without `api_version`, a line over 1 MiB, more than one final line, a line after the final one, or a result that lacks keys the shell needs. As `TOOL_CRASHED`: `export_failed` with `fault` `TOOL_PROTOCOL` |
| `usage` | A tool code the shell also sends: a `makeVideo` request it could not read, or one that names an id it does not hold (a released file). Nothing was started and no dialog opened |
| `cancelled` | A tool code the shell also sends: `previewImage` failed because the image was released while its preview was being made |
| `TOOL_STALLED` | Only in `ToolStatus` or as `fault`: a launch-time `--version` that gave no answer in 10 s. A running job is never killed for silence; it is shown as `JobUpdate.stalled` |

## The stand-in

`src/bridge.fake.ts` implements `DesktopBridge` for a plain browser. The headless audit and the screenshot script reach every state through it, chosen in the address's fragment (`#fixture=job-failed-output_in_use&platform=windows`). It must cover every state the app can be in: one fixture per designed empty, loading, error and dense state, and one per row of SPEC 27.5's error table. Its open dialog answers at once with generated files.

## Settled by S2V-029

- `check` takes one file (SPEC 24.8), so `chooseAudio`, `chooseImage` and a drop each ask the tool about the files they have. D-024 records the rest of the adapter's decisions.
- Every channel `electron/preload.ts` names has a handler in `electron/tool/index.ts` except the preferences, link and notices channels, which S2V-030 wrote (below).

## Settled by S2V-030 (D-025, D-026)

- `app:preferences`, `app:open-link`, `app:notices` and `Bootstrap.preferences` have handlers (`electron/app-data.ts`, wired in `electron/main.ts`). The Codec is saved the moment it is chosen; the theme and the window's place are the shell's own as before.
- A file opened with the app reaches `onFilesOpened` through `shell.ts` (`filesWaiting`) and `main.ts`, once the page has said it is listening (the preload sends `file:listening` when the page subscribes). Files that arrive while the page loads wait and are judged as a drop is.
- A refresh that ends between `bootstrap()` and the page's subscriptions is not missed: the page asks `bootstrap()` once more after it has subscribed. A cached ready tool that fails this launch's version check is announced by `onToolStatus`.
- `src/bridge.fake.ts` speaks the new bridge: every state of the window has a fixture (its header lists them, one `make-fail-<code>` for each row of SPEC 27.5) and `pnpm typecheck` is green.
