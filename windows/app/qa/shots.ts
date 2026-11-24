// Captures every state at the app's default and minimum window, two device scales, the dark theme (and
// light in a full run) and every system's key family, headless. These pictures are what the independent
// critic gets: screenshots only, never the code, the audit or the builder's notes. Each state opens on a
// fixture of the stand-in bridge (src/bridge.fake.ts); the states are in qa/states.ts, the same list the
// audit checks, so every designed state is photographed.
// Usage: node qa/shots.ts [outDir] [--quick]
//   --quick  the default size only, one scale (for critique rounds and qa/visual.ts)
//            Every state at the main size; the secondary sets (each system's labels, forced colours, 200%
//            zoom, the light theme) take the CORE states of qa/states.ts, which keeps the baselines to a
//            size that can be reviewed.
import { mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { launch, load, modFor, openPage, park, readConfig, root, serve, settle } from './lib.ts';
import type { PageOptions } from './lib.ts';
import { STATES } from './states.ts';
import type { State } from './states.ts';

const W = readConfig().window;

const args = process.argv.slice(2);
const quick = args.includes('--quick');
const outDir = join(root, args.find((a) => !a.startsWith('--')) ?? 'qa/shots');

const SIZES: [number, number][] = quick ? [[W.width, W.height]] : [[W.width, W.height], [W.minWidth, W.minHeight]];
// The page is the same on every system except the title bar inset and the key labels.
const PLATFORMS = quick ? ['windows', 'macos'] : ['windows', 'macos', 'linux'];
const SCALES = quick ? [1] : [1, 1.25];
// Dark is the default theme (D-020) and takes every state; light, a choice the person made, takes the core states.
const THEMES = ['dark', 'light'] as const;

const ALL = Object.entries(STATES);
const CORE = ALL.filter(([, state]) => state.core);

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
  for (const [width, height] of SIZES) {
    for (const scale of SCALES) {
      for (const theme of THEMES) {
        const dir = join(outDir, `${width}x${height}@${scale}x-${theme}`);
        await mkdir(dir, { recursive: true });
        // The default size takes every state in the dark theme; the other sizes, scales and the light theme take the core states.
        const states = width === W.width && scale === 1 && theme === 'dark' ? ALL : CORE;
        for (const [name, state] of states) await capture(dir, name, state, { width, height, scale, theme });
      }
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
  const zoomDir = join(outDir, `zoom-200-of-${W.width}x${W.height}`);
  await mkdir(zoomDir, { recursive: true });
  for (const theme of THEMES) {
    for (const [name, state] of CORE) await capture(zoomDir, `${name}-${theme}`, state, { width: Math.round(W.width / 2), height: Math.round(W.height / 2), scale: 2, theme });
  }
} finally {
  await browser.close();
  await close();
}

console.log(`${count} screenshots written`);
if (problems.length) {
  console.error(problems.join('\n'));
  process.exit(1);
}
