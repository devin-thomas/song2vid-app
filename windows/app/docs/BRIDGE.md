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
| Running the tool | The shell | `electron/tool/` runs `song2vid.exe --json --cancel-on-eof` (SPEC 27.6). One job at a time. A second `makeVideo` while one runs resolves `{ status: 'busy' }` |
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
| `chooseAudio()`, `chooseImage()` | The Windows open dialog, filtered to the section 7 types, then the section 7 check | `chosen` with an `AudioInfo` (id, file name, length) or an `ImageInfo` (id, file name, pixel size, and the section 14.3 table of output sizes with placement and "enlarged"); `dismissed` when the person closed the dialog; `unusable` with the tool's code. Nothing changes unless `chosen`: a choice replaces the current file (SPEC 4) and the page then calls `releaseFiles` for the old id |
| `dropFiles(files)` | Judge a drop (SPEC 4a) | `ok` with the audio and image the drop holds (either may be `null`), each already checked, or `rejected` with a reason: `more-audio`, `more-images`, `too-many`, `folder`, `unsupported`, `unreadable`. The shell changes nothing and the page decides: an empty slot is filled, a filled slot gets the page's Replace dialog, and an id the person did not keep goes to `releaseFiles`. While a video is being made the page refuses a drop itself, with "Wait for the current video to finish." for 3 seconds in the status bar, and does not call it |
| `onFilesOpened(listener)` | The same judgement for a file opened with the app | The same `DropResult` |
| `releaseFiles(ids)` | Free ids the page will not use | Nothing |
| `previewImage(imageId)` | `song2vid preview` (SPEC 24.3): the image as the video will see it, any supported type | `ready` with an `src` the page's policy allows and its pixel size, or `failed` with a problem |
| `onEncoders(listener)` | A fresh `encoders` answer after the launch refresh (SPEC 27.6) | One `EncoderReport` per refresh |
| `makeVideo(request)` | Open the save dialog (`destination: 'ask'`), or reuse the last destination (`'same'`, for Try Again), then start the job | `started` with a job id as soon as it is recorded; `dismissed` when the person closed the save dialog; `busy` |
| `cancelJob(jobId)` | Close the tool's stdin (SPEC 24.4), then kill it after 3 s | Nothing. The job ends with a `cancelled` update. The page shows "Cancelling" on the next frame without waiting |
| `onJob(listener)` | The job's updates, one at a time, in order | `running` (stage, percent or `null`, elapsed and remaining seconds, the Encoder from the encoding stage, `stalled` after 30 s with no line), then exactly one of `done`, `cancelled`, `failed` |
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
| `TOOL_INCOMPATIBLE` | The tool's `--version` is not `song2vid 1.2.0` |
| `TOOL_CRASHED` | The tool ended without exactly one final line |
| `TOOL_PROTOCOL` | A line that is not JSON, or longer than 1 MiB |
| `TOOL_STALLED` | Used only in `JobUpdate.stalled`; no job is killed for silence |

## The stand-in

`src/bridge.fake.ts` implements `DesktopBridge` for a plain browser. The headless audit and the screenshot script reach every state through it, chosen in the address's fragment (`#fixture=job-failed-output_in_use&platform=windows`). It must cover every state the app can be in: one fixture per designed empty, loading, error and dense state, and one per row of SPEC 27.5's error table. Its open dialog answers at once with generated files.

## Open points for S2V-029 and S2V-030

- `check` takes an audio and an image together (SPEC 14.2), yet `chooseAudio` and `chooseImage` each resolve with one file's facts. How the shell learns a song's length with no image chosen yet (or the frame table with no song) is not in the contract. S2V-029 decides it (a one-file form of `check`, or a probe in the tool) and records it in `docs/DECISIONS.md` before the page depends on it.
- `src/bridge.ts` replaced the starter's example bridge. Until S2V-029 and S2V-030 rewrite their halves, `electron/preload.ts`, `electron/main.ts`, `electron/tool/index.ts`, `src/bridge.fake.ts` and the starter's example page still speak the old one, so `pnpm typecheck` and `test/preload.test.ts` fail until then. This is expected and recorded in `windows/SKILL-NOTES.md`.
