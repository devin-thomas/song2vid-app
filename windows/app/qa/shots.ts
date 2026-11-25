// Captures every state at the app's default and minimum window, two device scales, the dark theme (and
// light in a full run) and every system's key family, headless. These pictures are what the independent
// critic gets: screenshots only, never the code, the audit or the builder's notes. Each state opens on a
// fixture of the stand-in bridge (src/bridge.fake.ts); the states are in qa/states.ts, the same list the
// audit checks, so every designed state is photographed.
// Usage: node qa/shots.ts [outDir] [--quick]
//   --quick  the default size, the minimum size and the default at 125% (for critique rounds and qa/visual.ts)
//            Every state at the main size; the secondary sets (each system's labels, forced colours, 200%
//            zoom, the light theme) take the CORE states of qa/states.ts, which keeps the baselines to a
//            size that can be reviewed.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { mkdir } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { launch, load, modFor, openPage, park, readConfig, root, serve, settle } from './lib.ts';
import type { PageOptions } from './lib.ts';
import { STATES } from './states.ts';
import type { State } from './states.ts';

const W = readConfig().window;

const args = process.argv.slice(2);
const quick = args.includes('--quick');
const outDir = join(root, args.find((a) => !a.startsWith('--')) ?? 'qa/shots');

// The sizes and scales the main groups are taken at. A full run takes both sizes at both scales; a quick run (the
// one qa/visual.ts compares) takes the default size, the minimum size (480 x 640) and the default at 125%.
const GROUPS: [width: number, height: number, scale: number][] = quick
  ? [[W.width, W.height, 1], [W.minWidth, W.minHeight, 1], [W.width, W.height, 1.25]]
  : [[W.width, W.height, 1], [W.width, W.height, 1.25], [W.minWidth, W.minHeight, 1], [W.minWidth, W.minHeight, 1.25]];
// The page is the same on every system except the title bar inset and the key labels.
const PLATFORMS = quick ? ['windows', 'macos'] : ['windows', 'macos', 'linux'];
// Dark is the default theme (D-020) and takes every state; light, a choice the person made, takes the core states.
const THEMES = ['dark', 'light'] as const;

const ALL = Object.entries(STATES);
const CORE = ALL.filter(([, state]) => state.core);

const zoomDir = join(outDir, `zoom-200-of-${W.width}x${W.height}`);

const { url, close } = await serve();
const { browser, channel } = await launch();
console.log(`serving ${url}, browser channel ${channel}, writing ${outDir}`);
let count = 0;
const problems: string[] = [];

async function capture(dir: string, name: string, state: State, options: PageOptions, platform = 'windows'): Promise<void> {
  const { context, page, errors } = await openPage(browser, options);
  try {
    await load(page, url, state.fixture, [`platform=${platform}`, state.extra].filter(Boolean).join('&'));
    await state.run(page, modFor(platform));
    await park(page);
    await settle(page);
    // Under forced colours a button that was disabled and enabled again redraws its border one beat after the
    // animations have ended (it showed in 4 of 130 pictures, a different four each run): wait it out.
    // S2V-031: it still showed, as one button's border caught half-way between two system colours (a 266-pixel difference, a different
    // picture each run). Transitions are ended outright for these pictures: a transition in flight jumps to its end value.
    if (options.forcedColors === 'active') {
      await page.addStyleTag({ content: '*, *::before, *::after { transition: none !important; }' });
      // A button that was disabled and enabled again keeps its old border until something repaints it: make everything repaint.
      await page.evaluate(async () => {
        document.body.style.visibility = 'hidden';
        void document.body.offsetHeight;
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
        document.body.style.visibility = '';
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
      });
      await page.waitForTimeout(400);
    }
    // animations: 'disabled' finishes every CSS animation and transition before the capture, so
    // two runs of the same state give the same picture (an entrance caught mid-way differed by
    // up to 95% between identical runs; qa/visual.ts compares these pictures).
    await page.screenshot({ path: join(dir, `${name}.png`), animations: 'disabled' });
    count += 1;
  } catch (error) {
    problems.push(`${name} ${JSON.stringify(options)}: ${String(error).split('\n')[0]}`);
  }
  if (errors.length) problems.push(`${name}: page errors: ${errors.join(' | ')}`);
  await context.close();
}

try {
  for (const [width, height, scale] of GROUPS) {
    for (const theme of THEMES) {
      // A quick run takes the default size at 125% in the dark theme only.
      if (quick && scale !== 1 && theme === 'light') continue;
      const dir = join(outDir, `${width}x${height}@${scale}x-${theme}`);
      await mkdir(dir, { recursive: true });
      // The default size takes every state in the dark theme; the other sizes, scales and the light theme take the core states.
      const states = width === W.width && scale === 1 && theme === 'dark' ? ALL : CORE;
      for (const [name, state] of states) await capture(dir, name, state, { width, height, scale, theme });
    }
  }
  // Every system's labels and title bar inset, at the default size in the dark theme.
  for (const platform of PLATFORMS) {
    const dir = join(outDir, `${platform}-${W.width}x${W.height}-dark`);
    await mkdir(dir, { recursive: true });
    for (const [name, state] of CORE) await capture(dir, name, state, { width: W.width, height: W.height, scale: 1, theme: 'dark' }, platform);
  }
  // A system contrast theme (forced colours), on a dark and a light system, at the default size.
  for (const theme of ['dark', 'light'] as const) {
    const dir = join(outDir, `forced-colors-${W.width}x${W.height}-${theme}`);
    await mkdir(dir, { recursive: true });
    for (const [name, state] of CORE) await capture(dir, name, state, { width: W.width, height: W.height, scale: 1, theme, forcedColors: 'active' });
  }
  // The 200% zoom case: the default window zoomed to 200% lays out at half its size in CSS px.
  await mkdir(zoomDir, { recursive: true });
  for (const theme of THEMES) {
    for (const [name, state] of CORE) await capture(zoomDir, `${name}-${theme}`, state, { width: Math.round(W.width / 2), height: Math.round(W.height / 2), scale: 2, theme });
  }
} finally {
  await browser.close();
  await close();
}

console.log(`${count} screenshots written`);

// A light picture that is the dark one again proves nothing about the light theme (S2V-031: for a whole ticket the light pictures
// were byte-identical to the dark ones, because the capture set the browser's colour scheme and the page takes its theme from the
// saved choice). Every light picture must differ from the dark picture of the same state, size and scale; and the zoomed pictures
// carry the theme in their names.
function sameBytes(a: string, b: string): boolean {
  return existsSync(a) && existsSync(b) && readFileSync(a).equals(readFileSync(b));
}
let lightChecked = 0;
for (const dir of readdirSync(outDir).filter((d) => d.endsWith('-light') && d.includes('@'))) {
  const darkDir = join(outDir, dir.replace(/-light$/, '-dark'));
  for (const file of readdirSync(join(outDir, dir))) {
    lightChecked += 1;
    if (sameBytes(join(outDir, dir, file), join(darkDir, file))) problems.push(`${dir}/${file}: the light picture is the dark picture, byte for byte`);
  }
}
for (const file of readdirSync(zoomDir).filter((f) => f.endsWith('-light.png'))) {
  lightChecked += 1;
  if (sameBytes(join(zoomDir, file), join(zoomDir, file.replace(/-light\.png$/, '-dark.png')))) problems.push(`${relative(outDir, zoomDir)}/${file}: the light picture is the dark picture, byte for byte`);
}
console.log(`${lightChecked} light pictures differ from their dark pictures`);
if (lightChecked === 0) problems.push('no light pictures were taken, so the light theme is not photographed');
if (problems.length) {
  console.error(problems.join('\n'));
  process.exit(1);
}
