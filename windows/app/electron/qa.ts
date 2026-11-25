// Test instrumentation for the development shell. main.ts loads it (as dist/electron/qa.mjs)
// only when the app is not packaged and a --qa-* flag is present; the packaged app does not
// include it (scripts/package.ts leaves it out, and the main bundle never imports it).
//
//   --qa-typing=<out.json>          the palette shortcut to the frame that shows it (Song2Vid has no text
//                                   field, so there is no typing run: rules 27, 29, 41, 41b and 44 are N/A)
//   --qa-choose-codec=<out.json>    choose HEVC in the page by its own control, report the PID and the time of
//                                   the choice, then stay open (the kill test terminates this process from outside)
//   --qa-read-codec=<out.json>      report the Codec the page shows, then quit
//   --qa-marks=<out.json>           launch and first-frame times, the display, and the result of --qa-bench
//   --qa-bench=<script.js>          run a scripted workload inside the page (measure/workload.js) and record what it returns
//   --qa-exit-after=<seconds>       quit after this long (the measurement harness uses it)
//
// What these runs choose is the Codec, the one thing Song2Vid saves on a click (the theme and the
// window's place are the shell's; the last save folder is saved when a video is). The choice is read
// back after a relaunch by the page's own control, so the run proves the whole path: the click, the
// bridge, the main process's write and the next launch's bootstrap.
//
// Measurement comes from @uppercut-labs/electron-qa-measurements, a development dependency
// imported here at run time and never bundled. Every key goes into the page through the
// DevTools protocol with the page told it has focus, and every kit call is given that
// injector, so the window is never focused and no system input is used.
//
// The verdict: the premium bar's published limits decide (references/premium-bar.md, rules 7,
// 27 and 41). See qa/premium-gate.ts.
import fs from 'node:fs';
import path from 'node:path';
import { app, screen } from 'electron';
import type { BrowserWindow, KeyboardInputEvent } from 'electron';
import type { KeyInjector, WindowLike } from '@uppercut-labs/electron-qa-measurements';
import { judge } from '../qa/premium-gate.ts';
import { stackOf } from './errors.ts';

type Kit = typeof import('@uppercut-labs/electron-qa-measurements');
type WriteState = (key: string, json: string) => void;
export interface QaOptions {
  launchedAt: number;
  system: 'windows' | 'macos' | 'linux';
}

/** The Codec choices in the page: one radio group, each choice carrying its value. */
const CODEC = (value: string) => `[data-group="codec"] [data-value="${value}"]`;

function arg(name: string): string | null {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : null;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const kitOf = (): Promise<Kit> => import('@uppercut-labs/electron-qa-measurements');

/**
 * The window as the kit's WindowLike, which takes input events with any `type` string where
 * Electron names its four key event types. It has no focus(): the kit cannot focus the window
 * through it, whatever it is asked.
 */
function windowFor(win: BrowserWindow): WindowLike {
  return {
    getBounds: () => win.getBounds(),
    isVisible: () => win.isVisible(),
    isFocused: () => win.isFocused(),
    close: () => win.close(),
    webContents: {
      executeJavaScript: (source) => win.webContents.executeJavaScript(source) as Promise<unknown>,
      sendInputEvent: (event) => win.webContents.sendInputEvent({ ...event, type: event.type as KeyboardInputEvent['type'] } as KeyboardInputEvent),
      reload: () => win.webContents.reload(),
      once: (event, listener) => win.webContents.once(event as 'did-finish-load', listener),
    },
  };
}

/** The DevTools protocol on this window's page, with the page behaving as focused. */
async function protocolInjector(win: BrowserWindow, kit: Kit): Promise<KeyInjector> {
  const dbg = win.webContents.debugger;
  if (!dbg.isAttached()) dbg.attach('1.3');
  const send = (method: string, params: Record<string, unknown> = {}) => dbg.sendCommand(method, params) as Promise<unknown>;
  await kit.emulatePageFocus(send);
  return kit.createProtocolInjector(send);
}

async function typingScenario(win: BrowserWindow, outFile: string, options: QaOptions): Promise<void> {
  const kit = await kitOf();
  const display = screen.getDisplayMatching(win.getBounds());
  const injector = await protocolInjector(win, kit);
  await sleep(800);

  // The palette: Ctrl+K (Command+K on macOS) to the frame that shows it.
  const palette = await kit.measureCommandPalette(windowFor(win), { openSelector: '.palette', injector, modifier: options.system === 'macos' ? 'meta' : 'control' });

  const gate = await judge({ typing: {}, typingNotApplicable: 'Song2Vid has no text field (SPEC 28: rules 27, 29, 41, 41b and 44 are N/A)', palette, windowFocusedAfterTyping: win.isFocused() });
  const report = {
    at: new Date().toISOString(),
    display: { hz: display.displayFrequency, scale: display.scaleFactor },
    window: kit.describeWindow(windowFor(win)),
    note: 'Times run from the key event timestamp to the end of the frame that rendered the change, on the page clock. They do not include the compositor or the display.',
    palette,
    gate,
    passed: gate.passed,
  };
  await kit.writeJsonReport(path.resolve(outFile), report);
}

/** Wait until the page has a Codec control that can take a choice (the first paint may still be coming). */
async function waitForCodecControl(win: BrowserWindow): Promise<void> {
  for (let i = 0; i < 100; i += 1) {
    if (await win.webContents.executeJavaScript(`Boolean(document.querySelector('${CODEC('hevc')}'))`)) return;
    await sleep(100);
  }
  throw new Error('the page has no Codec control');
}

/** Choose HEVC the way a person does (a click on its choice), so the whole path to the saved file is exercised. */
async function chooseCodec(win: BrowserWindow, outFile: string): Promise<void> {
  await waitForCodecControl(win);
  // The HEVC choice is disabled until the Encoder report says this computer can make it.
  for (let i = 0; i < 100; i += 1) {
    if (await win.webContents.executeJavaScript(`!document.querySelector('${CODEC('hevc')}').disabled`)) break;
    await sleep(100);
  }
  await win.webContents.executeJavaScript(`document.querySelector('${CODEC('hevc')}').click(); true`);
  const at = Date.now();
  fs.writeFileSync(path.resolve(outFile), JSON.stringify({ pid: process.pid, at, expected: 'hevc' }));
}

const readCodec = (win: BrowserWindow): Promise<string | null> =>
  win.webContents.executeJavaScript(`document.querySelector('[data-group="codec"] [aria-checked="true"]')?.getAttribute('data-value') ?? null`) as Promise<string | null>;

async function readCodecScenario(win: BrowserWindow, outFile: string): Promise<void> {
  await waitForCodecControl(win);
  await sleep(600);
  fs.writeFileSync(path.resolve(outFile), JSON.stringify({ codec: await readCodec(win) }));
  win.close();
}

/**
 * Launch-to-first-frame marks and an optional scripted workload, for measure/run.py. The marks
 * are written as soon as the first frame is in, before the workload runs: run.py waits for
 * firstFrameAfterLoad to time everything after it, and the workload takes most of a minute.
 */
async function marksScenario(win: BrowserWindow, outFile: string, options: QaOptions): Promise<void> {
  const kit = await kitOf();
  const exitAfter = Number(arg('qa-exit-after') ?? 0);
  const marks: Record<string, unknown> = {
    ...(await kit.measureLaunchMarks(windowFor(win), {
      launchedAt: options.launchedAt,
      getDisplay: (bounds) => {
        const d = bounds ? screen.getDisplayMatching(bounds) : screen.getPrimaryDisplay();
        return { hz: d.displayFrequency, scale: d.scaleFactor, primary: d.id === screen.getPrimaryDisplay().id };
      },
    })),
  };
  const flush = () => fs.writeFileSync(path.resolve(outFile), JSON.stringify({ pid: process.pid, marks }, null, 2));
  flush();
  if (exitAfter > 0)
    setTimeout(() => {
      flush();
      app.quit();
    }, exitAfter * 1000);
  const bench = arg('qa-bench');
  if (bench) {
    try {
      marks['bench'] = await win.webContents.executeJavaScript(fs.readFileSync(path.resolve(bench), 'utf8'));
    } catch (error) {
      marks['benchError'] = String(error);
    }
    flush();
  }
}

export async function run(win: BrowserWindow, _writeState: WriteState, options: QaOptions): Promise<void> {
  try {
    const marks = arg('qa-marks');
    if (marks) return await marksScenario(win, marks, options);
    const typing = arg('qa-typing');
    const choose = arg('qa-choose-codec');
    const read = arg('qa-read-codec');
    if (typing) {
      await typingScenario(win, typing, options);
      win.close();
    } else if (choose) await chooseCodec(win, choose);
    else if (read) await readCodecScenario(win, read);
  } catch (error) {
    process.stderr.write(`qa: ${stackOf(error)}\n`);
    const out = arg('qa-typing') ?? arg('qa-choose-codec') ?? arg('qa-read-codec') ?? arg('qa-marks');
    if (out) fs.writeFileSync(path.resolve(out), JSON.stringify({ error: stackOf(error) }));
    if (!win.isDestroyed()) win.close();
  }
}
