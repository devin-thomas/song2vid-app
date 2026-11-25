// Audits the production build headlessly and writes qa/audit.json.
// Exits 1 with the failures printed when any gate fails.
//
// Gates (the premium-bar rule each one checks is in brackets). Every state is
// opened on a fixture of the stand-in bridge (src/bridge.fake.ts), so no shell,
// no tool and no window is involved; the browser is headless and muted.
//   css        no `transition: all`, no animated layout property, nothing over 300 ms
//              except a sheet (450 ms), read from the shipped stylesheets [13, 14, 15]
//   motion     the same limits on animations that actually ran; popovers grow from their
//              trigger; no motion for keyboard actions; no transform motion under
//              prefers-reduced-motion [13, 15, 18, 20, 22]
//   list       no list over 50 rows is drawn: Song2Vid has none (rules 25 and 26 are N/A, so the gate
//              checks the page never grows one) [26]
//   axe        zero violations in both themes, every state [37]
//   focus      every keyboard-focusable element changes appearance on focus [5]
//   names      every interactive element has an accessible name that contains its visible
//              label [36]
//   text       no text under 12 px [31]
//   language   no banned term (qa/banned-terms.json), matched as a whole word, in any text
//              a person can read, Details and About included [49]
//   buttons    no filled button reads Details, Show details or OK [73]
//   desktop    nothing that reads as a web form: no native range, select, number, checkbox
//              or radio input, no title tooltip, no pointer cursor, no capitals or
//              letter-spaced label, no blur, glow or gradient, no slogan heading [80]
//   clipped    a scroll area that hides content shows a fading edge or a scrollbar [38]
//   overflow   nothing outside the window at the app's default and minimum window size
//              (app.config.json), 125% scale and 200% zoom [38]
//   spill      nothing a person operates spills out of its region or the window, regions do
//              not overlap, and the window has no scroll range; a root with hidden overflow
//              does not pass this by hiding the spill [81]
//   stable     at each of those sizes, the title bar, the work area and the status bar sit in
//              the same place in every state, and the status bar has one height [74]
//   restore    the Codec survives a reload and corrupt storage; a remembered HEVC starts on H.264 on a
//              computer that cannot make it and comes back where it can [23, 44, page level only]
//   journeys   each journey in qa/journeys.json runs by keyboard alone within its step
//              budget, once with Ctrl (Windows and Linux) and once with Command (macOS) [6, 47]
//   shortcuts  every command is in the palette with its shortcut written as the system writes
//              it, tooltips show shortcuts, and each shortcut works on both key families [46]
//   overlay    keys typed straight after the key that opens an overlay land in it [6]
//   forced     under a system contrast theme (forced colours), on a light and a dark system,
//              every keyboard-focusable element in every state still changes on focus [109]
//   tokens     no colour literal or palette colour in src/ outside the token layer, and every
//              theme defines the same colour names [110]
//   job        cancel is acknowledged at once; each row of SPEC 27.5's table says its sentence and its
//              filled button can succeed for its cause; "Copy Details" copies the developer text
//              without showing it, into a clipboard the audit captures (never the machine's);
//              progress never goes back and time left follows its rules [50, 58, 65, 66, 69]
//   crop       the crop follows the pointer in the same frame, the arrow keys step 5% and 25% with
//              Shift, and the control reads as a slider with its value text [75, 67]
//   files      a drop fills empty slots at once, asks before replacing (Keep Current is the default,
//              Esc keeps, focus comes back), is refused while a video is made, and a rejected drop
//              changes nothing [4a, 88]
//   tool       a tool that is missing, or turns out wrong after launch, is the one blocking state [59]
//   notices    the banned-terms gate leaves out the third-party notices text and nothing else [49, 64]
//
// The states are in qa/states.ts (one list for this audit and for qa/shots.ts); the journey scripts,
// shortcut effects and job fixtures below are Song2Vid's.
import { AxeBuilder } from '@axe-core/playwright';
import { readdirSync, readFileSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { Page } from 'playwright-core';
import { launch, load, openPage, park, readConfig, root, serve, settle } from './lib.ts';
import type { MotionRecord, PageOptions } from './lib.ts';
import { AUDITED, PICTURE, SONG, STATES, cropValue, drop, fill, make, openPalette, pickCodec, pickShape, waitStatus } from './states.ts';
import type { Mod } from './states.ts';

/** One entry of qa/journeys.json. */
interface Journey {
  id: string;
  name: string;
  stepBudget: number;
}
/** qa/journeys.json: the essential journeys, and the commands that have no shortcut and why. */
interface JourneysFile {
  journeys: Journey[];
  commandsWithoutShortcut: { label: string; reason: string }[];
}
/** qa/banned-terms.json: words matched as whole words (any case), and words matched exactly. */
interface BannedTerms {
  terms: string[];
  exact: string[];
}

const config = readConfig();
const journeys = (JSON.parse(readFileSync(join(root, 'qa', 'journeys.json'), 'utf8')) as JourneysFile).journeys;
const termsFile = JSON.parse(readFileSync(join(root, 'qa', 'banned-terms.json'), 'utf8')) as Partial<BannedTerms>;
const bannedTerms: BannedTerms = { terms: termsFile.terms ?? [], exact: termsFile.exact ?? [] };
// The app's own default and minimum window, 125% scale of the default, and 200% zoom of the
// default (build 2: sizes chosen by the audit instead of the app missed the app's real minimum).
const W = config.window;
const SIZES: [label: string, options: PageOptions][] = [
  [`${W.width}x${W.height} default`, { width: W.width, height: W.height, scale: 1 }],
  [`${W.minWidth}x${W.minHeight} minimum`, { width: W.minWidth, height: W.minHeight, scale: 1 }],
  [`${W.width}x${W.height} at 125% scale`, { width: W.width, height: W.height, scale: 1.25 }],
  [`${W.width}x${W.height} at 200% zoom`, { width: Math.round(W.width / 2), height: Math.round(W.height / 2), scale: 2 }],
];
const VIEW: PageOptions = { width: W.width, height: W.height, scale: 1 };
const PREFS_KEY = `${config.storagePrefix}.preferences.v1`;

interface CssDeclaration {
  selector: string;
  name: string;
  raw: string;
  value: string;
  loops?: boolean;
}
interface MotionGate {
  pointer: Record<string, string[]>;
  keyboard: Record<string, string[]>;
  reducedMotion: { ran?: string[] };
  tooltipTransformOrigin?: { x: number; y: number; width: number; height: number };
}
interface AxeState {
  violations: { id: string; impact: string | null | undefined; nodes: number; first: string | undefined }[];
  incomplete: string[];
  passes: number;
}
type Geometry = Record<string, number[] | null>;
interface ShortcutResult {
  commands: number;
  withShortcut: number;
  worked: string[];
  tooltipShowsKeys?: boolean;
}
type JobGate = { cancelAcknowledged?: string | null | undefined; secondFailure?: { text: string; filled: string[] } } & Record<string, unknown>;
/** What the audit writes to qa/audit.json: one entry per gate that ran, in the shape the gate reports. */
interface Gates {
  css?: { selfTest: string; declarationsRead: number; longestMs: number; longestSheetMs: number; violations: string[] };
  motion?: MotionGate;
  list?: { notApplicable: string; rowsSeen: number };
  axe?: { statesChecked: number; violations: number; incompleteRules: string[]; byState: Record<string, AxeState> };
  text?: { smallestTextPx: number };
  focus?: { focusableElementsChecked: number };
  names?: { interactiveElementsChecked: number };
  language?: { bannedTerms: number };
  desktop?: { statesChecked: number };
  overflow?: Record<string, { scrollWidth: number; clientWidth: number; outside: number; spill: number }>;
  stable?: { sizes: string[]; anchors: string[]; statesPerSize: number };
  restore?: { restoredAfterReload: boolean; survivesCorruptStorage: boolean; hevcStartsOnH264Where: boolean; hevcComesBack: boolean };
  journeys?: Record<string, { name: string; steps: number; stepBudget: number; passed: boolean }>;
  shortcuts?: Record<string, ShortcutResult>;
  forced?: { stateAndThemeRuns: number; focusableElementsChecked: number };
  tokens?: { filesRead: number; linesRead: number; themes: string[]; contrasts: Record<string, number> };
  overlay?: Record<string, { query: string | null; body: string }>;
  job?: JobGate;
  crop?: Record<string, unknown>;
  files?: Record<string, unknown>;
  tool?: Record<string, unknown>;
  notices?: Record<string, unknown>;
  theme?: Record<string, unknown>;
  distinct?: Record<string, unknown>;
  messages?: Record<string, unknown>;
  ring?: Record<string, unknown>;
}
interface Report {
  generatedFor: string;
  browser?: { channel: string; version: string };
  gates: Gates;
  info?: { targetsUnder24px: string[] };
  failures?: string[];
  passed?: boolean;
}

const failures: string[] = [];
const report: Report = { generatedFor: 'dist/page/', gates: {} };
const fail = (gate: string, message: string) => failures.push(`[${gate}] ${message}`);

const { url, close } = await serve();
const { browser, channel } = await launch();
report.browser = { channel, version: browser.version() };

// ---------------------------------------------------------------- states ---

async function inState<T>(name: string, options: PageOptions, run: (page: Page) => Promise<T>): Promise<T> {
  const { context, page, errors } = await openPage(browser, options);
  try {
    const state = STATES[name];
    if (!state) throw new Error(`no state named ${name}`);
    await load(page, url, state.fixture, state.extra ?? '');
    await state.run(page, 'Control');
    await park(page);
    await settle(page);
    return await run(page);
  } finally {
    if (errors.length) fail('page', `${name}: ${errors.join(' | ')}`);
    await context.close();
  }
}

// ------------------------------------------------------------------ css ---

const LAYOUT = [
  'width', 'height', 'min-width', 'min-height', 'max-width', 'max-height', 'top', 'right', 'bottom', 'left', 'inset',
  'margin', 'padding', 'border-width', 'font-size', 'line-height', 'flex-basis', 'gap', 'grid-template-columns',
];

async function cssGate() {
  const { context, page } = await openPage(browser, { width: 1280, height: 800 });
  await load(page, url);
  const rules = await page.evaluate(() => {
    const rootStyle = getComputedStyle(document.documentElement);
    const resolve = (text: string): string => {
      let out = text;
      for (let i = 0; i < 6 && out.includes('var('); i++) {
        out = out.replace(/var\(\s*(--[\w-]+)\s*(?:,[^()]*)?\)/g, (_: string, name: string) => rootStyle.getPropertyValue(name).trim() || '0s');
      }
      return out;
    };
    const found: CssDeclaration[] = [];
    const walk = (list: CSSRuleList, prefix: string): void => {
      for (const rule of [...list] as (CSSStyleRule & CSSGroupingRule)[]) {
        const selector = rule.selectorText ? rule.selectorText.replaceAll('&', prefix || '') : prefix;
        if (rule.style) {
          const loops = rule.style.getPropertyValue('animation-iteration-count') === 'infinite';
          for (const name of ['transition', 'transition-property', 'transition-duration', 'animation', 'animation-duration']) {
            const value = rule.style.getPropertyValue(name);
            if (value) found.push({ selector: selector || rule.cssText.slice(0, 40), name, raw: value, value: resolve(value), loops });
          }
        }
        if (rule.cssRules?.length) walk(rule.cssRules, selector);
      }
    };
    for (const sheet of document.styleSheets) walk(sheet.cssRules, '');
    return found;
  });
  await context.close();

  const splitTop = (text: string): string[] => {
    const parts: string[] = [];
    let depth = 0;
    let current = '';
    for (const ch of text) {
      if (ch === '(') depth++;
      if (ch === ')') depth--;
      if (ch === ',' && depth === 0) {
        parts.push(current.trim());
        current = '';
      } else current += ch;
    }
    if (current.trim()) parts.push(current.trim());
    return parts;
  };
  const toMs = (token: string) => (token.endsWith('ms') ? parseFloat(token) : parseFloat(token) * 1000);
  const times = (segment: string) => (segment.replace(/\([^()]*\)/g, '').match(/(?<![\w.-])\d*\.?\d+m?s\b/g) ?? []).map(toMs);

  let longest = 0;
  let longestSheet = 0;
  let violations: string[] = [];
  const real = rules.length;
  // Three planted rules prove the classifier works; they are removed again below.
  rules.push(
    { selector: '.planted-a', name: 'transition', raw: 'all 1s', value: 'all 1s' },
    { selector: '.planted-b', name: 'transition', raw: 'height .2s', value: 'height .2s' },
    { selector: '.planted-c', name: 'animation-duration', raw: '.5s', value: '.5s' },
  );
  for (const rule of rules) {
    const isSheet = /\.sheet\b/.test(rule.selector);
    const segments = splitTop(rule.value);
    if (rule.name === 'transition' || rule.name === 'transition-property') {
      for (const segment of segments) {
        const property = segment.split(/\s+/)[0] ?? '';
        if (property === 'all') violations.push(`${rule.selector} { ${rule.name}: ${rule.raw} } uses "all"`);
        if (LAYOUT.some((p) => property === p || property.startsWith(`${p}-`))) {
          violations.push(`${rule.selector} animates layout property ${property}`);
        }
      }
    }
    if (rule.name === 'transition-property') continue;
    const infinite = rule.loops || /\binfinite\b/.test(rule.value);
    for (const segment of segments) {
      const all = times(segment);
      const duration = rule.name.endsWith('duration') ? Math.max(0, ...all) : (all[0] ?? 0);
      if (infinite) continue; // spinner loop, reported under motion
      if (!rule.selector.startsWith('.planted-')) {
        if (isSheet) longestSheet = Math.max(longestSheet, duration);
        else longest = Math.max(longest, duration);
      }
      if (duration > (isSheet ? 450 : 300)) {
        violations.push(`${rule.selector} { ${rule.name}: ${rule.raw} } runs ${duration} ms`);
      }
    }
  }
  const planted = violations.filter((v) => v.includes('.planted-'));
  if (planted.length !== 4) fail('audit', `css self-test caught ${planted.length} of 4 planted violations`);
  violations = violations.filter((v) => !v.includes('.planted-'));
  report.gates.css = {
    selfTest: `${planted.length} of 4 planted violations caught`,
    declarationsRead: real,
    longestMs: longest,
    longestSheetMs: longestSheet,
    violations,
  };
  violations.forEach((v) => fail('css', v));
}

// --------------------------------------------------------------- motion ---

const RECORDER = (): void => {
  window.__seen = new WeakSet();
  window.__motion = [];
  const describe = (el: Element | null): string => {
    if (!el) return 'unknown';
    const cls = typeof el.className === 'string' ? el.className.split(/\s+/).filter(Boolean).slice(0, 3).join('.') : '';
    return `${el.tagName.toLowerCase()}${cls ? `.${cls}` : ''}`;
  };
  const tick = () => {
    for (const animation of document.getAnimations()) {
      if (window.__seen.has(animation)) continue;
      window.__seen.add(animation);
      const effect = animation.effect as KeyframeEffect | null;
      const timing: ComputedEffectTiming = effect?.getComputedTiming?.() ?? {};
      const target = effect?.target ?? null;
      let properties: string[] = [];
      try {
        properties = [...new Set((effect as KeyframeEffect).getKeyframes().flatMap((k) => Object.keys(k)))].filter(
          (k) => !['offset', 'easing', 'composite', 'computedOffset'].includes(k),
        );
      } catch {
        properties = [];
      }
      window.__motion.push({
        kind: animation.constructor.name,
        name: (animation as Animation & { transitionProperty?: string; animationName?: string }).transitionProperty ?? (animation as Animation & { animationName?: string }).animationName ?? 'script',
        properties,
        duration: Number(timing.duration) || 0,
        iterations: timing.iterations === Infinity ? 'infinite' : timing.iterations,
        target: describe(target),
        inSheet: Boolean(target?.closest?.('.sheet')),
      });
    }
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
};

const drain = (page: Page): Promise<MotionRecord[]> =>
  page.evaluate(() => {
    const out = window.__motion;
    window.__motion = [];
    return out;
  });

const LAYOUT_JS = ['width', 'height', 'top', 'left', 'right', 'bottom', 'margin', 'padding', 'fontSize', 'inset'];
// Endless animations that are allowed: the spinner, and the scroll-driven fade at the end of a scroll area.
const ENDLESS_OK = ['spin', 'scroll-cue'];

function judge(records: MotionRecord[], label: string): string[] {
  const violations: string[] = [];
  for (const r of records) {
    const props = r.properties.length ? r.properties : [r.name];
    if (r.iterations === 'infinite' || ENDLESS_OK.includes(r.name)) {
      if (!ENDLESS_OK.includes(r.name)) violations.push(`${label}: endless animation ${r.name} on ${r.target}`);
      continue;
    }
    const limit = r.inSheet ? 450 : 300;
    if (r.duration > limit) violations.push(`${label}: ${r.name} on ${r.target} runs ${r.duration} ms (limit ${limit})`);
    for (const p of props) {
      if (LAYOUT_JS.some((l) => p === l || p.startsWith(l))) violations.push(`${label}: layout property ${p} animates on ${r.target}`);
    }
  }
  return violations;
}

async function motionGate() {
  const out: MotionGate = { pointer: {}, keyboard: {}, reducedMotion: {} };
  const themeButton = '[aria-label="Use the dark theme"], [aria-label="Use the light theme"]';

  // Pointer session: everything a mouse user triggers.
  {
    const { context, page } = await openPage(browser, { width: 1280, height: 800 });
    await page.addInitScript(RECORDER);
    await load(page, url);
    await fill(page);
    await drain(page);
    const steps: [string, () => Promise<void>][] = [
      ['hover and press a button', async () => {
        await page.hover('#choose-audio');
        await page.mouse.down();
        await page.waitForTimeout(160);
        await page.mouse.move(300, 4);
        await page.mouse.up();
        await page.waitForTimeout(250);
      }],
      ['tooltip', async () => {
        await page.hover(themeButton);
        await page.waitForTimeout(800);
        await page.mouse.move(300, 4);
        await page.waitForTimeout(200);
      }],
      ['choose a Frame Shape and a Codec', async () => {
        await pickShape(page, '1:1');
        await page.waitForTimeout(300);
        await pickCodec(page, 'hevc');
        await page.waitForTimeout(300);
      }],
      ['drag the crop', async () => {
        const box = await page.locator('[role="slider"]').boundingBox();
        if (!box) throw new Error('the crop control is not on the page');
        await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
        await page.mouse.down();
        await page.mouse.move(box.x + box.width / 2 + 40, box.y + box.height / 2, { steps: 4 });
        await page.mouse.up();
        await page.waitForTimeout(250);
      }],
      ['open and close a dialog', async () => {
        await page.getByRole('button', { name: /Commands/ }).click();
        await page.waitForSelector('.palette');
        await page.getByRole('option', { name: /^About/ }).click();
        await page.waitForSelector('[data-about]');
        await page.waitForTimeout(350);
        await page.getByRole('button', { name: 'Close' }).click();
        await page.waitForTimeout(350);
      }],
      ['make a video', async () => {
        await page.locator('#make-video').click();
        await waitStatus(page, 'done', 8000);
        await page.waitForTimeout(300);
      }],
    ];
    for (const [label, run] of steps) {
      await run();
      const records = await drain(page);
      out.pointer[label] = records.map((r) => `${r.name} ${r.duration}ms on ${r.target}`);
      judge(records, `pointer/${label}`).forEach((v) => fail('motion', v));
    }
    await context.close();
  }

  // Popovers animate from their trigger: the origin must not be the centre.
  {
    const { context, page } = await openPage(browser, { width: 1280, height: 800 });
    await load(page, url);
    await page.hover(themeButton);
    await page.waitForSelector('.tooltip');
    const origin = await page.evaluate(() => {
      const popup = document.querySelector('.tooltip') as Element;
      const box = popup.getBoundingClientRect();
      const [x = NaN, y = NaN] = getComputedStyle(popup).transformOrigin.split(' ').map(parseFloat);
      return { x, y, width: box.width, height: box.height };
    });
    out.tooltipTransformOrigin = origin;
    const centred = Math.abs(origin.x - origin.width / 2) < 2 && Math.abs(origin.y - origin.height / 2) < 2;
    if (centred) fail('motion', 'the tooltip animates from its centre, not from its trigger');
    await context.close();
  }

  // Keyboard session: actions started from the keyboard must not animate.
  {
    const { context, page } = await openPage(browser, { width: 1280, height: 800 });
    await page.addInitScript(RECORDER);
    await load(page, url);
    await page.locator('#choose-audio').focus();
    await drain(page);
    const steps: [string, () => Promise<void>][] = [
      ['Ctrl+K opens the palette', async () => {
        await openPalette(page);
        await page.waitForTimeout(200);
      }],
      ['arrow keys move through commands', async () => {
        for (let i = 0; i < 4; i++) await page.keyboard.press('ArrowDown');
        await page.waitForTimeout(150);
        await page.keyboard.press('Escape');
        await page.waitForTimeout(200);
      }],
      ['Ctrl+O and Ctrl+Shift+O choose the files', async () => {
        await fill(page);
        await page.waitForTimeout(300);
      }],
      ['arrow keys choose a Frame Shape, a Resolution and a Codec', async () => {
        await page.locator('[data-group="shape"] [aria-checked="true"]').focus();
        await page.keyboard.press('ArrowRight');
        await page.keyboard.press('ArrowRight');
        await page.keyboard.press('Tab');
        await page.keyboard.press('ArrowRight');
        await page.keyboard.press('Tab');
        await page.keyboard.press('ArrowRight');
        await page.waitForTimeout(300);
      }],
      ['arrow keys move the crop', async () => {
        await page.locator('[role="slider"]').focus();
        for (let i = 0; i < 5; i++) await page.keyboard.press('ArrowLeft');
        await page.keyboard.press('Shift+ArrowRight');
        await page.waitForTimeout(200);
      }],
      ['Ctrl+Enter makes the video', async () => {
        await make(page);
        await waitStatus(page, 'done', 8000);
        await page.waitForTimeout(300);
      }],
    ];
    for (const [label, run] of steps) {
      await run();
      // Wait indicators (skeleton, spinner) are exempt: their delayed appearance is a timing rule.
      const records = (await drain(page)).filter(
        (r) => r.iterations !== 'infinite' && !ENDLESS_OK.includes(r.name) && r.duration > 0 && !/skeleton|spinner/.test(r.target),
      );
      out.keyboard[label] = records.map((r) => `${r.name} ${r.duration}ms on ${r.target}`);
      if (records.length) fail('motion', `keyboard/${label}: ${records.length} animation(s) ran: ${out.keyboard[label].join(', ')}`);
    }
    await context.close();
  }

  // Reduced motion: opacity may fade; transforms must not animate.
  {
    const { context, page } = await openPage(browser, { width: 1280, height: 800, reducedMotion: 'reduce' });
    await page.addInitScript(RECORDER);
    await load(page, url);
    await fill(page);
    await drain(page);
    await page.hover(themeButton);
    await page.waitForTimeout(700);
    await pickShape(page, '4:3');
    await page.waitForTimeout(300);
    await page.getByRole('button', { name: /Commands/ }).click();
    await page.waitForSelector('.palette');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
    const records = (await drain(page)).filter((r) => r.duration > 0);
    out.reducedMotion.ran = records.map((r) => `${r.name} ${r.duration}ms on ${r.target}`);
    const moving = records.filter((r) => [r.name, ...r.properties].some((p) => /transform|translate|scale|rotate/.test(p)));
    moving.forEach((r) => fail('motion', `reduced motion: ${r.name} still animates on ${r.target}`));
    await context.close();
  }

  report.gates.motion = out;
}

// ----------------------------------------------------------------- list ---

async function listGate() {
  // Song2Vid has no list (SPEC 28: rules 25 and 26 are N/A). This keeps it that way: no state draws a list of
  // more than 50 rows without the page being given a virtualised list and the rules back.
  const { context, page } = await openPage(browser, { width: 1280, height: 800 });
  await load(page, url);
  await fill(page);
  const rowsSeen = await page.evaluate(() => document.querySelectorAll('[role="option"], li, [data-row]').length);
  await context.close();
  report.gates.list = { notApplicable: 'Song2Vid has no list (SPEC 28: rules 25 and 26 are N/A)', rowsSeen };
  if (rowsSeen > 50) fail('list', `${rowsSeen} rows are drawn: a list over 50 rows must be virtualised (rule 26) and its scroll measured (rule 25)`);
}

// -------------------------------------------------- per-state page checks ---

/** An element a person operates, with the two properties only some controls have. */
type Control = HTMLElement & { disabled?: boolean; labels?: NodeListOf<HTMLLabelElement> | null };

const PAGE_CHECKS = async (terms: BannedTerms) => {
  const frames = () => new Promise<void>((r) => requestAnimationFrame(() => requestAnimationFrame(() => r())));
  const visible = (el: Element): boolean => {
    if (el.closest('[inert]')) return false;
    const style = getComputedStyle(el);
    if (style.visibility === 'hidden' || style.display === 'none') return false;
    const box = el.getBoundingClientRect();
    return box.width > 0 && box.height > 0;
  };
  const describe = (el: Element): string => {
    const id = el.id ? `#${el.id}` : '';
    const cls = typeof el.className === 'string' ? el.className.split(/\s+/).filter(Boolean).slice(0, 2).join('.') : '';
    const label = el.getAttribute('aria-label') ?? el.textContent?.trim().slice(0, 30) ?? '';
    return `${el.tagName.toLowerCase()}${id}${cls ? `.${cls}` : ''} "${label}"`;
  };

  // -- text size
  const small: string[] = [];
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let smallest = Infinity;
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    if (!(node.textContent ?? '').trim()) continue;
    const el = node.parentElement;
    if (!el || !visible(el) || el.closest('script,style')) continue;
    const size = parseFloat(getComputedStyle(el).fontSize);
    smallest = Math.min(smallest, size);
    if (size < 12) small.push(`${describe(el)} at ${size}px`);
  }

  // -- plain language: no banned term in any text a person can read, Details and About
  //    included. Developer text is never on screen; "Copy details" copies it without showing it.
  //    Whole words only: "rate" must not match "generate", nor "lab" "available" (build 2 found
  //    the substring match gave false hits).
  const banned: string[] = [];
  if (terms.terms.length || terms.exact.length) {
    const escape = (t: string) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const whole = (list: string[], flags: string) => (list.length ? new RegExp(`(?<![\\p{L}\\p{N}])(?:${list.map(escape).join('|')})(?![\\p{L}\\p{N}])`, flags) : null);
    const loose = whole(terms.terms, 'iu');
    const exact = whole(terms.exact, 'u');
    const BANNED = { test: (text: string) => Boolean(loose?.test(text) || exact?.test(text)) };
    const words = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let node = words.nextNode(); node; node = words.nextNode()) {
      const el = node.parentElement;
      if (!el || !visible(el) || el.closest('script,style')) continue;
      // The one exemption (SPEC 27.5, 27.8): About's third-party notices name the program that does the work. Only the element
      // that carries them is left out; the heading above them, the buttons and every other word stay covered.
      if (el.closest('[data-notices]')) continue;
      if (BANNED.test(node.textContent ?? '')) banned.push(`"${(node.textContent ?? '').trim().slice(0, 70)}"`);
    }
    for (const el of document.querySelectorAll('[placeholder],[aria-label]')) {
      if (!visible(el)) continue;
      const text = `${el.getAttribute('placeholder') ?? ''} ${el.getAttribute('aria-label') ?? ''}`;
      if (BANNED.test(text)) banned.push(`attribute "${text.trim()}"`);
    }
  }

  // -- no filled button that only reveals or dismisses (critique of builds 1 and 2)
  const filledWrong: string[] = [];
  for (const el of document.querySelectorAll('.btn-primary, [data-filled]')) {
    if (!visible(el)) continue;
    const text = (el.textContent ?? '').trim();
    if (/^(show |hide )?details$|^ok$/i.test(text)) filledWrong.push(`${describe(el)} is a filled button reading "${text}"`);
  }

  // -- what makes a web page of a desktop app (a finding of build 2's research)
  const webForm: string[] = [];
  for (const el of document.querySelectorAll('select, input[type="range"], input[type="number"], input[type="checkbox"], input[type="radio"], [title]')) {
    if (visible(el) && !el.closest('svg')) webForm.push(`${describe(el)} is a native form control or carries a title tooltip`);
  }
  for (const el of document.body.querySelectorAll('*')) {
    if (!visible(el)) continue;
    const st = getComputedStyle(el);
    if (st.cursor === 'pointer') webForm.push(`${describe(el)} has a pointer cursor`);
    if (st.backdropFilter && st.backdropFilter !== 'none') webForm.push(`${describe(el)} blurs what is behind it`);
    if (/gradient/.test(st.backgroundImage)) webForm.push(`${describe(el)} has a gradient background`);
    const own = [...el.childNodes].some((n) => n.nodeType === 3 && (n.textContent ?? '').trim().length > 1);
    if (!own) continue;
    if (st.textTransform === 'uppercase') webForm.push(`${describe(el)} is set in capitals`);
    if (parseFloat(st.letterSpacing) > parseFloat(st.fontSize) * 0.04) webForm.push(`${describe(el)} is letter-spaced like a label above a heading`);
    if (/^h[1-6]$/i.test(el.tagName) && /[.!?]\s+\S|, not /.test((el.textContent ?? '').trim())) webForm.push(`heading "${(el.textContent ?? '').trim().slice(0, 50)}" reads as a slogan`);
  }

  // What a person can see of an element is what its clipping ancestors leave of it: a picture placed past the edge of
  // the frame that holds it (the crop) is cut by the frame, not outside the window.
  const shown = (el: Element): DOMRect => {
    let box = el.getBoundingClientRect();
    for (let up = el.parentElement; up && up !== document.body; up = up.parentElement) {
      const style = getComputedStyle(up);
      if (style.overflowX === 'visible' && style.overflowY === 'visible') continue;
      const clip = up.getBoundingClientRect();
      box = new DOMRect(Math.max(box.left, clip.left), Math.max(box.top, clip.top), Math.max(0, Math.min(box.right, clip.right) - Math.max(box.left, clip.left)), Math.max(0, Math.min(box.bottom, clip.bottom) - Math.max(box.top, clip.top)));
    }
    return box;
  };
  // -- a scroll area that hides content must show it: a visible scrollbar, or the cue the page draws ("More below", a real element).
  //    A fade made with a mask is not a cue: it was always "present" in the style, vanished in a picture, and let whole rows of the
  //    card sit out of sight at 200% zoom with nothing to say so (S2V-031, the critic's must-fix 2). Headless browsers hide scrollbars,
  //    so in these runs the cue is what is checked; a scrollbar counts where the browser draws one.
  const clipped: string[] = [];
  const unreachable: string[] = [];
  for (const el of document.querySelectorAll<HTMLElement>('*')) {
    if (!visible(el)) continue;
    const style = getComputedStyle(el);
    if (!/auto|scroll/.test(style.overflowY) || el.scrollHeight <= el.clientHeight + 1) continue;
    if (el.matches('textarea')) continue; // native text scrolling
    const atEnd = el.scrollTop + el.clientHeight >= el.scrollHeight - 1;
    const hasBar = el.offsetWidth - el.clientWidth > 0;
    const next = el.nextElementSibling;
    const cue = next instanceof HTMLElement && next.hasAttribute('data-scroll-cue') && visible(next);
    if (!atEnd && !hasBar && !cue) clipped.push(`${describe(el)} hides ${el.scrollHeight - el.clientHeight}px with no cue`);
    // Every control inside it can be brought into view by scrolling (the keyboard does the same by focusing it).
    const port = el.getBoundingClientRect();
    const before = el.scrollTop;
    for (const control of el.querySelectorAll<HTMLElement>('button, a[href], [tabindex], input, select, textarea, [role="option"]')) {
      if (!visible(control) || (control as HTMLButtonElement).disabled) continue;
      control.scrollIntoView({ block: 'nearest' });
      const box = control.getBoundingClientRect();
      if (box.top < port.top - 1 || box.bottom > port.bottom + 1) unreachable.push(`${describe(control)} cannot be scrolled into view of ${describe(el)}`);
    }
    el.scrollTop = before;
  }

  // -- a label or a sentence cut off by its own box: the text of a button, a message, a note must be whole. Where a box has
  //    to cut (a file name in a row, which has its tooltip and keeps its ending) the cut is by the page's own two-part name.
  const truncated: string[] = [];
  const mayCut = (el: Element): boolean => el.classList.contains('file-head') || el.classList.contains('statusbar-layer') || el.closest('.statusbar-layer:not([data-live])') !== null;
  for (const el of document.body.querySelectorAll<HTMLElement>('*')) {
    if (!visible(el) || mayCut(el) || el.closest('svg') || el.closest('[data-notices]') || el.classList.contains('sr-only')) continue;
    const own = [...el.childNodes].some((n) => n.nodeType === 3 && (n.textContent ?? '').trim().length > 0);
    if (!own) continue;
    const style = getComputedStyle(el);
    const cuts = style.overflowX !== 'visible' || style.overflowY !== 'visible' || style.textOverflow === 'ellipsis' || /-webkit-box/.test(style.display);
    if (!cuts) continue;
    if (/auto|scroll/.test(style.overflowY) && el.scrollHeight > el.clientHeight) continue; // a scroll area, checked above
    if (el.scrollWidth > el.clientWidth + 1 || el.scrollHeight > el.clientHeight + 1) truncated.push(`${describe(el)} is cut off (${el.scrollWidth}x${el.scrollHeight} of ${el.clientWidth}x${el.clientHeight})`);
  }
  // A button's label whole inside the button, and the button whole inside what holds it.
  for (const button of document.querySelectorAll<HTMLElement>('button, .btn')) {
    if (!visible(button) || button.closest('.statusbar-layer:not([data-live])')) continue;
    if (button.scrollWidth > button.clientWidth + 1) truncated.push(`${describe(button)}: the label is wider than the button (${button.scrollWidth} > ${button.clientWidth})`);
    const box = button.getBoundingClientRect();
    const seen = shown(button);
    if (seen.width < box.width - 1 || seen.height < box.height - 1) {
      const inScroll = (() => {
        for (let up = button.parentElement; up && up !== document.body; up = up.parentElement) if (/auto|scroll/.test(getComputedStyle(up).overflowY)) return true;
        return false;
      })();
      if (!inScroll) truncated.push(`${describe(button)} is cut by what holds it (${Math.round(seen.width)}x${Math.round(seen.height)} of ${Math.round(box.width)}x${Math.round(box.height)})`);
    }
  }

  // -- accessible names and focus styles
  const interactive = [
    ...document.querySelectorAll<Control>(
      'button, a[href], input:not([type="hidden"]), select, textarea, [tabindex], [role="option"], [role="tab"], [role="combobox"], [role="listbox"]',
    ),
  ].filter(
    (el) =>
      visible(el) &&
      !el.disabled &&
      el.getAttribute('aria-disabled') !== 'true' &&
      // Base UI's focus guards are hidden sentinels, not controls.
      !el.hasAttribute('data-base-ui-focus-guard') &&
      el.getAttribute('aria-hidden') !== 'true',
  );

  const nameOf = (el: Control): string => {
    const labelledby = el.getAttribute('aria-labelledby');
    if (labelledby) {
      const text = labelledby.split(/\s+/).map((id) => document.getElementById(id)?.textContent ?? '').join(' ').trim();
      if (text) return text;
    }
    const aria = el.getAttribute('aria-label');
    if (aria?.trim()) return aria.trim();
    if (el.labels?.length) return [...el.labels].map((l) => l.textContent ?? '').join(' ').trim();
    if (el.matches('input, textarea, select')) return (el.getAttribute('title') ?? el.getAttribute('placeholder') ?? '').trim();
    return (el.textContent ?? '').trim() || (el.getAttribute('title') ?? '').trim();
  };
  const unnamed = interactive
    .filter((el) => !el.matches('[tabindex="-1"]:not(button):not([role])'))
    .filter((el) => !nameOf(el))
    .map(describe);
  // The accessible name contains the visible label (WCAG 2.5.3), so a person who says what
  // they see reaches the control by voice.
  const squash = (t: string) => t.replace(/\s+/g, ' ').trim().toLowerCase();
  const labelNotInName = interactive
    .filter((el) => el.matches('button, a[href], [role="option"], [role="tab"]') && el.hasAttribute('aria-label'))
    .filter((el) => {
      const shown = squash([...el.childNodes].filter((n) => n.nodeType === 3 || (n.nodeType === 1 && (n as Element).getAttribute('aria-hidden') !== 'true')).map((n) => n.textContent ?? '').join(' '));
      return shown && !squash(nameOf(el)).includes(shown);
    })
    .map(describe);

  // What a person could see change on focus: only paint that exists. An outline or border colour
  // counts only where a line is drawn (a colour on an outline of style none is not a change, and
  // under forced colours it is the only part of a ring that still shows).
  const signature = (el: HTMLElement): string => {
    const parts: string[] = [];
    let node: HTMLElement | null = el;
    for (let depth = 0; node && depth < 5; depth++, node = node.parentElement) {
      const s = getComputedStyle(node);
      const before = getComputedStyle(node, '::before');
      const outline = s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) > 0 ? `${s.outlineStyle} ${s.outlineWidth} ${s.outlineColor}` : 'no outline';
      const border = s.borderTopStyle !== 'none' && parseFloat(s.borderTopWidth) > 0 ? s.borderTopColor : 'no border';
      parts.push([outline, s.boxShadow, s.backgroundColor, border, before.backgroundColor].join('|'));
    }
    const active = el.getAttribute('aria-activedescendant');
    const activeEl = active ? document.getElementById(active) : el.querySelector?.('[data-active="true"]');
    if (activeEl) {
      const s = getComputedStyle(activeEl);
      parts.push([s.outlineStyle, s.outlineWidth, s.backgroundColor].join('|'));
    }
    return parts.join('\n');
  };

  const focusable = interactive.filter((el) => el.tabIndex >= 0);
  const previous = document.activeElement as HTMLElement | null;
  const noFocusStyle: string[] = [];
  const notFocusable: string[] = [];
  for (const el of focusable) {
    (document.activeElement as HTMLElement | null)?.blur?.();
    const before = signature(el);
    el.focus({ preventScroll: true });
    if (document.activeElement !== el) {
      notFocusable.push(describe(el));
      continue;
    }
    if (signature(el) === before) {
      // Some focus styles arrive with the next render (the list picks a visible row).
      await frames();
      if (signature(el) === before) noFocusStyle.push(describe(el));
    }
  }
  previous?.focus?.({ preventScroll: true });

  // -- target size (reported, not a gate)
  const smallTargets = interactive
    .filter((el) => el.matches('button, a[href], [role="option"], [role="tab"]'))
    .filter((el) => {
      const box = el.getBoundingClientRect();
      return box.width < 24 || box.height < 24;
    })
    .map((el) => {
      const box = el.getBoundingClientRect();
      return `${describe(el)} ${Math.round(box.width)}x${Math.round(box.height)}`;
    });

  // -- horizontal overflow
  const vw = document.documentElement.clientWidth;
  const outside: string[] = [];
  for (const el of document.body.querySelectorAll('*')) {
    if (!visible(el)) continue;
    const box = shown(el);
    if (box.right > vw + 1 || box.left < -1) outside.push(`${describe(el)} spans ${Math.round(box.left)}..${Math.round(box.right)} of ${vw}`);
  }
  const action = document.querySelector('[data-primary-action]');
  const actionBox = action?.getBoundingClientRect();

  // -- spill: nothing a person operates spills out of its region or the window, and regions
  //    do not overlap. A root with `overflow: hidden` makes "the window never scrolls" pass
  //    trivially (build 2), so this checks what is cut off rather than whether it scrolls.
  const vh = window.innerHeight;
  const spill: string[] = [];
  const REGIONS: [string, string][] = [
    ['.titlebar', '.titlebar button, .titlebar h1'],
    ['.card', '.card button, .card input, .card textarea, .card label'],
    ['[data-status-bar]', '[data-status-bar] button, [data-status-bar] p, [data-status-bar] [role="progressbar"]'],
  ];
  for (const [regionSelector, inside] of REGIONS) {
    const region = document.querySelector(regionSelector);
    if (!region || !visible(region)) continue;
    const r = region.getBoundingClientRect();
    if (r.top < -1 || r.left < -1 || r.bottom > vh + 1 || r.right > vw + 1) spill.push(`${regionSelector} spans ${Math.round(r.top)}..${Math.round(r.bottom)} of ${vh} high, ${Math.round(r.left)}..${Math.round(r.right)} of ${vw} wide`);
    for (const el of document.querySelectorAll(inside)) {
      if (!visible(el)) continue;
      let scroller = el.parentElement;
      while (scroller && scroller !== region && !/auto|scroll/.test(getComputedStyle(scroller).overflowY)) scroller = scroller.parentElement;
      if (scroller && scroller !== region && region.contains(scroller)) continue; // reached by scrolling
      const box = el.getBoundingClientRect();
      if (box.top < r.top - 1 || box.bottom > r.bottom + 1 || box.left < r.left - 1 || box.right > r.right + 1) spill.push(`${describe(el)} spills out of ${regionSelector} (${Math.round(box.top)}..${Math.round(box.bottom)} in ${Math.round(r.top)}..${Math.round(r.bottom)})`);
    }
  }
  const regions = ['.titlebar', '.workspace', '[data-status-bar]'].map((sel) => document.querySelector(sel)).filter((el): el is Element => el !== null && visible(el));
  for (let i = 0; i < regions.length; i++) {
    for (let j = i + 1; j < regions.length; j++) {
      const ra = regions[i];
      const rb = regions[j];
      if (!ra || !rb) continue;
      const a = ra.getBoundingClientRect();
      const b = rb.getBoundingClientRect();
      if (a.left < b.right - 1 && b.left < a.right - 1 && a.top < b.bottom - 1 && b.top < a.bottom - 1) spill.push(`${describe(ra)} overlaps ${describe(rb)}`);
    }
  }
  const scroller = document.scrollingElement ?? document.documentElement;
  return {
    smallestTextPx: smallest,
    smallText: small,
    banned,
    filledWrong,
    webForm: [...new Set(webForm)].slice(0, 12),
    clipped,
    unreachable,
    truncated,
    interactiveCount: interactive.length,
    focusableCount: focusable.length,
    unnamed,
    labelNotInName,
    noFocusStyle,
    notFocusable,
    smallTargets,
    scrollWidth: document.documentElement.scrollWidth,
    clientWidth: vw,
    outside: outside.slice(0, 12),
    spill,
    scrollRange: { x: scroller.scrollWidth - scroller.clientWidth, y: scroller.scrollHeight - scroller.clientHeight },
    primaryActionReachable: actionBox ? actionBox.bottom <= window.innerHeight + 1 && actionBox.right <= vw + 1 : null,
  };
};

async function stateGates() {
  const axe: Record<string, AxeState> = {};
  let smallest = Infinity;
  let focusableChecked = 0;
  let interactiveChecked = 0;
  const targets = new Set<string>();

  for (const theme of ['light', 'dark'] as const) {
    for (const name of AUDITED) {
      await inState(name, { ...VIEW, theme }, async (page) => {
        const result = await new AxeBuilder({ page }).analyze();
        axe[`${name}/${theme}`] = {
          violations: result.violations.map((v) => ({ id: v.id, impact: v.impact, nodes: v.nodes.length, first: v.nodes[0]?.target?.join(' ') })),
          incomplete: result.incomplete.map((v) => `${v.id} (${v.nodes.length})`),
          passes: result.passes.length,
        };
        for (const v of result.violations) {
          fail('axe', `${name}/${theme}: ${v.id} (${v.impact}) on ${v.nodes.length} node(s), first ${v.nodes[0]?.target?.join(' ')}: ${v.nodes[0]?.failureSummary?.split('\n')[1]?.trim() ?? ''}`);
        }

        // Put the page in keyboard modality so :focus-visible applies to script focus.
        await page.keyboard.press('Shift');
        await page.evaluate(() => (document.documentElement.dataset.modality = 'keyboard'));
        const c = await page.evaluate(PAGE_CHECKS, bannedTerms);
        smallest = Math.min(smallest, c.smallestTextPx);
        focusableChecked += c.focusableCount;
        interactiveChecked += c.interactiveCount;
        c.smallTargets.forEach((t) => targets.add(t));
        c.smallText.forEach((t) => fail('text', `${name}/${theme}: ${t}`));
        c.banned.forEach((t) => fail('language', `${name}/${theme}: banned term in primary text: ${t}`));
        c.clipped.forEach((t) => fail('clipped', `${name}/${theme}: ${t}`));
        c.unreachable.forEach((t) => fail('reach', `${name}/${theme}: ${t}`));
        c.truncated.forEach((t) => fail('truncated', `${name}/${theme}: ${t}`));
        c.unnamed.forEach((t) => fail('names', `${name}/${theme}: no accessible name: ${t}`));
        c.labelNotInName.forEach((t) => fail('names', `${name}/${theme}: the accessible name does not contain the visible label: ${t}`));
        c.filledWrong.forEach((t) => fail('buttons', `${name}/${theme}: ${t}`));
        c.webForm.forEach((t) => fail('desktop', `${name}/${theme}: ${t}`));
        c.noFocusStyle.forEach((t) => fail('focus', `${name}/${theme}: no focus-visible change: ${t}`));
        c.notFocusable.forEach((t) => fail('focus', `${name}/${theme}: cannot take focus: ${t}`));
      });
    }
  }

  report.gates.axe = {
    statesChecked: Object.keys(axe).length,
    violations: Object.values(axe).reduce((n, a) => n + a.violations.length, 0),
    incompleteRules: [...new Set(Object.values(axe).flatMap((a) => a.incomplete.map((i) => i.split(' ')[0] ?? i)))],
    byState: axe,
  };
  report.gates.text = { smallestTextPx: smallest };
  report.gates.focus = { focusableElementsChecked: focusableChecked };
  report.gates.names = { interactiveElementsChecked: interactiveChecked };
  report.gates.language = { bannedTerms: bannedTerms.terms.length + bannedTerms.exact.length };
  report.gates.desktop = { statesChecked: Object.keys(axe).length };
  report.info = { targetsUnder24px: [...targets] };
}

// --------------------------------------------------------------- forced ---
// A system contrast theme (Windows "Contrast themes", forced colours): Chromium replaces the
// page's colours with the system's few and drops box shadows, so a focus ring drawn as a shadow
// vanishes. Every state, on a light and a dark system: every keyboard-focusable element still
// changes appearance on focus, and no page error.

async function forcedGate(): Promise<void> {
  let checked = 0;
  let states = 0;
  for (const theme of (['light', 'dark'] as const)) {
    for (const name of AUDITED) {
      await inState(name, { ...VIEW, theme, forcedColors: 'active' }, async (page) => {
        states += 1;
        const active = await page.evaluate(() => matchMedia('(forced-colors: active)').matches);
        if (!active) fail('forced', `${name}/${theme}: forced colours did not take effect, so this gate proves nothing`);
        await page.keyboard.press('Shift');
        await page.evaluate(() => (document.documentElement.dataset.modality = 'keyboard'));
        const c = await page.evaluate(PAGE_CHECKS, bannedTerms);
        checked += c.focusableCount;
        c.noFocusStyle.forEach((t) => fail('forced', `${name}/${theme}: no visible focus change under forced colours: ${t}`));
      });
    }
  }
  report.gates.forced = { stateAndThemeRuns: states, focusableElementsChecked: checked };
}

// --------------------------------------------------------------- tokens ---
// Colour comes only from the token layer (tokens/design-tokens.json, built into
// src/styles/tokens.css): no colour literal in the page's code or its own stylesheet, and no
// Tailwind palette colour that bypasses the semantic names. An alpha mask (mask-image) may use
// #000 and transparent, which are not colours a person sees.

/** The parts of tokens/design-tokens.json that the audit reads. */
interface DesignTokens {
  color?: Record<string, Record<string, unknown> | undefined>;
}

function tokensGate(): void {
  const LITERAL = /#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?|oklch|oklab|lab|lch|hwb|color)\(/;
  const PALETTE = /\b(?:bg|text|border|ring|fill|stroke|outline|from|to|via|shadow|decoration|divide|accent|caret)-(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose|black|white)(?:-\d{2,3})?\b|\b(?:bg|text|border)-\[#/;
  const files: string[] = [];
  const walk = (dir: string): void => {
    for (const entry of readdirSync(join(root, dir), { withFileTypes: true })) {
      const rel = `${dir}/${entry.name}`;
      if (entry.isDirectory()) walk(rel);
      else if (/\.(tsx?|css)$/.test(entry.name) && rel !== 'src/styles/tokens.css') files.push(rel);
    }
  };
  walk('src');
  let lines = 0;
  for (const file of files) {
    readFileSync(join(root, file), 'utf8').split('\n').forEach((text, i) => {
      lines += 1;
      const code = text.replace(/\/\/.*$|\/\*.*?\*\//g, '');
      if (/mask-image/.test(code) && !LITERAL.test(code.replace(/#000\b/g, ''))) return;
      if (LITERAL.test(code)) fail('tokens', `${file}:${i + 1}: a colour literal outside the token layer: ${text.trim().slice(0, 100)}`);
      if (PALETTE.test(code)) fail('tokens', `${file}:${i + 1}: a palette colour that bypasses the semantic tokens: ${text.trim().slice(0, 100)}`);
    });
  }
  // The light and dark themes define the same colour names (other groups under `color`, such
  // as `tier`, are shared by both and are not themes).
  const tokens = JSON.parse(readFileSync(join(root, 'tokens', 'design-tokens.json'), 'utf8')) as DesignTokens;
  const themes: string[] = (['light', 'dark'] as const).filter((t) => tokens.color?.[t]);
  const keys = themes.map((t) => Object.keys(tokens.color?.[t] ?? {}).sort().join());
  if (themes.length < 2 || new Set(keys).size !== 1) fail('tokens', `tokens/design-tokens.json: the themes (${themes.join(', ')}) do not define the same colour names`);
  // The accent and the tones, checked as numbers in both themes (S2V-031): the filled button's text on its fill, the fill on the
  // card, the tones on the tinted status bar, and the bar's two text colours on that tint. These are the pairs the stylesheet makes;
  // axe checks the rendered ones too, in every state.
  const contrasts: Record<string, number> = {};
  for (const theme of ['light', 'dark'] as const) {
    const c = (name: string): [number, number, number] => parseOklch(String(tokens.color?.[theme]?.[name] ?? ''));
    const fg = c('fg');
    const mixIn = (top: [number, number, number], over: [number, number, number], share: number): [number, number, number] => [0, 1, 2].map((i) => (top[i] ?? 0) * share + (over[i] ?? 0) * (1 - share)) as [number, number, number];
    const need = (label: string, a: [number, number, number], b: [number, number, number], least: number): void => {
      const ratio = contrastOf(a, b);
      contrasts[`${theme}: ${label}`] = Number(ratio.toFixed(2));
      if (ratio < least) fail('tokens', `${theme} theme: ${label} has contrast ${ratio.toFixed(2)}, under ${least}:1`);
    };
    need('on-accent text on the accent fill', c('on-accent'), c('accent'), 4.5);
    need('the accent fill on the card', c('accent'), c('surface'), 3);
    need('the accent fill on the status bar', c('accent'), c('chrome'), 3);
    for (const tone of ['danger', 'warning', 'success'] as const) {
      const bar = mixIn(c(tone), c('chrome'), 0.1);
      need(`the ${tone} mark on its tinted status bar`, c(tone), bar, 3);
      need(`the status bar's first line on the ${tone} tint`, fg, bar, 4.5);
      need(`the status bar's second line on the ${tone} tint`, mixIn(fg, bar, 0.66), bar, 4.5);
      need(`the accent fill on the ${tone} tint`, c('accent'), bar, 3);
    }
    need("the status bar's second line on the bar", mixIn(fg, c('chrome'), 0.66), c('chrome'), 4.5);
  }
  report.gates.tokens = { filesRead: files.length, linesRead: lines, themes, contrasts };
}

/** "oklch(0.55 0.19 258)" as sRGB 0 to 1, gamma-encoded. */
function parseOklch(text: string): [number, number, number] {
  const m = /^oklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)/.exec(text);
  if (!m) throw new Error(`not an oklch colour: ${text}`);
  const [L, C, H] = [Number(m[1]), Number(m[2]), (Number(m[3]) * Math.PI) / 180];
  const a = C * Math.cos(H);
  const b = C * Math.sin(H);
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const mm = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const ss = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  const lin = [4.0767416621 * l - 3.3077115913 * mm + 0.2309699292 * ss, -1.2684380046 * l + 2.6097574011 * mm - 0.3413193965 * ss, -0.0041960863 * l - 0.7034186147 * mm + 1.707614701 * ss];
  return lin.map((v) => {
    const x = Math.min(1, Math.max(0, v));
    return x <= 0.0031308 ? 12.92 * x : 1.055 * x ** (1 / 2.4) - 0.055;
  }) as [number, number, number];
}

/** WCAG contrast of two gamma-encoded sRGB colours. */
function contrastOf(a: [number, number, number], b: [number, number, number]): number {
  const luminance = (rgb: [number, number, number]): number => {
    const [r, g, bl] = rgb.map((v) => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)) as [number, number, number];
    return 0.2126 * r + 0.7152 * g + 0.0722 * bl;
  };
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number];
  return (hi + 0.05) / (lo + 0.05);
}

// ------------------------------------------------------------- overflow ---

// What a person must always find in the same place, in every state: the title bar, the work
// area and the status bar, and the status bar's height (critique of build 2, must-fix 4).
const ANCHORS = ['.titlebar', '.workspace', '.card', '[data-status-bar]'];
const geometry = (page: Page): Promise<Geometry> =>
  page.evaluate((anchors) => {
    const out: Record<string, number[] | null> = {};
    for (const selector of anchors) {
      const el = document.querySelector(selector);
      const box = el?.getBoundingClientRect();
      out[selector] = box ? [Math.round(box.x), Math.round(box.y), Math.round(box.width), Math.round(box.height)] : null;
    }
    return out;
  }, ANCHORS);

async function overflowGate() {
  const out: NonNullable<Gates['overflow']> = {};
  const stable: Record<string, Geometry> = {};
  const none: BannedTerms = { terms: [], exact: [] };
  for (const [label, options] of SIZES) {
    let reference: { name: string; g: Geometry } | null = null;
    for (const name of AUDITED) {
      await inState(name, options, async (page) => {
        const c = await page.evaluate(PAGE_CHECKS, none);
        out[`${label}/${name}`] = { scrollWidth: c.scrollWidth, clientWidth: c.clientWidth, outside: c.outside.length, spill: c.spill.length };
        if (c.scrollWidth > c.clientWidth) fail('overflow', `${label}/${name}: page scrolls sideways (${c.scrollWidth} > ${c.clientWidth})`);
        c.outside.forEach((o) => fail('overflow', `${label}/${name}: ${o}`));
        if (c.primaryActionReachable === false) fail('overflow', `${label}/${name}: the primary action is outside the window`);
        c.spill.forEach((o) => fail('spill', `${label}/${name}: ${o}`));
        // At every size, 200% zoom included: a control out of sight has a cue and can be scrolled to, and no label or sentence is cut.
        c.clipped.forEach((o) => fail('clipped', `${label}/${name}: ${o}`));
        c.unreachable.forEach((o) => fail('reach', `${label}/${name}: ${o}`));
        c.truncated.forEach((o) => fail('truncated', `${label}/${name}: ${o}`));
        if (c.scrollRange.x > 0 || c.scrollRange.y > 0) fail('spill', `${label}/${name}: the window itself scrolls (${JSON.stringify(c.scrollRange)})`);
        const g = await geometry(page);
        stable[`${label}/${name}`] = g;
        const ref = reference ?? (reference = { name, g });
        for (const selector of ANCHORS) {
          if (JSON.stringify(g[selector]) !== JSON.stringify(ref.g[selector])) {
            fail('stable', `${label}/${name}: ${selector} is at ${JSON.stringify(g[selector])}, in ${ref.name} at ${JSON.stringify(ref.g[selector])}`);
          }
        }
      });
    }
  }
  report.gates.overflow = out;
  report.gates.stable = { sizes: SIZES.map(([l]) => l), anchors: ANCHORS, statesPerSize: AUDITED.length };
}

// -------------------------------------------------------------- restore ---
// What Song2Vid remembers is the Codec (SPEC 23, 27.7). It survives a reload and corrupt storage, and a
// remembered HEVC starts the picker on H.264 where this computer cannot make HEVC, without forgetting it.

async function restoreGate() {
  const { context, page } = await openPage(browser, { width: 1280, height: 800 });
  const checked = () => page.locator('[data-group="codec"] [aria-checked="true"]').getAttribute('data-value');
  await load(page, url);
  await pickCodec(page, 'hevc');
  const before = await checked();
  await page.reload();
  await page.waitForSelector('.app');
  const restored = before === 'hevc' && (await checked()) === 'hevc';
  if (!restored) fail('restore', `the Codec after a reload is ${await checked()}, not the HEVC that was chosen`);

  // A computer that cannot make HEVC: the picker starts on H.264, says why, and keeps HEVC remembered.
  await load(page, url, 'no-hevc');
  await page.reload();
  await page.waitForSelector('.app');
  const startsOnH264 = (await checked()) === 'h264' && (await page.locator('[data-group="codec"] [data-value="hevc"]').isDisabled()) && /can't make HEVC videos/.test(await page.locator('[data-hevc-note]').textContent().then((t) => t ?? '', () => ''));
  if (!startsOnH264) fail('restore', 'on a computer that cannot make HEVC the picker did not start on H.264 with HEVC disabled and the note under it');
  const remembered = await page.evaluate((key) => (JSON.parse(localStorage.getItem(key) ?? '{}') as { codec?: string }).codec, PREFS_KEY);
  if (remembered !== 'hevc') fail('restore', `the remembered Codec became ${remembered} on a computer that cannot make HEVC`);
  await load(page, url, 'default');
  await page.reload();
  await page.waitForSelector('.app');
  const comesBack = (await checked()) === 'hevc';
  if (!comesBack) fail('restore', 'HEVC did not come back on a computer that can make it');

  // Broken storage must not break the app.
  await page.evaluate((key) => localStorage.setItem(key, '{not json'), PREFS_KEY);
  await page.reload();
  const usable = await page.waitForSelector('#choose-audio', { timeout: 3000 }).then(() => true, () => false);
  if (!usable) fail('restore', 'the app did not render with corrupt stored data');
  await context.close();
  report.gates.restore = { restoredAfterReload: restored, survivesCorruptStorage: usable, hevcStartsOnH264Where: startsOnH264 && remembered === 'hevc', hevcComesBack: comesBack };
}

// ------------------------------------------------------------- journeys ---
// Each journey in qa/journeys.json has a script here: an array of steps, each one thing a person does
// (one key combination; the drop is the one step no key can make and is sent as the page receives a real
// one), and a check of the result. The step count may not pass the journey's budget. Every journey runs
// twice: with Ctrl (the stand-in says Windows) and with Command (the stand-in says macOS). "Mod" in a key
// names the family's modifier. A step may wait for what it started (a file dialog answers at once; the
// check that follows takes a moment): waiting is not a step.

const KEY_FAMILIES: ['windows' | 'macos', Mod][] = [
  ['windows', 'Control'],
  ['macos', 'Meta'],
];
/** One thing a person does in a journey. */
interface Step {
  label: string;
  run: (page: Page, mod: Mod) => Promise<void>;
}
const press = (keys: string, until?: string): Step => ({
  label: `press ${keys}`,
  run: async (page, mod) => {
    await page.keyboard.press(keys.replace('Mod', mod));
    if (until) await page.waitForSelector(until, { timeout: 5000 });
  },
});

/** Made and saved: the status bar says it, and the page asked the shell for exactly one video. */
const saved = async (page: Page): Promise<string | null> => {
  const done = await waitStatus(page, 'done', 8000).then(() => true, () => false);
  if (!done) return 'the video was not saved';
  const text = await page.locator('[data-status-text]').textContent();
  if (!/^Saved Song\.mp4 to Videos\./.test(text ?? '')) return `the status bar says "${text}"`;
  const makes = await page.evaluate(() => (window.__desktopCalls ?? []).filter((c) => c.name === 'makeVideo').length);
  return makes === 1 ? null : `${makes} requests to make a video`;
};

const lastMake = (page: Page): Promise<Record<string, unknown> | undefined> =>
  page.evaluate(() => ((window.__desktopCalls ?? []).filter((c) => c.name === 'makeVideo').at(-1)?.args[0]) as Record<string, unknown> | undefined);

const JOURNEY_SCRIPTS: Record<string, { fixture: string; steps: Step[]; check: (page: Page) => Promise<string | null> }> = {
  'choose-and-make': {
    fixture: 'default',
    steps: [press('Mod+o', '[data-file="audio"]'), press('Mod+Shift+o', '[data-preview-state="ready"]'), press('Mod+Enter')],
    check: saved,
  },
  'drop-and-make': {
    fixture: 'default',
    steps: [
      {
        label: 'drop a song and an image on the window',
        run: async (page) => {
          await drop(page, [SONG, PICTURE]);
          await page.waitForSelector('[data-preview-state="ready"]', { timeout: 5000 });
        },
      },
      press('Mod+Enter'),
    ],
    check: saved,
  },
  'crop-square': {
    fixture: 'default',
    steps: [
      press('Mod+o', '[data-file="audio"]'),
      press('Mod+Shift+o', '[data-preview-state="ready"]'),
      press('Tab'), // Frame Shape
      press('ArrowRight'), // 9:16
      press('ArrowRight'), // 1:1
      press('Tab'), // Resolution
      press('Tab'), // Codec
      press('Tab'), // Crop position
      press('ArrowLeft'), // a 5% nudge
      press('Mod+Enter'),
    ],
    check: async (page) => {
      const problem = await saved(page);
      if (problem) return problem;
      const request = (await lastMake(page)) as { shape?: string; crop?: { h: number; v: number }; codec?: string } | undefined;
      return request?.shape === '1:1' && request.crop?.h === 0.55 && request.crop.v === 0.5 && request.codec === 'h264' ? null : `the request was ${JSON.stringify(request)}`;
    },
  },
  'hevc-remembered': {
    fixture: 'default',
    steps: [
      press('Tab'), // Choose Image (focus starts on Choose Audio)
      press('Tab'), // Frame Shape
      press('Tab'), // Resolution
      press('Tab'), // Codec
      press('ArrowRight'), // HEVC
      {
        label: 'restart the app',
        run: async (page) => {
          await page.reload();
          await page.waitForSelector('.app');
        },
      },
    ],
    check: async (page) => ((await page.locator('[data-group="codec"] [aria-checked="true"]').getAttribute('data-value')) === 'hevc' ? null : 'HEVC was not chosen after the restart'),
  },
};

async function journeyGate() {
  const out: NonNullable<Gates['journeys']> = {};
  for (const journey of journeys) {
    const script = JOURNEY_SCRIPTS[journey.id];
    if (!script) {
      fail('journeys', `${journey.id}: listed in qa/journeys.json but has no script in qa/audit.ts`);
      continue;
    }
    for (const [platform, mod] of KEY_FAMILIES) {
      const { context, page, errors } = await openPage(browser, VIEW);
      await load(page, url, script.fixture, `platform=${platform}`);
      let problem: string | null = null;
      try {
        for (const step of script.steps) await step.run(page, mod);
        problem = await script.check(page);
      } catch (error) {
        problem = `a step failed: ${String(error).split('\n')[0]}`;
      }
      out[`${journey.id}/${platform}`] = { name: journey.name, steps: script.steps.length, stepBudget: journey.stepBudget, passed: !problem };
      if (problem) fail('journeys', `${journey.id} (${platform} keys): ${problem}`);
      if (script.steps.length > journey.stepBudget) fail('journeys', `${journey.id}: ${script.steps.length} steps, budget ${journey.stepBudget}`);
      if (errors.length) fail('page', `journey ${journey.id} (${platform}): ${errors.join(' | ')}`);
      await context.close();
    }
  }
  report.gates.journeys = out;
}

// ------------------------------------------------------------ shortcuts ---
// What each shortcut must visibly do, by the label of its palette row. A row with no shortcut must be
// listed in qa/journeys.json `commandsWithoutShortcut` with the reason it is not a repeated action. Each
// label is one string written as the system writes it ("Ctrl+Shift+L"; "⇧⌘L"), and each key works on both
// families.

const seen = (page: Page, selector: string): Promise<boolean> => page.waitForSelector(selector, { timeout: 1500 }).then(() => true, () => false);
const SHORTCUT_EFFECTS: Record<string, (page: Page) => Promise<boolean>> = {
  'Choose Audio…': (page) => seen(page, '[data-file="audio"]'),
  'Choose Image…': (page) => seen(page, '[data-file="image"]'),
  'Use the dark theme': (page) => page.evaluate(() => document.documentElement.dataset.theme === 'dark'),
  'Use the light theme': (page) => page.evaluate(() => document.documentElement.dataset.theme === 'light'),
};
// A command that only applies in another state is set up first.
const SHORTCUT_SETUP: Record<string, { fixture: string; setup: (page: Page, mod: Mod) => Promise<void>; effect: (page: Page) => Promise<boolean> }> = {
  'Make Video': {
    fixture: 'default',
    setup: async (page, mod) => fill(page, mod),
    effect: (page) => seen(page, '[data-status-bar][data-job="starting"], [data-status-bar][data-job="running"], [data-status-bar][data-job="done"]'),
  },
  Cancel: {
    fixture: 'make-hold',
    setup: async (page, mod) => {
      await fill(page, mod);
      await make(page, mod);
      await waitStatus(page, 'running');
    },
    effect: (page) => seen(page, '[data-status-bar][data-job="cancelling"], [data-status-bar][data-job="cancelled"]'),
  },
  'Reset Crop to Center': {
    fixture: 'default',
    setup: async (page, mod) => {
      await fill(page, mod);
      await pickShape(page, '1:1');
      await page.locator('[role="slider"]').focus();
      await page.keyboard.press('ArrowLeft');
      await page.keyboard.press('ArrowLeft');
    },
    effect: async (page) => (await cropValue(page)) === '50% across, 50% down',
  },
};
const LABEL_FORMAT: Record<string, RegExp> = { windows: /^(Ctrl\+)?(Alt\+)?(Shift\+)?[^+\s]+$/, macos: /^⌥?⇧?⌘?[^+\s⌘⇧⌥]+$/ };
const toPlaywright = (label: string, platform: string): string => {
  if (platform === 'macos') {
    const mods = [...label].filter((ch) => '⌥⇧⌘'.includes(ch)).map((ch) => (({ '⌥': 'Alt', '⇧': 'Shift', '⌘': 'Meta' }) as Record<string, string>)[ch]);
    const key = [...label].filter((ch) => !'⌥⇧⌘'.includes(ch)).join('');
    return [...mods, key === '↩' ? 'Enter' : key === '⎋' ? 'Escape' : key].join('+');
  }
  return label.replace('Ctrl', 'Control').replace(/\+?Esc$/, (m) => (m.startsWith('+') ? '+Escape' : 'Escape'));
};

async function shortcutsGate() {
  const exempt = (JSON.parse(readFileSync(join(root, 'qa', 'journeys.json'), 'utf8')) as JourneysFile).commandsWithoutShortcut.map((c) => c.label.replace('{productName}', config.productName));
  const out: Record<string, ShortcutResult> = {};
  for (const [platform, mod] of KEY_FAMILIES) {
    const { context, page } = await openPage(browser, VIEW);
    await load(page, url, 'default', `platform=${platform}`);
    await fill(page, mod);
    await page.keyboard.press(`${mod}+k`);
    await page.waitForSelector('.palette');
    const rows = await page.evaluate(() =>
      [...document.querySelectorAll('.palette [role="option"]')].map((row) => ({
        label: row.querySelector('span')?.textContent?.trim() ?? '',
        keys: [...row.querySelectorAll('[data-keys] kbd')].map((k) => (k.textContent ?? '').trim()),
      })),
    );
    await page.keyboard.press('Escape');
    await context.close();
    const result: ShortcutResult = { commands: rows.length, withShortcut: 0, worked: [] };
    for (const row of rows) {
      if (!row.keys.length) {
        if (!exempt.includes(row.label)) fail('shortcuts', `"${row.label}" has no shortcut and is not listed in commandsWithoutShortcut`);
        continue;
      }
      result.withShortcut += 1;
      const keys = row.keys[0] ?? '';
      if (row.keys.length !== 1 || !LABEL_FORMAT[platform]?.test(keys)) fail('shortcuts', `${platform}: "${row.label}" shows ${JSON.stringify(row.keys)}, not one key cap written as the system writes it`);
      const special = SHORTCUT_SETUP[row.label];
      const effect = special?.effect ?? SHORTCUT_EFFECTS[row.label];
      if (!effect) {
        fail('shortcuts', `"${row.label}" has no effect check in qa/audit.ts`);
        continue;
      }
      const run = await openPage(browser, VIEW);
      await load(run.page, url, special?.fixture ?? 'default', `platform=${platform}`);
      if (special) await special.setup(run.page, mod);
      await run.page.locator('#choose-audio').focus().catch(() => undefined);
      await run.page.keyboard.press(toPlaywright(keys, platform));
      await run.page.waitForTimeout(120);
      if (await effect(run.page)) result.worked.push(row.label);
      else fail('shortcuts', `${platform}: ${row.keys[0]} did not do "${row.label}"`);
      await run.context.close();
    }
    // Tooltips show the shortcut of the control they describe, as the system writes it.
    const tipPage = await openPage(browser, VIEW);
    await load(tipPage.page, url, 'default', `platform=${platform}`);
    await tipPage.page.hover('[aria-label="Use the dark theme"], [aria-label="Use the light theme"]');
    const tip = await tipPage.page.waitForSelector('.tooltip', { timeout: 2000 }).then((el) => el?.textContent(), () => '');
    result.tooltipShowsKeys = platform === 'macos' ? /⌘/.test(tip ?? '') : /Ctrl\+/.test(tip ?? '');
    if (!result.tooltipShowsKeys) fail('shortcuts', `${platform}: the theme button tooltip does not show its shortcut (${tip})`);
    await tipPage.context.close();
    out[platform] = result;
  }
  report.gates.shortcuts = out;
}

// -------------------------------------------------------------- overlay ---
// Keys typed straight after the key that opens an overlay land in it: the overlay takes focus in the same
// turn as the key (build 2 found focus a frame late).

async function overlayGate() {
  const out: NonNullable<Gates['overlay']> = {};
  for (const [platform, mod] of KEY_FAMILIES) {
    const { context, page } = await openPage(browser, VIEW);
    await load(page, url, 'default', `platform=${platform}`);
    await page.locator('#choose-audio').focus();
    await page.keyboard.press(`${mod}+k`);
    await page.keyboard.type('abo', { delay: 0 });
    const state = await page.evaluate(() => ({ query: document.querySelector<HTMLInputElement>('.palette input')?.value ?? null, body: document.activeElement?.tagName ?? '' }));
    out[platform] = state;
    if (state.query !== 'abo') fail('overlay', `${platform}: keys typed after opening the palette went elsewhere: ${JSON.stringify(state)}`);
    await context.close();
  }
  report.gates.overlay = out;
}

// ------------------------------------------------------------------ job ---
// The job, from the stand-in's fixtures. Cancel is acknowledged at once; each row of SPEC 27.5's table says
// its sentence and its filled button can succeed for its cause; "Copy Details" copies the developer text,
// which never appears on screen; progress never goes back and never reads 100% before the outcome.

/** SPEC 27.5, written out again here on purpose: the audit does not read the page's own table. */
const TABLE: Record<string, { sentence: string; filled: string }> = {
  audio_not_found: { sentence: 'The song file is no longer where it was.', filled: 'Choose Audio…' },
  image_not_found: { sentence: 'The image file is no longer where it was.', filled: 'Choose Image…' },
  audio_unreadable: { sentence: "Song2Vid can't read this audio file.", filled: 'Choose Audio…' },
  image_unreadable: { sentence: "Song2Vid can't read this image file.", filled: 'Choose Image…' },
  image_too_small: { sentence: 'This image is too small. Each side needs at least 16 pixels.', filled: 'Choose Image…' },
  codec_unavailable: { sentence: "This computer can't make HEVC videos.", filled: 'Use H.264' },
  output_not_writable: { sentence: "Couldn't save to that folder. Nothing was saved.", filled: 'Choose Another Folder…' },
  disk_full: { sentence: 'Not enough disk space. Nothing was saved.', filled: 'Choose Another Folder…' },
  output_in_use: { sentence: 'Another app is using that file. Close it, then try again.', filled: 'Try Again' },
  output_exists: { sentence: "A file with that name appeared while the video was being made. It was kept, and the new video wasn't saved.", filled: 'Save As…' },
  export_failed: { sentence: "The video couldn't be made. Your files are unchanged.", filled: 'Try Again' },
  something_new: { sentence: "The video couldn't be made. Your files are unchanged.", filled: 'Try Again' },
};

const callsOf = (page: Page, name: string): Promise<{ args: unknown[] }[]> => page.evaluate((n) => (window.__desktopCalls ?? []).filter((c) => c.name === n), name);
const statusText = (page: Page): Promise<string> =>
  page.evaluate(() => [...document.querySelectorAll('[data-status-text] p')].map((p) => (p.textContent ?? '').trim()).filter(Boolean).join(' '));

async function jobGate() {
  const out: JobGate = {};
  // Cancel is acknowledged in the same task as the click, and the tool's exit is then waited for.
  {
    const { context, page } = await openPage(browser, VIEW);
    await load(page, url, 'make-hold');
    await fill(page);
    await make(page);
    await waitStatus(page, 'running');
    // Read the state after the task's microtasks (where React applies a discrete update) and before any timer or frame can run.
    const after = await page.evaluate(async () => {
      document.querySelector<HTMLElement>('[data-status-bar] button')?.click();
      for (let i = 0; i < 3; i++) await new Promise<void>((r) => queueMicrotask(() => r()));
      return { kind: document.querySelector('[data-status-bar]')?.getAttribute('data-job'), text: document.querySelector('[data-status-text]')?.textContent ?? '' };
    });
    out.cancelAcknowledged = after.kind;
    if (after.kind !== 'cancelling' || !/^Cancelling/.test(after.text)) fail('job', `cancel was not acknowledged at once: the bar says "${after.kind}": ${after.text}`);
    await waitStatus(page, 'cancelled', 3000).catch(() => fail('job', 'the job did not end as cancelled'));
    const end = await statusText(page);
    if (end !== 'Cancelled. Nothing was saved.') fail('job', `after cancelling the bar says "${end}"`);
    const controls = await page.evaluate(() => [...document.querySelectorAll<HTMLButtonElement>('#choose-audio, #choose-image, #make-video')].map((b) => b.disabled));
    if (controls.some(Boolean)) fail('job', `a control stayed disabled after the job ended: ${controls}`);
    await context.close();
  }
  // Progress: never back, under 100 before the outcome; time left only once encoding has run 1 s and passed 5%.
  {
    const { context, page } = await openPage(browser, VIEW);
    await load(page, url);
    await fill(page);
    await page.evaluate(() => {
      const seen: { percent: number | null; text: string; kind: string }[] = [];
      new MutationObserver(() => {
        const bar = document.querySelector('[data-status-bar]');
        const value = bar?.querySelector('[role="progressbar"]')?.getAttribute('aria-valuenow');
        seen.push({ percent: value === null || value === undefined ? null : Number(value), text: (bar?.querySelector('[data-status-text]')?.textContent ?? '').trim(), kind: bar?.getAttribute('data-job') ?? '' });
      }).observe(document.querySelector('[data-status-bar]') as Element, { subtree: true, childList: true, attributes: true, characterData: true });
      (window as unknown as { __seen: typeof seen }).__seen = seen;
    });
    await make(page);
    await waitStatus(page, 'done', 8000);
    const trail = await page.evaluate(() => (window as unknown as { __seen: { percent: number | null; text: string; kind: string }[] }).__seen);
    let high = -1;
    for (const point of trail) {
      if (point.percent === null) continue;
      if (point.percent < high) fail('job', `progress went back from ${high} to ${point.percent}`);
      if (point.percent >= 100 && point.kind !== 'done') fail('job', `progress read ${point.percent}% before the outcome`);
      high = Math.max(high, point.percent);
      if (/left/.test(point.text) && point.percent <= 5) fail('job', `time left shown at ${point.percent}%: ${point.text}`);
    }
    out.progress = { points: trail.length, highest: high, timeLeftSeen: trail.some((t) => /left/.test(t.text)) };
    if (!trail.some((t) => /left/.test(t.text))) fail('job', 'time left was never shown on a job that ran past 5% after 1 s');
    await context.close();
  }
  // Every row of SPEC 27.5's table, and a code the page does not know.
  for (const [code, expected] of Object.entries(TABLE)) {
    const { context, page } = await openPage(browser, VIEW);
    await load(page, url, `make-fail-${code}`);
    await fill(page);
    await make(page);
    await waitStatus(page, 'failure');
    const seenNow = await page.evaluate(() => ({
      filled: [...document.querySelectorAll('[data-status-bar] .btn-primary')].map((b) => (b.textContent ?? '').trim()),
      page: document.body.innerText,
    }));
    const text = await statusText(page);
    if (text !== expected.sentence) fail('job', `${code}: the bar says "${text}", SPEC 27.5 says "${expected.sentence}"`);
    if (seenNow.filled.length !== 1 || seenNow.filled[0] !== expected.filled) fail('job', `${code}: the filled button reads ${JSON.stringify(seenNow.filled)}, expected "${expected.filled}"`);
    // Copy Details copies the developer text, and it is never on screen.
    await page.keyboard.press('Control+k');
    await page.waitForSelector('.palette');
    await page.keyboard.type('copy details');
    await page.keyboard.press('Enter');
    await page.waitForFunction(() => (window.__copied ?? []).length > 0, null, { timeout: 2000 }).catch(() => undefined);
    const copied = await page.evaluate(() => window.__copied.at(-1) ?? '');
    if (!copied || !copied.includes(code === 'something_new' ? 'something_new' : code)) fail('job', `${code}: "Copy Details" copied ${JSON.stringify(copied.slice(0, 60))}`);
    if (copied && seenNow.page.includes(copied.split('\n')[0] ?? copied) && (copied.split('\n')[0] ?? '').length > 1) fail('job', `${code}: the developer text is on screen`);
    out[`row:${code}`] = { text, filled: seenNow.filled, copiedChars: copied.length };
    await context.close();
  }
  // A second failure with the same inputs says so and offers a different step.
  {
    const { context, page } = await openPage(browser, VIEW);
    await load(page, url, 'make-fail-output_in_use');
    await fill(page);
    await make(page);
    await waitStatus(page, 'failure');
    await page.getByRole('button', { name: 'Try Again' }).click();
    await page.waitForFunction(() => /failed again/.test(document.querySelector('[data-status-text]')?.textContent ?? ''), null, { timeout: 3000 }).catch(() => {});
    const second = { text: await statusText(page), filled: await page.evaluate(() => [...document.querySelectorAll('[data-status-bar] .btn-primary')].map((b) => (b.textContent ?? '').trim())) };
    out.secondFailure = second;
    if (!/It failed again\./.test(second.text) || second.filled[0] !== 'Copy Details') fail('job', `a repeated failure reads the same or offers the same step: ${JSON.stringify(second)}`);
    // A change of inputs is a new failure, not a repeat.
    await pickShape(page, '1:1');
    await make(page);
    await waitStatus(page, 'failure');
    const third = await statusText(page);
    if (/failed again/.test(third)) fail('job', `a failure with different inputs said it failed again: ${third}`);
    await context.close();
  }
  // Each filled button can succeed for its cause.
  for (const [code, label, check] of [
    ['audio_not_found', 'Choose Audio…', async (page: Page) => (await callsOf(page, 'chooseAudio')).length === 2],
    ['image_unreadable', 'Choose Image…', async (page: Page) => (await callsOf(page, 'chooseImage')).length === 2],
    ['codec_unavailable', 'Use H.264', async (page: Page) => (await page.locator('[data-group="codec"] [aria-checked="true"]').getAttribute('data-value')) === 'h264' && (await callsOf(page, 'setPreferences')).length === 2 && (await statusText(page)) !== TABLE['codec_unavailable']?.sentence],
    ['output_not_writable', 'Choose Another Folder…', async (page: Page) => (await callsOf(page, 'makeVideo')).at(-1)?.args[0] instanceof Object && ((await callsOf(page, 'makeVideo')).at(-1)?.args[0] as { destination: string }).destination === 'ask'],
    ['output_exists', 'Save As…', async (page: Page) => ((await callsOf(page, 'makeVideo')).at(-1)?.args[0] as { destination: string }).destination === 'ask'],
    ['output_in_use', 'Try Again', async (page: Page) => ((await callsOf(page, 'makeVideo')).at(-1)?.args[0] as { destination: string }).destination === 'same'],
  ] as const) {
    const { context, page } = await openPage(browser, VIEW);
    await load(page, url, `make-fail-${code}`);
    await fill(page);
    if (code === 'codec_unavailable') await pickCodec(page, 'hevc');
    await make(page);
    await waitStatus(page, 'failure');
    await page.locator('[data-status-bar] .btn-primary').click();
    await page.waitForTimeout(300);
    if (!(await check(page))) fail('job', `${code}: "${label}" did not do what it says`);
    await context.close();
  }
  // A drop while a video is made is refused in words for 3 seconds and changes nothing.
  {
    const { context, page } = await openPage(browser, VIEW);
    await load(page, url, 'make-hold');
    await fill(page);
    await make(page);
    await waitStatus(page, 'running');
    await drop(page, [SONG, PICTURE]);
    await waitStatus(page, 'notice');
    const refused = await statusText(page);
    const dropCalls = (await callsOf(page, 'dropFiles')).length;
    if (!/^Wait for the current video to finish\./.test(refused) || dropCalls !== 0) fail('job', `a drop during a job said "${refused}" and asked the shell ${dropCalls} times`);
    const cancelStill = await page.locator('[data-status-bar] [data-live] button', { hasText: 'Cancel' }).count();
    if (cancelStill !== 1) fail('job', 'Cancel disappeared while the drop was refused');
    await page.waitForTimeout(3300);
    const after = await page.locator('[data-status-bar]').getAttribute('data-job');
    if (after !== 'running') fail('job', `the refusal stayed longer than 3 seconds (the bar says ${after})`);
    out.dropRefused = { text: refused };
    await context.close();
  }
  // The save dialog closed without a choice changes nothing.
  {
    const { context, page } = await openPage(browser, VIEW);
    await load(page, url, 'make-dismissed');
    await fill(page);
    await make(page);
    await page.waitForTimeout(300);
    const kind = await page.locator('[data-status-bar]').getAttribute('data-job');
    if (kind !== 'idle') fail('job', `a dismissed save dialog left the bar saying ${kind}`);
    await context.close();
  }
  report.gates.job = out;
}

// ----------------------------------------------------------------- crop ---
// The crop control (SPEC 27.2, premium bar rules 67 and 75): a slider to assistive technology with a spoken
// value, arrow keys of 5% and Shift of 25%, Home, End, Page Up and Page Down, a drag that moves the image
// with the pointer in the same frame, and Reset to Center.

async function cropGate() {
  const out: Record<string, unknown> = {};
  const { context, page } = await openPage(browser, VIEW);
  await load(page, url);
  await fill(page);
  const hidden = await page.locator('[role="slider"]').count();
  if (hidden !== 0) fail('crop', 'Crop position is offered for a Fit shape, where there is nothing to crop');
  await pickShape(page, '1:1');
  const slider = page.locator('[role="slider"][aria-label="Crop position"]');
  const attrs = await slider.evaluate((el) => ({ min: el.getAttribute('aria-valuemin'), max: el.getAttribute('aria-valuemax'), now: el.getAttribute('aria-valuenow'), text: el.getAttribute('aria-valuetext'), tab: (el as HTMLElement).tabIndex }));
  out.attributes = attrs;
  if (attrs.min !== '0' || attrs.max !== '100' || attrs.now !== '50' || attrs.text !== '50% across, 50% down' || attrs.tab !== 0) fail('crop', `the Crop position control reads ${JSON.stringify(attrs)}`);

  const expectKey = async (keys: string, text: string) => {
    await page.keyboard.press(keys);
    const got = await cropValue(page);
    if (got !== text) fail('crop', `${keys}: the value reads "${got}", expected "${text}"`);
  };
  await slider.focus();
  await expectKey('ArrowLeft', '55% across, 50% down');
  await expectKey('Shift+ArrowLeft', '80% across, 50% down');
  await expectKey('ArrowUp', '80% across, 50% down'); // nothing to crop that way: unchanged
  await expectKey('ArrowRight', '75% across, 50% down');
  await expectKey('PageUp', '100% across, 50% down');
  await expectKey('Home', '0% across, 50% down');
  await expectKey('End', '100% across, 50% down');
  await expectKey('PageDown', '75% across, 50% down');
  await page.keyboard.press('Control+0');
  if ((await cropValue(page)) !== '50% across, 50% down') fail('crop', 'Ctrl+0 did not reset the crop to the centre');

  // A drag moves the image with the pointer: 40 screen pixels move it 40 screen pixels, in the same task.
  const frameBox = await page.locator('.frame').boundingBox();
  const imageBefore = await page.locator('.frame img').boundingBox();
  if (!frameBox || !imageBefore) throw new Error('no frame to drag');
  await page.mouse.move(frameBox.x + frameBox.width / 2, frameBox.y + frameBox.height / 2);
  await page.mouse.down();
  await page.mouse.move(frameBox.x + frameBox.width / 2 - 40, frameBox.y + frameBox.height / 2);
  const imageDuring = await page.locator('.frame img').boundingBox();
  const textDuring = await cropValue(page);
  await page.mouse.up();
  const moved = imageDuring && imageBefore ? imageDuring.x - imageBefore.x : NaN;
  out.drag = { moved, textDuring };
  if (!(Math.abs(moved - -40) <= 1)) fail('crop', `a 40 px drag moved the image ${moved} px`);
  if (!/^[6-9]\d% across, 50% down$/.test(textDuring ?? '')) fail('crop', `during the drag the value reads "${textDuring}"`);
  // Past the edge it stops.
  await page.mouse.move(frameBox.x + 200, frameBox.y + 100);
  await page.mouse.down();
  await page.mouse.move(frameBox.x - 5000 + 200, frameBox.y + 100, { steps: 3 });
  await page.mouse.up();
  const edge = await cropValue(page);
  if (edge !== '100% across, 50% down') fail('crop', `dragged far past the edge, the value reads "${edge}"`);
  // Reset to Center, by its button.
  await page.getByRole('button', { name: 'Reset to Center' }).click();
  if ((await cropValue(page)) !== '50% across, 50% down') fail('crop', 'Reset to Center did not restore 50% across, 50% down');
  // A new Frame Shape or a new image starts from the centre; a new Resolution keeps the position.
  await slider.focus();
  await page.keyboard.press('ArrowLeft');
  await pickShape(page, '4:3');
  if ((await cropValue(page)) !== '50% across, 50% down') fail('crop', 'a new Frame Shape did not start from the centre');
  await page.keyboard.press('Tab').catch(() => undefined);
  await slider.focus();
  await page.keyboard.press('ArrowLeft');
  await page.locator('[data-group="resolution"] [data-value="2160p"]').click();
  if ((await cropValue(page)) !== '55% across, 50% down') fail('crop', 'a new Resolution did not keep the crop position');
  await context.close();
  report.gates.crop = out;
}

// ---------------------------------------------------------------- files ---
// SPEC 4a and 27.3, by what a person sees: an empty slot fills at once, a filled one asks (Keep Current is the
// default; Esc keeps; focus returns), a rejected drop changes nothing and says why, and only a drop that could
// be used lights the window.

async function filesGate() {
  const out: Record<string, unknown> = {};
  const names = (page: Page) => page.evaluate(() => ({ audio: document.querySelector('[data-file="audio"]')?.textContent ?? null, image: document.querySelector('[data-file="image"]')?.textContent ?? null }));
  const { context, page, errors } = await openPage(browser, VIEW);
  await load(page, url);
  // Into empty slots: filled at once, no question.
  await drop(page, [SONG, PICTURE]);
  await page.waitForSelector('[data-file="image"]');
  const filled = await names(page);
  if (filled.audio !== SONG.name || filled.image !== PICTURE.name || (await page.locator('[data-replace]').count()) !== 0) fail('files', `a drop into empty slots gave ${JSON.stringify(filled)} or asked a question`);
  // Onto filled slots: asked first, in the Mac app's words; Keep Current is the default.
  await page.locator('#choose-image').focus();
  await drop(page, [{ name: 'Other Song.mp3', type: 'audio/mpeg' }]);
  await page.waitForSelector('[data-replace]');
  await page.waitForFunction(() => document.activeElement?.textContent === 'Keep Current', null, { timeout: 1000 }).catch(() => undefined);
  const dialog = await page.evaluate(() => ({ title: document.querySelector('[data-replace]')?.textContent ?? '', focused: document.activeElement?.textContent ?? '', buttons: [...document.querySelectorAll('[data-replace] button')].map((b) => b.textContent?.trim()) }));
  out.question = dialog;
  if (!dialog.title.startsWith('Replace the current song?') || dialog.focused !== 'Keep Current' || dialog.buttons.join() !== 'Replace,Keep Current') fail('files', `the Replace question reads ${JSON.stringify(dialog)}`);
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => !document.querySelector('[data-replace]'));
  const kept = await names(page);
  const back = await page.evaluate(() => document.activeElement?.id ?? '');
  if (kept.audio !== SONG.name) fail('files', `Esc did not keep the current song: ${JSON.stringify(kept)}`);
  if (back !== 'choose-image') fail('files', `after the question focus is on "${back}", not where it was (choose-image)`);
  const released = await page.evaluate(() => (window as unknown as { __released: string[] }).__released.length);
  if (released < 1) fail('files', 'the dropped file that was not kept was not released');
  // Replace uses the dropped files, and a song and an image together ask one question.
  await drop(page, [{ name: 'Other Song.mp3', type: 'audio/mpeg' }, { name: 'Other Cover.png', type: 'image/png' }]);
  await page.waitForSelector('[data-replace]');
  const both = await page.locator('[data-replace]').textContent();
  if (!/^Replace the current song and image\?/.test(both ?? '')) fail('files', `a song and an image asked "${both}"`);
  await page.getByRole('button', { name: 'Replace', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('[data-file="audio"]')?.textContent === 'Other Song.mp3');
  await page.waitForFunction(() => !document.querySelector('[data-replace]'));
  const replaced = await names(page);
  if (replaced.image !== 'Other Cover.png') fail('files', `Replace did not use both dropped files: ${JSON.stringify(replaced)}`);
  // A drop that fills an empty slot while the other is dropped onto a filled one: the empty slot is filled whichever way the person answers.
  // Rejected drops change nothing and say why.
  const before = await names(page);
  for (const [label, files, words] of [
    ['two songs', [SONG, { name: 'B.mp3', type: 'audio/mpeg' }], /Song2Vid uses one song at a time\. Drop one song, one image, or one of each\./],
    ['three files', [SONG, PICTURE, { name: 'C.png', type: 'image/png' }], /takes two at most\. Drop one song, one image, or one of each\./],
    ['an unreadable type', [{ name: 'notes.txt', type: 'text/plain' }], /\u201cnotes\.txt\u201d is not a song or an image Song2Vid can use\. Drop a song or an image\./],
  ] as const) {
    await drop(page, [...files]);
    await waitStatus(page, 'notice');
    const said = await statusText(page);
    if (!words.test(said)) fail('files', `${label}: the message says "${said}"`);
    if (JSON.stringify(await names(page)) !== JSON.stringify(before) || (await page.locator('[data-replace]').count()) !== 0) fail('files', `${label}: the drop changed something`);
    await page.waitForTimeout(150);
  }
  // The highlight: only for a drop that could be used.
  await drop(page, [SONG], { phase: 'over' });
  const lit = await page.locator('.drop-veil').getAttribute('data-active');
  await drop(page, [SONG, PICTURE, { name: 'C.png', type: 'image/png' }], { phase: 'over' });
  const litForThree = await page.locator('.drop-veil').getAttribute('data-active');
  out.highlight = { valid: lit, three: litForThree };
  if (lit !== 'true' || litForThree !== 'false') fail('files', `the highlight is ${lit} for a valid drop and ${litForThree} for three files`);
  // A file opened with the app (a second launch) is judged as a drop is.
  await page.evaluate(() => (window as unknown as { __openFiles: (names: string[]) => void }).__openFiles(['Handed Over.mp3']));
  await page.waitForSelector('[data-replace]');
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => !document.querySelector('[data-replace]'));
  if (errors.length) fail('page', `files: ${errors.join(' | ')}`);
  await context.close();
  // Choosing with a button replaces without a question, since it is a deliberate choice (SPEC 4).
  {
    const second = await openPage(browser, VIEW);
    await load(second.page, url);
    await fill(second.page);
    await second.page.locator('#choose-audio').click();
    await second.page.waitForTimeout(150);
    if ((await second.page.locator('[data-replace]').count()) !== 0) fail('files', 'choosing a file with its button asked a question');
    await second.context.close();
  }
  report.gates.files = out;
}

// ----------------------------------------------------------------- tool ---
async function toolGate() {
  const out: Record<string, unknown> = {};
  {
    const { context, page } = await openPage(browser, VIEW);
    await load(page, url, 'tool-damaged');
    const seenNow = await page.evaluate(() => ({ text: [...document.querySelectorAll('[data-blocked] p')].map((p) => p.textContent).join(' '), filled: [...document.querySelectorAll('.btn-primary')].map((b) => b.textContent?.trim()), make: document.querySelectorAll('#make-video').length, rows: document.querySelectorAll('.row').length }));
    out.missing = seenNow;
    if (seenNow.text !== 'Song2Vid is missing part of itself. Reinstall it to keep making videos.' || seenNow.filled.join() !== 'Open Download Page' || seenNow.make !== 0 || seenNow.rows !== 0) fail('tool', `the missing-tool state reads ${JSON.stringify(seenNow)}`);
    await page.getByRole('button', { name: 'Open Download Page' }).click();
    const links = await callsOf(page, 'openLink');
    if (links.length !== 1 || links[0]?.args[0] !== 'download-page') fail('tool', `Open Download Page asked the shell for ${JSON.stringify(links)}`);
    await page.keyboard.press('Control+o');
    await page.waitForTimeout(100);
    if ((await callsOf(page, 'chooseAudio')).length !== 0) fail('tool', 'Ctrl+O chose a file with the tool missing');
    await context.close();
  }
  {
    const { context, page } = await openPage(browser, VIEW);
    await load(page, url, 'tool-damaged-late');
    await fill(page);
    const blocked = await page.waitForSelector('[data-blocked]', { timeout: 3000 }).then(() => true, () => false);
    out.turnsMissing = blocked;
    if (!blocked) fail('tool', 'a tool that failed its version check after launch did not show the blocking state');
    await context.close();
  }
  report.gates.tool = out;
}

// -------------------------------------------------------------- notices ---
// The banned-terms gate leaves out the third-party notices text and nothing else. A planted banned word is
// caught anywhere but there, and no element but About's notices carries the exemption.

async function noticesGate() {
  const out: Record<string, unknown> = {};
  const { context, page } = await openPage(browser, VIEW);
  await load(page, url);
  await STATES['42-about']?.run(page, 'Control');
  await park(page);
  const bannedNow = async () => (await page.evaluate(PAGE_CHECKS, bannedTerms)).banned;
  const none = await bannedNow();
  const text = await page.locator('[data-notices]').textContent();
  out.noticesNameTheProgram = /FFmpeg/.test(text ?? '');
  if (!/FFmpeg/.test(text ?? '')) fail('notices', 'the notices do not name FFmpeg, so this gate would prove nothing');
  if (none.length) fail('notices', `About reports banned terms: ${none.join(', ')}`);
  await page.evaluate(() => {
    const planted = document.createElement('p');
    planted.id = 'planted';
    planted.textContent = 'FFmpeg and ffprobe, planted';
    document.querySelector('[data-about] dl')?.after(planted);
  });
  const outside = await bannedNow();
  out.plantedOutside = outside.length;
  if (!outside.some((t) => /planted/.test(t))) fail('notices', 'a banned word planted in About outside the notices was not caught');
  await page.evaluate(() => document.getElementById('planted')?.remove());
  await page.evaluate(() => {
    const planted = document.createElement('p');
    planted.id = 'planted-in';
    planted.textContent = 'ffprobe, planted';
    document.querySelector('[data-notices]')?.append(planted);
  });
  const inside = await bannedNow();
  if (inside.length) fail('notices', 'the exemption does not cover the notices text');
  await context.close();
  report.gates.notices = out;
}

// ------------------------------------------------------------- distinct ---
// A failure, a refusal and a saved video are not a status line (the critic's must-fix 4 and 7, 11): the bar carries a mark, a tint
// and a heavier first line, and the idle bar carries none of them. And every state that says a file is the problem says one thing
// in every place (must-fix 5): the row, the preview, the bar, Make Video and the enlarge note.

interface BarLook {
  tone: string | null;
  mark: boolean;
  background: string;
  weight: number;
  edge: string;
  text: string;
  button: { label: string; filled: boolean } | null;
  progressWide: number | null;
  height: number;
}

const barLook = (page: Page): Promise<BarLook> =>
  page.evaluate(() => {
    const bar = document.querySelector('[data-status-bar]') as HTMLElement;
    // A bar without the live layer is an old layout: it is looked at as a whole, and fails the checks below instead of crashing.
    const live = (bar.querySelector('[data-live]') ?? bar) as HTMLElement;
    const first = (live.querySelector('.statusbar-first') ?? live.querySelector('p') ?? live) as HTMLElement;
    const filled = live.querySelector('[data-filled]');
    const button = live.querySelector('button');
    const progress = bar.querySelector('[role="progressbar"]') as HTMLElement | null;
    return {
      tone: bar.getAttribute('data-tone'),
      mark: Boolean(live.querySelector('svg.statusbar-mark, svg')),
      background: getComputedStyle(bar).backgroundColor,
      weight: Number(getComputedStyle(first).fontWeight),
      edge: getComputedStyle(bar).boxShadow,
      text: [...live.querySelectorAll('[data-status-text] p')].map((p) => p.textContent ?? '').join(' ').trim(),
      button: button ? { label: (button.textContent ?? '').trim(), filled: Boolean(filled) } : null,
      progressWide: progress ? progress.getBoundingClientRect().width / bar.getBoundingClientRect().width : null,
      height: bar.getBoundingClientRect().height,
    };
  });

async function distinctGate(): Promise<void> {
  const out: Record<string, unknown> = {};
  for (const theme of ['dark', 'light'] as const) {
    const looks: Record<string, BarLook> = {};
    for (const name of ['04-both', '17-making', '21-cancelled', '22-done', '23-error-audio-not-found', '28-error-codec-unavailable', '32-error-output-exists', '33-error-export-failed', '35-error-repeated', '36-choose-audio-unreadable', '45-drop-refused']) {
      await inState(name, { ...VIEW, theme }, async (page) => {
        looks[name] = await barLook(page);
      });
    }
    const idle = looks['04-both'] as BarLook;
    if (idle.tone !== 'neutral' || idle.mark || idle.weight >= 600) fail('distinct', `${theme}: the idle bar already looks like an error or a result (${JSON.stringify({ tone: idle.tone, mark: idle.mark, weight: idle.weight })})`);
    for (const [name, look] of Object.entries(looks)) {
      const isFailure = /error|choose-audio-unreadable|drop-refused/.test(name);
      const isDone = /done/.test(name);
      if (!isFailure && !isDone) continue;
      const what = isDone ? 'a saved video' : 'a failure or a refusal';
      if (look.tone === 'neutral' || look.tone === null) fail('distinct', `${theme}/${name}: ${what} has the neutral tone of a status line`);
      if (!look.mark) fail('distinct', `${theme}/${name}: ${what} has no mark (icon) in the bar`);
      if (look.background === idle.background) fail('distinct', `${theme}/${name}: ${what} has the same bar colour as "Ready"`);
      if (look.weight < 600) fail('distinct', `${theme}/${name}: the first line of ${what} is not heavier than a status (${look.weight})`);
      if (look.edge === 'none') fail('distinct', `${theme}/${name}: ${what} has no coloured edge`);
      if (isFailure && !look.button && !/drop-refused/.test(name)) fail('distinct', `${theme}/${name}: ${what} offers no button that can succeed`);
      if (isFailure && look.button && !look.button.filled && !/drop-refused/.test(name)) fail('distinct', `${theme}/${name}: the button of a failure is not the filled one`);
    }
    const making = looks['17-making'] as BarLook;
    if (making.progressWide === null || making.progressWide < 0.95) fail('distinct', `${theme}: the progress bar spans ${making.progressWide === null ? 'nothing' : `${Math.round(making.progressWide * 100)}%`} of the status bar, not its full width`);
    if (making.text.match(/(\d+)%.*\1%/)) fail('distinct', `${theme}: the percent is said twice in "${making.text}"`);
    const hold = new Set(Object.values(looks).map((l) => Math.round(l.height)));
    if (hold.size !== 1) fail('distinct', `${theme}: the status bar has more than one height across these states (${[...hold].join(', ')})`);
    out[theme] = { states: Object.keys(looks).length, barHeight: [...hold][0] };
  }
  report.gates.distinct = out;
}

// ------------------------------------------------------------- messages ---
// When a file is the problem the controls say so too: the row names the problem, the preview says it, Make Video waits, the
// enlarge note goes; a tool that is missing never says "Ready".

async function messagesGate(): Promise<void> {
  const out: Record<string, unknown> = {};
  const seen = (page: Page) =>
    page.evaluate(() => ({
      make: (document.getElementById('make-video') as HTMLButtonElement | null)?.disabled ?? null,
      note: (document.querySelector('[data-enlarge-note]')?.textContent ?? '').trim(),
      problemRows: [...document.querySelectorAll('[data-problem]')].map((el) => (el.getAttribute('data-file') ?? 'words') + ':' + (el.textContent ?? '').trim()),
      frame: (document.querySelector('[data-preview-words]')?.textContent ?? '').trim(),
      bar: (document.querySelector('[data-status-text]')?.textContent ?? '').trim(),
      output: (document.querySelector('[data-output]')?.textContent ?? '').trim(),
    }));
  const cases: [string, 'audio' | 'image' | null][] = [
    ['23-error-audio-not-found', 'audio'],
    ['24-error-image-not-found', 'image'],
    ['25-error-audio-unreadable', 'audio'],
    ['26-error-image-unreadable', 'image'],
    ['27-error-image-too-small', 'image'],
    ['16-preview-failed', 'image'],
  ];
  for (const [name, slot] of cases) {
    await inState(name, VIEW, async (page) => {
      const v = await seen(page);
      out[name] = v;
      if (v.make !== true) fail('messages', `${name}: Make Video is enabled while the bar says the ${slot} is the problem ("${v.bar}")`);
      if (slot === 'image' && v.note) fail('messages', `${name}: the enlarge note ("${v.note}") is shown beside "${v.bar}"`);
      if (!v.problemRows.some((r) => r.startsWith(`${slot}:`))) fail('messages', `${name}: the ${slot} row does not say that file is the problem (${v.problemRows.join(' | ') || 'nothing marked'})`);
      if (slot === 'image' && !v.frame) fail('messages', `${name}: the preview shows no words for an image that cannot be drawn`);
      if (/^Ready|^Choose a song/.test(v.bar)) fail('messages', `${name}: the bar says "${v.bar}"`);
    });
  }
  await inState('13-original-too-small', VIEW, async (page) => {
    const v = await seen(page);
    out['13-original-too-small'] = v;
    if (v.make !== true) fail('messages', '13-original-too-small: Make Video is enabled for an image that is too small');
    if (/^Ready/.test(v.bar) || !/too small/.test(v.bar)) fail('messages', `13-original-too-small: the bar says "${v.bar}", not what blocks Make Video`);
    if (/not available/.test(v.output)) fail('messages', `13-original-too-small: the row says "${v.output}", which tells nothing`);
  });
  for (const name of ['38-tool-missing', '39-tool-turns-missing']) {
    await inState(name, VIEW, async (page) => {
      const v = await seen(page);
      out[name] = v;
      if (/Ready|Choose a song|Choose an image/.test(v.bar)) fail('messages', `${name}: the bar says "${v.bar}" on a screen that can make nothing`);
      if ((await page.locator('#make-video').count()) !== 0) fail('messages', `${name}: a Make Video button is still there`);
    });
  }
  // After the problem file is replaced, the controls come back by themselves.
  await inState('23-error-audio-not-found', VIEW, async (page) => {
    await page.keyboard.press('Control+o');
    await page.waitForFunction(() => !document.querySelector('[data-problem]'));
    const v = await seen(page);
    if (v.make !== false) fail('messages', 'after a new song replaced the one that was not found, Make Video is still disabled');
  });
  report.gates.messages = out;
}

// ----------------------------------------------------------------- ring ---
// The focus ring is for the keyboard (must-fix 10): none on the first paint, none after a mouse action, none in a window that is not
// active; it appears at once with the first key. And a row's label does not change when its control is focused.

async function ringGate(): Promise<void> {
  const out: Record<string, unknown> = {};
  const ring = (page: Page) =>
    page.evaluate(() => {
      const el = document.activeElement as HTMLElement | null;
      if (!el || el === document.body) return { element: null, shown: false };
      const s = getComputedStyle(el);
      return { element: el.id || el.getAttribute('aria-label') || el.tagName, shown: s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) > 0 };
    });
  const labels = (page: Page) => page.evaluate(() => [...document.querySelectorAll('.row-label')].map((l) => getComputedStyle(l).color).join('|'));
  for (const theme of ['dark', 'light'] as const) {
    const { context, page } = await openPage(browser, { ...VIEW, theme });
    await load(page, url);
    await page.waitForFunction(() => document.activeElement?.id === 'choose-audio');
    const first = await ring(page);
    if (first.element !== 'choose-audio') fail('ring', `${theme}: the window did not start on Choose Audio (${first.element})`);
    if (first.shown) fail('ring', `${theme}: a focus ring shows on the first paint`);
    const baseline = await labels(page);
    await page.locator('[data-group="shape"] [data-value="1:1"]').click();
    const afterClick = await ring(page);
    if (afterClick.shown) fail('ring', `${theme}: a focus ring shows after a mouse click on ${afterClick.element}`);
    if ((await labels(page)) !== baseline) fail('ring', `${theme}: a row label changed colour when its control took focus`);
    await page.keyboard.press('Tab');
    const afterTab = await ring(page);
    if (!afterTab.shown) fail('ring', `${theme}: no focus ring shows on ${afterTab.element} after Tab`);
    if ((await labels(page)) !== baseline) fail('ring', `${theme}: a row label changed colour when a key moved focus into its row`);
    await page.evaluate(() => window.dispatchEvent(new Event('blur')));
    const inactive = await ring(page);
    if (inactive.shown) fail('ring', `${theme}: a focus ring shows in a window that is not active`);
    await page.evaluate(() => window.dispatchEvent(new Event('focus')));
    await page.mouse.move(10, 10);
    await page.mouse.move(40, 12);
    if ((await ring(page)).shown) fail('ring', `${theme}: the ring stays after the pointer moves`);
    out[theme] = { first, afterClick, afterTab: afterTab.shown, inactive: inactive.shown };
    await context.close();
  }
  report.gates.ring = out;
}

// ---------------------------------------------------------------- theme ---
// A run that says "light" shows the light theme (S2V-031: light pictures and light audits were the dark ones for a whole ticket).

async function themeGate(): Promise<void> {
  const out: Record<string, unknown> = {};
  const read = async (theme: 'light' | 'dark') => {
    const { context, page } = await openPage(browser, { ...VIEW, theme });
    await load(page, url);
    const look = await page.evaluate(() => ({ theme: document.documentElement.dataset.theme, background: getComputedStyle(document.body).backgroundColor, card: getComputedStyle(document.querySelector('.card') as Element).backgroundColor, scheme: getComputedStyle(document.documentElement).colorScheme }));
    await context.close();
    return look;
  };
  const light = await read('light');
  const dark = await read('dark');
  out.light = light;
  out.dark = dark;
  if (light.theme !== 'light') fail('theme', `a page opened for the light theme shows "${light.theme}"`);
  if (dark.theme !== 'dark') fail('theme', `a page opened for the dark theme shows "${dark.theme}"`);
  if (light.background === dark.background || light.card === dark.card) fail('theme', 'the light and the dark themes paint the same colours');
  // The toggle switches both ways and the choice survives a reload.
  const { context, page } = await openPage(browser, VIEW);
  await load(page, url);

  await page.locator('[aria-label="Use the light theme"]').click();
  await page.waitForFunction(() => document.documentElement.dataset.theme === 'light');
  await page.reload();
  await page.waitForSelector('.app');
  if ((await page.evaluate(() => document.documentElement.dataset.theme)) !== 'light') fail('theme', 'the light theme did not survive a reload');
  await context.close();
  report.gates.theme = out;
}

// ------------------------------------------------------------------ run ---

// AUDIT_ONLY=job,files runs just those gates while one is being worked on; a full run, with it unset, is the gate.
const only = process.env['AUDIT_ONLY']?.split(',').filter(Boolean);
const gate = async (name: string, run: () => unknown): Promise<void> => {
  if (!only || only.includes(name)) await run();
};

try {
  await gate('css', cssGate);
  await gate('motion', motionGate);
  await gate('list', listGate);
  await gate('states', stateGates);
  await gate('forced', forcedGate);
  await gate('tokens', tokensGate);
  await gate('overflow', overflowGate);
  await gate('restore', restoreGate);
  await gate('journeys', journeyGate);
  await gate('shortcuts', shortcutsGate);
  await gate('overlay', overlayGate);
  await gate('job', jobGate);
  await gate('crop', cropGate);
  await gate('files', filesGate);
  await gate('tool', toolGate);
  await gate('notices', noticesGate);
  await gate('theme', themeGate);
  await gate('distinct', distinctGate);
  await gate('messages', messagesGate);
  await gate('ring', ringGate);
} catch (error) {
  fail('audit', `the audit itself failed: ${(error instanceof Error ? (error.stack ?? error.message) : String(error)).split('\n').slice(0, 3).join(' ')}`);
} finally {
  await browser.close();
  await close();
}

report.failures = failures;
report.passed = failures.length === 0;
await writeFile(join(root, 'qa', 'audit.json'), JSON.stringify(report, null, 2));

const g = report.gates;
console.log(`css        ${g.css?.declarationsRead ?? 0} declarations, longest ${g.css?.longestMs ?? '?'} ms, self-test ${g.css?.selfTest ?? 'not run'}`);
console.log(`list       ${g.list ? `not applicable: ${g.list.rowsSeen} rows drawn` : 'not run'}`);
console.log(`axe        ${g.axe ? `${g.axe.violations} violations in ${g.axe.statesChecked} state and theme runs` : 'not run'}`);
console.log(`focus      ${g.focus?.focusableElementsChecked ?? 0} focus checks; names ${g.names?.interactiveElementsChecked ?? 0}; smallest text ${g.text?.smallestTextPx ?? '?'} px`);
console.log(`forced     ${g.forced ? `${g.forced.focusableElementsChecked} focus checks in ${g.forced.stateAndThemeRuns} state and theme runs under forced colours` : 'not run'}`);
console.log(`tokens     ${g.tokens ? `${g.tokens.linesRead} lines in ${g.tokens.filesRead} files, themes ${g.tokens.themes.join(', ')}` : 'not run'}`);
console.log(`overflow   ${g.overflow ? Object.keys(g.overflow).length : 0} layout cases at ${SIZES.length} sizes, spill and stable checked in each`);
console.log(`restore    ${g.restore ? `reload ${g.restore.restoredAfterReload}, corrupt storage ${g.restore.survivesCorruptStorage}, HEVC where it cannot be made ${g.restore.hevcStartsOnH264Where}, comes back ${g.restore.hevcComesBack}` : 'not run'}`);
console.log(`journeys   ${g.journeys ? Object.entries(g.journeys).map(([id, j]) => `${id} ${j.steps}/${j.stepBudget} steps`).join(', ') : 'not run'}`);
console.log(`shortcuts  ${g.shortcuts ? Object.entries(g.shortcuts).map(([p, r]) => `${p}: ${r.withShortcut} of ${r.commands} commands, ${r.worked.length} worked`).join('; ') : 'not run'}`);
console.log(`overlay    ${g.overlay ? Object.entries(g.overlay).map(([p, r]) => `${p}: typed into the palette "${r.query}"`).join('; ') : 'not run'}`);
console.log(`job        ${g.job ? `cancel acknowledged as "${g.job.cancelAcknowledged}", ${Object.keys(g.job).filter((k) => k.startsWith('row:')).length} rows of the error table, repeated failure "${g.job.secondFailure?.text ?? ''}"` : 'not run'}`);
console.log(`crop       ${g.crop ? 'slider, keys, drag, reset and edges checked' : 'not run'}`);
console.log(`files      ${g.files ? 'drop, Replace question, refused drops, highlight and a second launch checked' : 'not run'}`);
console.log(`tool       ${g.tool ? 'the missing-tool state, at launch and after it' : 'not run'}`);
console.log(`theme      ${g.theme ? 'light and dark are painted differently, the choice survives a reload' : 'not run'}`);
console.log(`distinct   ${g.distinct ? 'a failure, a refusal and a saved video are not a status line; progress spans the bar; one bar height' : 'not run'}`);
console.log(`messages   ${g.messages ? 'when a file is the problem the row, the preview, the bar, Make Video and the note agree' : 'not run'}`);
console.log(`ring       ${g.ring ? 'no focus ring on first paint, after a click or in an inactive window; one with the keyboard' : 'not run'}`);
console.log(`notices    ${g.notices ? 'the exemption covers the notices and nothing else' : 'not run'}`);
if (failures.length) {
  console.error(`\naudit FAILED: ${failures.length} failure(s)`);
  console.error(failures.join('\n'));
  process.exit(1);
}
console.log('\naudit passed');
