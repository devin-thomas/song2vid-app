// Shared helpers for the screenshot and audit scripts (the states they open are in qa/states.ts). Everything runs headless;
// no window is shown and nothing can take focus or make a sound. The production
// build is served from this process on 127.0.0.1, so there is no separate server
// to stop. The page runs against the stand-in bridge (src/bridge.fake.ts), whose
// fixture is chosen in the address's fragment.
import { launchBrowser, serveFolder } from '@uppercut-labs/browser-qa-harness';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Browser, BrowserContext, Page } from 'playwright-core';

/** One call the page made to the stand-in bridge, as the bridge double records it. */
export interface DesktopCall {
  name: string;
  args: unknown[];
}

// What the pages these scripts open put on `window`: the clipboard capture below, the stand-in
// bridge's call log, and the motion recorder in audit.ts. Only qa/ sees these names.
declare global {
  interface Window {
    __copied: string[];
    __desktopCalls?: DesktopCall[];
    __seen: WeakSet<Animation>;
    __motion: MotionRecord[];
  }
}

/** One animation the recorder in audit.ts saw start. */
export interface MotionRecord {
  kind: string;
  name: string;
  properties: string[];
  duration: number;
  iterations: number | 'infinite' | undefined;
  target: string;
  inSheet: boolean;
}

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const dist = join(root, 'dist', 'page');

/** The parts of app.config.json that these scripts read. */
export interface AppConfig {
  productName: string;
  storagePrefix: string;
  window: { width: number; height: number; minWidth: number; minHeight: number };
}

export const readConfig = (): AppConfig => JSON.parse(readFileSync(join(root, 'app.config.json'), 'utf8')) as AppConfig;

// Serving the build and launching the browser come from @uppercut-labs/browser-qa-harness:
// the folder on 127.0.0.1 with a path guard, and the first Chromium-family browser that starts
// headless and muted (QA_BROWSER, then Edge, then Chrome, then Playwright's own Chromium).
export async function serve(dir: string = dist): Promise<{ url: string; close: () => Promise<void> }> {
  const site = await serveFolder(dir, { requireIndex: true, cacheControl: 'no-store' });
  return { url: site.url.replace(/\/$/, ''), close: () => site.close() };
}

export async function launch(): Promise<{ browser: Browser; channel: string }> {
  const { browser, channel } = await launchBrowser({ envVar: 'QA_BROWSER', channels: ['msedge', 'chrome', 'bundled'], args: process.platform === 'linux' ? ['--disable-dev-shm-usage'] : [] });
  return { browser, channel };
}

export const FIXED_TIME = new Date('2026-11-14T14:14:00');

export interface PageOptions {
  width: number;
  height: number;
  scale?: number;
  theme?: 'light' | 'dark';
  reducedMotion?: 'no-preference' | 'reduce';
  forcedColors?: 'none' | 'active';
}

export interface OpenedPage {
  context: BrowserContext;
  page: Page;
  errors: string[];
}

/** The theme each page was opened to show, so `load` can say when the page did not take it. */
const themes = new WeakMap<Page, 'light' | 'dark'>();

export async function openPage(browser: Browser, { width, height, scale = 1, theme = 'dark', reducedMotion = 'no-preference', forcedColors = 'none' }: PageOptions): Promise<OpenedPage> {
  const context = await browser.newContext({
    viewport: { width, height },
    deviceScaleFactor: scale,
    colorScheme: theme,
    reducedMotion,
    // 'active' is a system contrast theme (Windows "Contrast themes"): the page's colours are
    // replaced by the system's few, and box-shadow focus rings and background-only shapes vanish.
    forcedColors,
    locale: 'en-US',
    timezoneId: 'America/Chicago',
  });
  // "Copy details" writes to the clipboard. A headless browser may share the machine's
  // clipboard, which belongs to the person using it (build 2 overwrote it once): the write
  // is caught here instead, and the checks read what would have been copied from
  // window.__copied.
  // The page chooses its theme from the saved choice, never from the system's setting (D-020), so a picture or an audit run
  // "in the light theme" has to save that choice first. Setting only the colour scheme of the browser (as qa/shots.ts and
  // qa/audit.ts did until S2V-031) photographed and audited the dark theme twice: the light pictures were the dark ones.
  await context.addInitScript((chosen: string) => {
    try {
      // Dark is what a page with no saved choice starts in; a choice made later in the run (the toggle) is kept across a reload.
      if (chosen === 'light' && localStorage.getItem('app.theme') === null) localStorage.setItem('app.theme', chosen);
    } catch {
      // The page then starts dark, and the theme check in openPage's callers says so.
    }
  }, theme);
  await context.addInitScript(() => {
    window.__copied = [];
    const capture = async (text: unknown): Promise<void> => {
      window.__copied.push(String(text));
    };
    try {
      Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: capture, readText: async () => window.__copied.at(-1) ?? '' } });
    } catch {
      // The page then takes its own fallback, which is caught below.
    }
    document.execCommand = (command: string): boolean => {
      if (command === 'copy') window.__copied.push(String(document.getSelection() ?? ''));
      return command === 'copy';
    };
  });
  const page = await context.newPage();
  themes.set(page, theme);
  await page.clock.setFixedTime(FIXED_TIME);
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text());
  });
  return { context, page, errors };
}

/** Opens the app on a fixture of the stand-in bridge (src/bridge.fake.ts), with options ("platform=macos"). */
export async function load(page: Page, base: string, fixture = 'default', options = ''): Promise<void> {
  await page.goto(`${base}/#fixture=${fixture}${options ? `&${options}` : ''}`);
  await page.waitForSelector('.app');
  await page.evaluate(() => document.fonts.ready);
  // A run that says "light" and shows dark proves nothing about the light theme (S2V-031: it happened for a whole ticket).
  const wanted = themes.get(page);
  const shown = await page.evaluate(() => document.documentElement.dataset.theme);
  if (wanted && shown !== wanted && !options.includes('theme=')) throw new Error(`the page was opened for the ${wanted} theme and shows the ${shown} theme`);
}

/** Calls the page made to the stand-in bridge, by name. */
export const calls = (page: Page, name: string): Promise<DesktopCall[]> => page.evaluate((n) => (window.__desktopCalls ?? []).filter((c) => c.name === n), name);

/** The modifier for a platform's key family: Meta on macOS, Control elsewhere. */
export const modFor = (platform: string): 'Meta' | 'Control' => (platform === 'macos' ? 'Meta' : 'Control');

export async function park(page: Page): Promise<void> {
  // Park the pointer on the empty title bar so nothing shows a hover state.
  const viewport = page.viewportSize();
  await page.mouse.move(Math.min(300, (viewport?.width ?? 300) - 8), 4);
}

/** Resolves when no CSS transition or animation is running (spinners excepted). */
export async function settle(page: Page): Promise<void> {
  await page.waitForFunction(
    () => document.getAnimations().every((a) => a.effect?.getComputedTiming().iterations === Infinity || a.playState !== 'running'),
    null,
    { timeout: 5000 },
  );
  // A dialog or the palette fades in from a starting style on the frame after it opens, which `getAnimations` does not list until
  // then: a contrast check taken mid-fade saw a colour at 90% opacity and failed one run in two (S2V-031). Wait for it to be whole.
  await page.waitForFunction(() => [...document.querySelectorAll('.dialog, .palette, .scrim')].every((el) => getComputedStyle(el).opacity === '1' && !el.hasAttribute('data-starting-style')), null, { timeout: 5000 });
  await page.waitForTimeout(60);
}
