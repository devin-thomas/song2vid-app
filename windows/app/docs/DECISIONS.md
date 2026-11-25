# Decisions

Append-only. Each entry says what was decided, by whom, when, and what it changes. Entries D-001 to D-012 came with the starter. D-001, D-002 and D-004 to D-006 are defaults applied in two builds (the mail app and the media converter, 2026-11-15); D-003 and D-007 to D-012 come from one build (the media converter). A later entry may override any of them by saying why.

## D-001 Electron shell and web UI

Inherited default. The page is React and TypeScript; the shell is Electron; the app is its own program with its own processes. Memory is summed as private bytes over the process tree: about 300 MB is the budget and 680 MB is the ceiling no build may pass. Both numbers live in `app.config.json`.

## D-002 Logic stays outside the page

Inherited default. The page asks the main process through the functions in `electron/preload.ts`; the main process runs the installed command-line tool or core. The page holds no credentials and makes no network request (`connect-src 'none'`). An app that needs a server names its origins in the Content-Security-Policy in `electron/main.ts` and records why here.

## D-003 The tool ships inside the app

Default from build 2. The command-line tool and every program it drives ship inside the app, one binary per system and processor under `resources/bin/<platform>-<arch>/`, and are started by absolute path with an argument array, never through a shell or PATH (`electron/tool/locate.ts`). This replaces round 1's npm-global tool started through the system `node.exe`, which is still in the `windows-web` starter for an app whose tool is an npm global.

## D-004 Plain language in the interface

Inherited default, tightened in build 2. Headings, buttons and status speak in outcomes. Identifiers, hashes and raw tool output are never on screen, Details and About included: a Copy details action copies them for whoever repairs the app. The audit scans all rendered text for the whole-word terms in `qa/banned-terms.json`.

## D-005 Title bar height

Inherited default. 36 px on every system, matching the title bar overlay height so the system's window buttons and the bar are one strip. The Windows default is 32 px and the macOS bars are 32, 40 or 52 pt; the difference is deliberate and recorded. Set `macTitleBarHeight` in `app.config.json` to use one of the macOS heights there; the traffic lights then sit at the system's own position.

## D-006 Buttons scale on press, rows do not

Inherited default. Web-styled buttons scale to 0.97 while pressed. List rows, menu items and title-bar controls do not.

## D-007 One codebase for Windows, macOS and Linux

Default from build 2 (owner, 2026-11-15: "It needs to be fully cross-platform across Windows, Mac, and Linux"). One page, one stylesheet, one main process. Everything that differs between the systems is decided in `electron/platform.ts`, and the page learns the system from `bootstrap().platform`. A Mac-only app is SwiftUI instead (the skill's macOS branch).

## D-008 Closing and quitting follow the system

Default from build 2. Closing the last window quits on Windows and Linux; on macOS the app stays in the Dock and the window comes back on activate. A running job makes the close and the quit ask first, on every system.

## D-009 macOS has a real menu bar; Windows and Linux have none

Default from build 2. On macOS the menu bar holds every command with its shortcut, in Apple's order, with the system's roles for editing, hiding and quitting (`electron/menu.ts`). On Windows and Linux there is no menu bar (a menu there would draw a bar inside the window); the page's palette lists every command, and on Linux the shell handles Ctrl+Q, Ctrl+W, F11 and F10 itself.

## D-010 Launches by agents follow scripts/lib/launch.ts

Default from build 2, where agent launches took the owner's focus three times. Every scripted launch uses absolute paths, runs the shell check first, passes `--no-activate`, a throwaway data folder and a time limit, and ends the process it started by its exact id. No script uses a second instance to control the running app (D-011).

## D-011 Scripts reach the running app only through the control channel

Default from build 2 (the media converter, its D-018), found after agent checks took the owner's focus on Windows. A script never starts the app's executable a second time to talk to a running one: on Windows that hands the running app the right to come to the front (Chromium's process singleton calls `AllowSetForegroundWindow` for it before any app code runs). An app started with `--no-activate` or `--control` serves a named pipe (Windows) or a Unix socket (macOS, Linux), `electron/control.ts`, and writes where it listens to `control.json` in its data folder; an app a person started serves none. The executable started with a command flag forwards it through the channel and ends without asking for the single-instance lock. The app counts second launches, and every check that asks it anything expects 0. Scripts on Windows that Explorer runs start under `conhost.exe --headless`, with no console window. A person's own second launch still brings the window forward.

## D-012 The network service runs in the main process

Default from build 2 (D-019 there), with one condition: the page makes no network request (`connect-src 'none'`). The separate network process then isolates nothing, and running it in the main process took Windows idle memory from 304.4 MB to 243.2 MB installed (306.8 to 238.0 MB in development); macOS and Linux dropped about 10 MB. An app whose page talks to a server sets `NETWORK_SERVICE_IN_PROCESS` to false in `electron/main.ts` and records why here; `pnpm shell:check` fails the switch without `connect-src 'none'`.

## D-013 Everything is strict TypeScript; the main process is bundled

Owner, 2026-11-19 and 2026-11-21: strict typing everywhere and no hand-written JavaScript where TypeScript can go, following the owner's other TypeScript apps. The main process is `electron/*.ts` and `electron/tool/*.ts`, bundled by rolldown (`scripts/build-electron.ts`) into `dist/electron/main.mjs`, an ES module and `package.json`'s `main`, with the runtime kit packages inside it, so the package carries no `node_modules`. The preload is bundled to `dist/electron/preload.cjs`, one CommonJS file that requires only `electron`, because the window is sandboxed; its object `satisfies DesktopBridge`. The page builds to `dist/page/`. The no-dialog handler is its own module, imported first; the shell check holds that it comes first in the bundle. Electron 45 loads an ES-module main, and an error thrown while it loads still reaches `process.on('uncaughtException')`.

## D-014 The test instrumentation never reaches the package

`electron/qa.ts` is built to `dist/electron/qa.mjs` and loaded by a path computed at run time, only in an unpackaged app with a `--qa-*` flag. Its measurement package stays outside the bundle. `scripts/package.ts` leaves the file out, and the shell check fails if `main.ts` imports it by name or `main.mjs` contains it.

## D-015 Scripts, measurements, QA and tests run by Node's type stripping

`scripts/`, `measure/`, `qa/`, `test/` and `tokens/` are `.ts` that Node 24 and later run directly, with erasable syntax only (`erasableSyntaxOnly` in `tsconfig.node.json`). `qa/tsconfig.json` adds the DOM types for the functions Playwright runs in the page; `pnpm typecheck` checks the page, the main process, the scripts and `qa/`. `node --check` passes a broken ES-module `.ts`, so `scripts/lib/syntax.ts` strips the types first.

## D-016 The plain-Node scripts are built from TypeScript and committed

`scripts/control.cjs`, `installed-helpers.cjs` and `installed-diagnostics.cjs` are built from their `.ts` sources by `scripts/emit-plain-node.ts` and committed. The installed checks run them by those names with the installed app acting as Node, often from a checkout that was never built, and Electron's Node strips types only from `.ts` files. `test/plain-node.test.ts` fails when one differs from its source.

## D-017 measure/workload.js stays JavaScript

Its text is the expression the page evaluates for `--qa-bench`, and `measure/run.py` names the file, so it cannot be a module or need a build. It is type-checked with the page (`checkJs`).

## D-018 Shared code comes from the kit packages, and only from them

Owner, 2026-11-21. Code every app had been copying comes from published packages: `@uppercut-labs/electron-command-menu` (the menus), `electron-child-process-runner` (starting and stopping the tool), `electron-qa-measurements` (typing, palette, launch marks, the kill test), `electron-bridge-test-double` (the stand-in bridge), `browser-qa-harness` (serving the build and launching the browser for the audit) and `app-icon-generator` (icons) from npm, and `uppercut-windows-window-capture` from PyPI for the window picture in `measure/run.py`. The PresentMon capture stays in `measure/run.py` and `analyze.py` until `uppercut-presentmon-measure` reads displayed-frame times (`msBetweenDisplayChange`) and starts a delayed capture on a chosen process; moving earlier would quietly change what the numbers mean. `test/kit-only.test.ts` fails when a hand-rolled copy of any of them or a direct PresentMon call comes back, and names the package to use. A package that lacks something the app needs is extended; its code is not copied here.

## D-019 The control channel, memory reading and line reader are packages too

The control channel is `@uppercut-labs/electron-control-channel` (`electron/control.ts` names the app's command flags), the memory reading is `@uppercut-labs/electron-private-memory` (`electron/memory.ts` gives it the budget and ceiling), and the bounded line reader is `createLineReader` from `@uppercut-labs/electron-child-process-runner` 0.2.0. `scripts/control.cjs` is built from `scripts/control.ts` with the package bundled in, so installed checks still run it with no `node_modules`. `test/kit-only.test.ts` holds all three.

## D-020 Desktop apps are dark by default

Owner, 2026-11-21. A generated app starts dark on first run and with any fresh data folder, whatever the operating system's theme is. Light is a choice the person made and the app saved; the saved choice wins on every later start. `electron/theme.ts` holds the one rule (`initialTheme`), `electron/window.ts` paints the window with it, and `index.html` sets the page the same way before first paint (the shell names its theme in the address, a plain browser reads `localStorage`, and with neither the theme is dark). The system setting is never read. `test/dark-default.test.ts` fails when a fresh profile renders anything but dark, with the operating system set to light. The QA helpers open pages dark, and a critique round (`pnpm qa:shots --quick`) photographs dark alone; the audit still checks both themes, because light stays available.

## D-021 Rules 104 to 111 are built in, each with a check that fails when it is broken

2026-11-21. The starter had the page checks but nothing for the shell's trust: a crashed renderer, a window saved on a monitor that is gone, what the page may ask Chromium for, the fuses, focus under a contrast theme, colour outside the tokens, or a picture that changed. They are now rules 104 to 111 of the premium bar, with code and checks in the starter: `electron/bounds.ts` and the crash handling in `electron/window.ts`, `electron/boundary.ts`, `scripts/lib/fuses.ts`, `pnpm qa:crash`, `pnpm shell:check` (rule 10), the audit's `forced` and `tokens` gates, `pnpm fuses:check` and `pnpm qa:visual`. `pnpm qa:planted` makes one break per rule in a throwaway copy of the app and requires its check to fail, so a check cannot quietly stop checking.

- **Fuses.** `NODE_OPTIONS` and `--inspect` off, the app only from `app.asar`, no extra file-protocol privileges, asar integrity on macOS only (on another system only after its packaged app has started with it). `RunAsNode` stays on, with `RUN_AS_NODE_REASON`, because the installed checks run the app's own binary as Node; turning it off is the next step. `--inspect` off means Playwright's `_electron` cannot drive a packaged app: drive the development app, which is never fused.
- **Permissions.** One allowed: writing to the clipboard, for Copy details. An app that needs another adds it to `ALLOWED` in `electron/boundary.ts` with its reason, and the test names it.
- **Baselines.** Per system, because each system draws fonts its own way, in `qa/baselines/<system>/`. The starter keeps none (`.gitignore`); an app removes that line and commits its own after reviewing the pictures. The threshold is 0.02 with anti-aliasing excluded, and a picture fails above 0.05% changed pixels: 0.1, the library's default, cannot see the design's smallest step.
- **Crash loop.** More than 3 renderer crashes in 60 s stop the reloads. The notice that tells the person is never shown under `--no-activate`, because a dialog would take focus.

## D-022 Song2Vid's seam files replace the starter's examples (S2V-028)

Song2Vid for Windows is built from this starter (ADR-022). Before any page work, the seam files were written for it: `src/bridge.ts` with `docs/BRIDGE.md`, `docs/JOURNEYS.md` with `qa/journeys.json`, `shortcuts.json`, `qa/banned-terms.json`, and `docs/TOOL-CONTRACT.md`, which now points at SPEC sections 14, 24 and 26 instead of describing the starter's example contract (ADR-024). The starter's example screen, its job, its stand-in bridge and its scenarios still speak the old seams until S2V-029 and S2V-030 replace them, so `pnpm typecheck`, `pnpm test` (the preload name check) and `pnpm qa:audit` (journeys and shortcuts) are expected to fail on the example until then. `windows/SKILL-NOTES.md` lists each file.

## D-023 Window size is Song2Vid's own

Default 560 x 760 and minimum 480 x 640 (SPEC 27.1), in `app.config.json`. The starter's example screen does not fit this width (its title bar overflows at 200% zoom and its two-pane journey fails), which is the reason the window size was changed in a commit of its own after the starter's gates had passed at its own size.

## D-024 The adapter speaks SPEC 14, 24 and 27.6 (S2V-029)

The starter's adapter (`--capabilities`, `--events 1`, `--stdin-control`, a `hello` first line, sequence numbers) is replaced. What was decided where the SPEC or the seam files left room:

- **One contract.** Every line has `api_version: "1"` and a `type`; unknown keys and types are ignored; exactly one final `result` or `error`. A different `api_version` is `TOOL_INCOMPATIBLE`. `make` and `preview` get `--json --cancel-on-eof`; `check` and `encoders` get `--json` only, and never `--cancel-on-eof`, so the tool never reads their stdin. Every path is absolute, so no name can read as an option and `--` is not used.
- **Faults end the job as `export_failed`** (SPEC 27.6), with the adapter's own name for the fault (`TOOL_PROTOCOL`, `TOOL_CRASHED`, `TOOL_STALLED`) in `Problem.details`. BRIDGE.md had listed `TOOL_CRASHED` and `TOOL_PROTOCOL` as codes the page receives; the page's sentence for them was the generic one either way, so the change is only in the code. `TOOL_NOT_FOUND` and `TOOL_INCOMPATIBLE` stay codes.
- **`--version --json`.** SPEC 27.6 names it and SPEC 14.2 lists `--json` only for check, make and `--update`. The Mac command refuses `--version --json` with a usage error. The adapter asks `--version --json` first and, when that gives no version line, plain `--version`. Either form must print exactly `song2vid 1.2.0`. S2V-025 should accept `--version --json` or SPEC 27.6 should drop `--json`; the adapter works with both.
- **Launch.** `--version` first, then `encoders --json` in the background. The last answers are cached by the binaries' size and modified time (`tool/report.json` in the data folder) and shown at once. A failed version check removes the cache. `encoders` that fails keeps the old report.
- **Temporary files.** The tool does not name its `.song2vid-<32 hex>.tmp` in any line (SPEC 14.5 says no folder path and the key list has no such key), so the job record holds the output folder alone. The next launch removes, directly in each recorded folder, regular files matching `^\.song2vid-[0-9a-fA-F]{32}\.tmp$` and nothing else. After a job the adapter had to kill, or one that broke the contract, the shell removes the matching files that were not in the folder before the job started. Hex digits of either case are accepted because the file name is case-insensitive on Windows and SPEC 26.3 says only "32 hex". A live tool from another program writing into the same folder at that moment is the one case this cannot tell apart; the SPEC's rule has the same limit.
- **Preview** is returned as a `data:image/png;base64,` address, which the page's Content-Security-Policy already allows. A route on the `app://` scheme would need a change to `electron/main.ts`; S2V-030 may choose it.
- **The save dialog and `--overwrite`.** `--overwrite` is passed only when the chosen name already ends in `.mp4`, the file exists and the Windows dialog (which asks before replacing) returned it. A name without `.mp4` gets it appended and is never replaced. Try Again (`destination: 'same'`) reuses the last destination and its overwrite answer. The last folder is remembered when a video is saved, not when one fails (`tool/destination.json`).
- **Dialogs under `--no-activate`** are never opened (D-010); the call answers as if the person had closed the dialog.
- **Time left** is withheld by the shell until encoding has run 1 second and passed 5% (SPEC 27.4), then taken from the tool, changing at most once a second.

## D-025 The window (S2V-030)

The page is Song2Vid's one window (SPEC 27.2). The decisions where the SPEC or the seam files left room:

- **Where the words go.** The status bar holds everything that is said about a job, because it is the one place that never moves (premium bar rule 97): it is two lines of one line each, 56 px high in every state (the starter's was one line of 40 px; the SPEC's done message has "a second line"). Line one is what is happening or what happened; line two is what goes with it (the Codec, the Encoder and the length of a saved video; the Encoder and the time left while one is made; the second sentence of an error). Each is cut at its end by the stylesheet, and the whole sentence stays in the page for a screen reader. SPEC 27.5's sentences are split at their sentence break and say exactly the SPEC's words when read together (`test/words.test.ts` holds the table). The filled button is at most one, at the right of the bar.
- **The card.** Choices and the preview scroll inside the card when the window is too small for them (200% zoom is 280 x 380 CSS px); Make Video sits below the scroll area and never leaves the window. The preview takes the room that is left and keeps the frame's shape (container query units, no script measures it).
- **Make Video** is enabled when both files are loaded, the tool is usable, no job runs, no question is open and the frame can be made (an Original of under 16 px is the preview's words, not an error row). Pressing it opens the save dialog; until the shell answers the status bar says "Getting ready", and a dialog closed without a choice puts everything back. Cancel pressed before the shell has named the job is sent the moment it does.
- **Cancel** shows "Cancelling" in the same task as the press and "Cancelled. Nothing was saved." only when the tool's exit says so; the choices unlock then. A message of a few seconds (the 3-second "Wait for the current video to finish.", a rejected drop) takes the two lines and leaves the progress bar and Cancel where they are.
- **Time left** follows the SPEC's exception to rule 66: shown once encoding has run 1 s and passed 5%, in coarse words ("about 20 seconds left"), changing at most once a second and never up by more than a second (the shell does it; the page applies it again). Progress never goes back and shows at most 99% until the outcome.
- **Repeat.** The same code twice in a row for the same inputs says "It failed again." and the filled button becomes Copy Details (rule 69). A different input, a success, or a failure of another code starts over. Otherwise Copy Details is a palette command with no shortcut (`copy-details` in `shortcuts.json`, File menu on macOS) and a button beside Open Download Page in the blocking state. It is not a second button in the status bar: with it, the first line of the longest sentence ("A file with that name appeared while the video was being made.") was cut at the default width.
- **The tool missing, damaged or the wrong version** is one blocking state in the card with Open Download Page filled and Copy Details beside it; every control is gone, so there is nothing to disable. It arrives from `bootstrap().tool`, from `onToolStatus` (a cached ready answer that this launch's version check overturned) and from a job that fails with `TOOL_NOT_FOUND` or `TOOL_INCOMPATIBLE`.
- **Choices** (Frame Shape, Resolution, Codec) are radio groups made of buttons: one tab stop, the arrow keys choose, a disabled choice (HEVC where it cannot be made) is skipped. They are not native radio inputs (rule 72). Original replaces Resolution with "Output: W x H" from the tool's own table.
- **Crop position** is the preview frame itself when the image can move, `role="slider"` with a minimum of 0, a maximum of 100, the percentage along the axis that can move and the value text "50% across, 30% down" (rule 75). Arrow keys move the image 5% of the movable range (25% with Shift) the way the Mac app does, Page Up and Page Down are the large step, Home and End the ends of the axis, Ctrl+0 and Reset to Center the middle. A drag moves the image the pointer's own distance in the same task. When there is nothing to crop the frame is a plain picture and not a tab stop. The page's frame math is a port of `OutputFrame` held to `fixtures/frame-math.json` (`test/frame.test.ts`).
- **Focus.** The window starts on Choose Audio. A file dialog opened by its shortcut returns focus to its button, so the next Tab is the next control (the journey budgets assume it). When a job ends and the controls that were disabled had focus, it goes to the status bar's button, else Make Video. A dialog opened by a drop returns focus to where it was.
- **The Replace question** is the page's own dialog: Replace, then Keep Current, which is filled, focused first, and what Esc and a click outside choose. Ids the person did not keep are released.
- **Drops.** The whole window takes them; a drag lights the window only when its types could be used (names are not readable until the drop); while a video is made a drop is accepted so it can be refused in words, without asking the shell.
- **The page saves no document.** The starter's draft, its `storage.ts`, the toasts and the 10,000-row list are gone; `STATE_KEYS` in `electron/main.ts` is empty. What survives a run is the Codec (`preferences.json`, written the moment it is chosen), the theme and the window's place (`window.json`) and the last save folder (`tool/destination.json`). A renderer that crashes comes back showing the remembered Codec and with no files chosen: the files' ids belong to the page's session, and SPEC 27.2 says an id is made only from a dialog, a drop or a file opened with the app.
- **Tokens.** `statusbar` 56, `label-col` 96, and one new colour, `frame` (the black of a video's bars, the same in both themes), because the tokens gate allows no colour literal in `src/`.
- **About** shows Song2Vid and its version, the licence, a button that opens the repository and the notices text (`THIRD-PARTY-NOTICES.txt`, which the packager rebuilds). The banned-terms gate leaves out the one element that carries `data-notices`, and nothing around it: the audit plants a banned word beside the notices and requires it to be caught, plants one inside and requires it to pass, and fails when any element outside About carries the attribute.

## D-026 Seam changes for the window (S2V-030)

Recorded here because `src/bridge.ts`, `docs/BRIDGE.md` and `shortcuts.json` change only by a decision.

- **`onToolStatus(listener)`** in `DesktopBridge` (channel `tool:status`): S2V-029's open point that a cached ready tool failing this launch's version check was not announced. The service emits it only when it had told the page "ready" and the check then says otherwise.
- **The page asks `bootstrap()` once more** after it has subscribed, and takes a newer Encoder report or tool status from it, so nothing that arrived between the first answer and the subscriptions is missed (S2V-029's other open point).
- **`app:preferences`, `app:open-link`, `app:notices`** and `Bootstrap.preferences` have handlers (`electron/app-data.ts`, `electron/main.ts`). The page names one of two links and never an address; an update is read key by key and anything but a known Codec is ignored; the notices come from `resources/THIRD-PARTY-NOTICES.txt` when packaged and `third-party/` in development.
- **Files opened with the app** (a second launch, Open with, the Dock): `shell.ts` gets an optional `filesWaiting` callback; `main.ts` hands the waiting paths to `native.openFiles` once the page has said it is listening (`file:listening`, sent by the preload when the page subscribes to `onFilesOpened`), so files that arrive while the page loads are not lost. They are judged as a drop is.
- **`shortcuts.json`** gains `copy-details` (no shortcut). The Cancel key prints as Esc (macOS: the Escape symbol).
- **A development-only answer for the dialogs** (`--qa-pick-audio=`, `--qa-pick-image=`, `--qa-pick-save=`, `electron/tool/qa-picks.ts`): a launch that is not packaged answers the open and save dialogs with the named files and opens nothing, so nothing takes focus (D-010) and a run with no one to click still goes through the same ids, the same one-file check and the same save rules. Only a file that exists answers an open dialog. The headless audit does not need it (its stand-in bridge answers at once); `qa:crash`, `qa:kill`, `qa:typing` and the workload use it or the stand-in tool.

## D-027 The checks for the window (S2V-030)

- **One list of states** (`qa/states.ts`) feeds the audit (axe, layout at four sizes, focus, language, forced colours) and the pictures (`qa/shots.ts`, `qa/visual.ts`): empty, a song alone, an image alone, both, each Frame Shape, a moved crop, HEVC chosen and disabled, an enlarged image, an Original that is too small, long names, the preview loading and failed, making (with time left, early, stalled), cancelling, cancelled, done, every row of SPEC 27.5 (and a code the page does not know, and a repeat), a chosen file that fails its check, the tool missing at launch and after it, the palette, About with its notices, the Replace question, the drop highlight and a refused drop. The dimmed title of an inactive window is a picture only (it is meant to be dim).
- **The pictures.** The main size in the dark theme takes every state; the other sizes, the light theme, each system's labels, forced colours and 200% zoom take the core states. Baselines are committed for the macOS run on the Mac and the Windows run on Titan, accepted after looking at them.
- **The gates added** beyond the starter's: `crop`, `files`, `tool`, `notices`, and a `job` gate that holds the error table to SPEC 27.5 sentence by sentence (written out again in the audit, not read from the page). `AUDIT_ONLY=job,files node qa/audit.ts` runs some gates while one is being worked on; a run without it is the gate.
- **Rule 6 for a drop-opened dialog.** Focus is inside the question within a frame of its opening and returns where it was; there is no key to be "in the same turn" as.
- **`qa:typing`** measures the palette only and says the typing rules are N/A (there is no text field); `qa:kill` and the `recover` trial of `qa:crash` use the Codec as the saved state (`--qa-choose-codec`, `--qa-read-codec`); `measure/workload.js` moves the crop, cycles the pickers and opens the palette. They run the stand-in tool (`qa/standin.ts`) in the development shell.
- **The window against the real tool** (`pnpm qa:real -- --tool-dir <folder>`, `qa/real-tool.ts`): the built page in a headless browser, its bridge the real `electron/tool/service.ts` over a real `song2vid.exe`, the dialogs answered with generated media. For each Frame Shape it drives the keys of a person's route, then has the command make the same video with the same options and compares the pixel size, the length (within 0.1 s), the Codec and the tracks. `--standin` runs the same plumbing against the stand-in tool.

## D-028 The critic's round (S2V-031)

One independent critic saw only the pictures of S2V-030 (`windows/docs/CRITIQUE-1.md`). Each must-fix class is fixed, and each class is a gate in `qa/audit.ts` that was shown failing on the S2V-030 build. Decisions where the critique and the SPEC pulled apart:

- **The light theme was never captured.** The page takes its theme from the saved choice and never from the system's setting (D-020); `qa/lib.ts` set only the browser's colour scheme, so every "light" picture and every "light" audit run was the dark theme (byte-identical pictures; axe "in both themes" was dark twice). `openPage` now saves the choice before the page loads, `load` throws when the page shows another theme than the one it was opened for, `qa/shots.ts` fails when a light picture equals its dark picture, and the audit has a `theme` gate. The light theme then had real contrast findings (fixed) that nothing had seen.
- **Scrolling is allowed; hiding is not.** At 200% zoom (280 x 380 CSS px) the choices and the preview cannot all fit. The card's work area scrolls, and while more is below it a strip under it says "More below" (`ScrollArea.tsx`, a real element: the old fade was a mask animated by scroll position, which a picture finishes to its end state and a headless browser's hidden scrollbars never show). Make Video stays below the strip. The `clipped` gate no longer counts a mask as a cue; the new `reach` gate brings every control of every scroll area into view; the new `truncated` gate fails any label, message or note cut by its own box, and any button cut by what holds it. Frame Shape reflows to three and two at that width, a file's name and facts take their own line under its button, and the blocked state scrolls too.
- **The status bar wraps and is as tall as its longest message.** Sentences wrap (premium rule 97's "cuts a long message at its end" is replaced by "never cut, one height"): the live message sits in one grid cell with every message the bar can say (`everyStatusView`, built from the same tables) drawn invisibly in the same cell, so the cell is the height of the tallest at the width it has and no state moves anything (the `stable` gate, which holds at all four sizes). No script measures anything. The filled button takes its own line under the sentence at 420 px and narrower.
- **An error is not a status.** The bar has a tone (`neutral`, `warning`, `danger`, `success`): a failure is the danger tone and a refusal the warning tone, with a mark, a 10% tint, a 3px edge and a semibold first line; a saved video is the success tone with a check. SPEC 27.5's sentences are unchanged. The `distinct` gate compares each against the idle bar.
- **Controls and messages say one thing.** A job that fails with a code about a file in a slot (`audio_*`, `image_*`), or an image that cannot be drawn, marks that slot (`failure.of`): the row names the problem in the error colour ("Can't find it"), the preview says it, the bar says it with its button, Make Video waits, and the enlarge note goes. A new file for that slot frees all of it. A file that is rejected when it is chosen does not mark the slot of the file that was already good. HEVC after `codec_unavailable` holds Make Video until H.264 is chosen. An image too small for its frame is said by the bar in SPEC 27.5's words. A missing tool leaves the bar empty; the card has the message and the buttons. The `messages` gate checks all of it.
- **Rejected: must-fix 6.** Copy Details stays the filled button of a repeated failure (SPEC 27.5, premium rules 50 and 69). The critic asked for Save As; the SPEC says a repeat says so and offers a different step that copies the details for whoever repairs the app.
- **Done says the folder's own name** (it always did: `whereOf` in `service.ts` is the folder's name, "Videos" only when it is Videos; the picture's fixture said Videos). A success mark and tone are new. Rejected part: the encoder stays on the second line (SPEC 27.4 wants the owner to see which Encoder made the video). Show in File Explorer stays the filled button.
- **Progress** is a bar across the top edge of the status bar, the width of the window, with the percent said once, in the words. Its first line and button keep their place because the bar has one height. The encoder's name stays (rejected part of must-fix 8).
- **The accent** (token `accent`, both themes) is the filled button's colour: Make Video and each state's button. Disabled is an outline, plainly not ready. The `tokens` gate now computes contrast for every pair the stylesheet makes: the text on the fill (4.98:1 light, 8.12:1 dark), the fill on the card and on the status bar, each tone on its tint, and both text lines on each tint.
- **The focus ring is for the keyboard.** `:root[data-modality="pointer"] :focus-visible` has no outline; the window starts in pointer modality, a pointer action returns to it, the first key that is not a modifier shows the ring at once, and an inactive window shows none. The row label no longer brightens on focus. The window still starts on Choose Audio (D-025). The `ring` gate checks the first paint, a click, a key, an inactive window and the pointer moving.
- **Refused drops say what was refused and what to do instead**, in two lines in the warning tone, naming the file when one was dropped (`rejectionLines`).
- **Names are cut in the middle** where the end carries meaning (premium rule 71): the start and the last 8 characters stay, the whole name is the tooltip, and the facts sit next to the name.

## Preferences ledger

Every preference the app offers is listed here with the reason a default could not serve. The starter has one: the theme, which starts dark and keeps a person's saved choice (D-020).

Song2Vid (D-025): the Codec (H.264 until a person chooses HEVC; the SPEC's rule 51 reason: both are right for someone, and the choice is the one thing a person repeats), and the theme, as in the starter. The last save folder and the window's size and place are kept without being offered. There is no settings window.
