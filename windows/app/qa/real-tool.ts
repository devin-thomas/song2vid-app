// The window against the real tool, headless. The built page runs in a headless browser; its bridge
// (`window.desktop`) is the real shell logic, electron/tool/service.ts, running in this process with the
// real adapter and a real `song2vid.exe`; the open and save dialogs are answered with generated files (the
// same seam the shell's development flags use). A person's route is driven by keys: Ctrl+O, Ctrl+Shift+O, a
// Frame Shape, Ctrl+Enter. Then, for each Frame Shape, the same video is made by the command itself with the
// same options, and the two are compared: the pixel size and the length (SPEC 22: length within 0.1 s) and,
// for each Codec asked, the Codec.
//
//   node qa/real-tool.ts --tool-dir <folder with song2vid.exe, ffmpeg.exe, ffprobe.exe>
//   node qa/real-tool.ts --standin          the stand-in tool, to check this script's own plumbing (no video is made)
//
// Needs a `make` that works (S2V-026). Writes qa/evidence/real-tool.json; exits 1 on any difference.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import type { DesktopBridge, DropResult, JobUpdate } from '../src/bridge.ts';
import { makeArgs } from '../electron/tool/contract.ts';
import type { Located } from '../electron/tool/locate.ts';
import { createToolService } from '../electron/tool/service.ts';
import { launch, openPage, root, serve } from './lib.ts';
import { chooseAudio, chooseImage, pickCodec, pickShape, waitStatus } from './states.ts';

const args = process.argv.slice(2);
const standin = args.includes('--standin');
const toolDir = args.find((_a, i) => args[i - 1] === '--tool-dir');
if (!standin && !toolDir) throw new Error('give --tool-dir <folder> or --standin');

const work = fs.mkdtempSync(path.join(os.tmpdir(), 's2v-real-'));
const dataDir = path.join(work, 'data');
const videos = path.join(work, 'Videos');
fs.mkdirSync(videos, { recursive: true });
fs.mkdirSync(dataDir, { recursive: true });
const exe = (name: string) => path.join(toolDir ?? '', `${name}${process.platform === 'win32' ? '.exe' : ''}`);

// ---- the media: made with the bundled FFmpeg, nothing from outside the repository ----------------
const song = path.join(work, 'Song.mp3');
const pictures = { wide: path.join(work, 'Wide.png'), tall: path.join(work, 'Tall.png'), square: path.join(work, 'Square.png') };
if (!standin) {
  const ff = (...a: string[]) => {
    const run = spawnSync(exe('ffmpeg'), ['-y', '-loglevel', 'error', ...a], { encoding: 'utf8' });
    if (run.status !== 0) throw new Error(`ffmpeg ${a.join(' ')}: ${run.stderr}`);
  };
  ff('-f', 'lavfi', '-i', 'sine=frequency=440:duration=3', '-c:a', 'libmp3lame', song);
  ff('-f', 'lavfi', '-i', 'testsrc2=size=1600x900:rate=1', '-frames:v', '1', pictures.wide);
  ff('-f', 'lavfi', '-i', 'testsrc2=size=900x1600:rate=1', '-frames:v', '1', pictures.tall);
  ff('-f', 'lavfi', '-i', 'testsrc2=size=1200x1200:rate=1', '-frames:v', '1', pictures.square);
} else {
  for (const file of [song, ...Object.values(pictures)]) fs.writeFileSync(file, 'x');
}

const located: Located = standin
  ? { ok: true, command: process.execPath, prefixArgs: [path.join(root, 'test', 'standin-tool.ts')], binary: path.join(root, 'test', 'standin-tool.ts'), source: 'override', helpers: {} }
  : { ok: true, command: exe('song2vid'), prefixArgs: [], binary: exe('song2vid'), source: 'development', helpers: { ffmpeg: { file: exe('ffmpeg'), source: 'beside' }, ffprobe: { file: exe('ffprobe'), source: 'beside' } } };

const { url, close } = await serve();
const { browser } = await launch();
const failures: string[] = [];
const results: Record<string, unknown>[] = [];
const fail = (message: string) => failures.push(message);

type Emit = (channel: string, payload: unknown) => void;

/**
 * One case: a page whose bridge is a window onto this process's service, driven by keys. The dialogs answer
 * with the generated files and `savePath`, as the shell's development flags would.
 */
async function runCase(c: (typeof CASES)[number], savePath: string): Promise<void> {
  const { context, page, errors } = await openPage(browser, { width: 560, height: 760 });
  const send: Emit = (channel, payload) => void page.evaluate(([ch, p]) => (window as unknown as { __emit: Emit }).__emit(ch as string, p), [channel, payload] as const).catch(() => undefined);
  const service = createToolService({
    located,
    dataDir,
    ui: { pickFile: async (kind) => (kind === 'audio' ? song : pictures[c.image]), pickSave: async () => savePath, showInFolder: () => {} },
    videosDir: () => videos,
    emit: {
      job: (u: JobUpdate) => send('job', u),
      encoders: (r) => send('encoders', r),
      filesOpened: (r: DropResult) => send('opened', r),
      toolStatus: (st) => send('tool', st),
    },
  });
  service.start();
  await service.settled();
  await page.exposeBinding('__s2v', async (_source, name: string, call: unknown[]) => {
    switch (name) {
      case 'bootstrap':
        return { stored: {}, platform: 'windows', preferences: { codec: 'h264' }, about: { appVersion: '1.2.0', dataDir: '' }, tool: await service.status(), encoders: service.encoders() };
      case 'chooseAudio':
        return service.chooseAudio();
      case 'chooseImage':
        return service.chooseImage();
      case 'previewImage':
        return service.previewImage(call[0]);
      case 'makeVideo':
        return service.makeVideo(call[0]);
      case 'cancelJob':
        return service.cancelJob(call[0]);
      case 'releaseFiles':
        return service.releaseFiles(call[0]);
      case 'notices':
        return '';
      default:
        return null;
    }
  });
  await page.addInitScript(() => {
    const listeners: Record<string, ((p: unknown) => void)[]> = { job: [], encoders: [], tool: [], opened: [] };
    (window as unknown as { __emit: Emit }).__emit = (channel, payload) => (listeners[channel] ?? []).forEach((l) => l(payload));
    const call = (name: string, ...rest: unknown[]) => (window as unknown as { __s2v: (n: string, a: unknown[]) => Promise<never> }).__s2v(name, rest);
    const on = (channel: string) => (listener: (p: never) => void) => {
      listeners[channel]?.push(listener as (p: unknown) => void);
      return () => {};
    };
    const desktop: DesktopBridge = {
      bootstrap: () => call('bootstrap'),
      setTheme: () => {},
      saveState: () => {},
      setPreferences: () => {},
      chooseAudio: () => call('chooseAudio'),
      chooseImage: () => call('chooseImage'),
      dropFiles: () => call('dropFiles'),
      onFilesOpened: on('opened'),
      releaseFiles: (ids) => void call('releaseFiles', ids),
      previewImage: (id) => call('previewImage', id),
      onEncoders: on('encoders'),
      onToolStatus: on('tool'),
      makeVideo: (request) => call('makeVideo', request),
      cancelJob: (id) => void call('cancelJob', id),
      onJob: on('job'),
      showInFolder: () => {},
      openLink: () => {},
      notices: () => call('notices'),
      onMenuCommand: () => () => {},
      setMenuState: () => {},
    };
    (window as unknown as { desktop: DesktopBridge }).desktop = desktop;
  });
  try {
    await page.goto(`${url}/`);
    await page.waitForSelector('.app', { timeout: 8000 }).catch(async (error) => {
      throw new Error(`${String(error).split('\n')[0]} (page errors: ${errors.join(' | ')})`);
    });
    await chooseAudio(page);
    await chooseImage(page);
    await pickShape(page, c.shape);
    if (c.tier) await page.locator(`[data-group="resolution"] [data-value="${c.tier}"]`).click();
    await pickCodec(page, c.codec);
    await page.keyboard.press('Control+Enter');
    await waitStatus(page, 'done', 120_000);
    const said = await page.locator('[data-status-text]').textContent();
    if (!/^Saved .*\.mp4 to /.test(said ?? '')) fail(`${c.shape}: the bar says "${said}"`);
  } catch (error) {
    fail(`${c.shape}: ${String(error).split('\n').slice(0, 3).join(' ')}`);
  }
  if (errors.length) fail(`${c.shape}: page errors: ${errors.join(' | ')}`);
  await context.close();
}

const probe = (file: string) => {
  const run = spawnSync(exe('ffprobe'), ['-v', 'error', '-show_entries', 'stream=codec_name,codec_type,width,height:format=duration', '-of', 'json', file], { encoding: 'utf8' });
  const info = JSON.parse(run.stdout || '{}') as { streams?: { codec_name: string; codec_type: string; width?: number; height?: number }[]; format?: { duration?: string } };
  const video = info.streams?.find((s) => s.codec_type === 'video');
  return { codec: video?.codec_name ?? null, width: video?.width ?? 0, height: video?.height ?? 0, seconds: Number(info.format?.duration ?? 0), tracks: info.streams?.length ?? 0 };
};

const CASES: { shape: string; image: keyof typeof pictures; tier: string | null; codec: 'h264' | 'hevc' }[] = [
  { shape: '16:9', image: 'wide', tier: '480p', codec: 'h264' },
  { shape: '9:16', image: 'tall', tier: '480p', codec: 'h264' },
  { shape: '1:1', image: 'wide', tier: '480p', codec: 'h264' },
  { shape: '4:3', image: 'wide', tier: '480p', codec: 'h264' },
  { shape: 'original', image: 'square', tier: null, codec: 'h264' },
];

try {
  for (const c of CASES.slice(0, Number(process.env['REAL_CASES'] ?? CASES.length))) {
    const viaWindow = path.join(videos, `window-${c.shape.replace(':', 'x')}.mp4`);
    const direct = path.join(videos, `command-${c.shape.replace(':', 'x')}.mp4`);
    await runCase(c, viaWindow);
    if (standin) {
      results.push({ ...c, plumbing: fs.existsSync(viaWindow) || 'the stand-in made no file (expected: it publishes a picture under the output name)' });
      continue;
    }
    const made = spawnSync(exe('song2vid'), makeArgs({ audio: song, image: pictures[c.image], output: direct, shape: c.shape as never, resolution: c.tier as never, crop: c.shape === '1:1' || c.shape === '4:3' ? { h: 0.5, v: 0.5 } : null, codec: c.codec, overwrite: true }).filter((a) => a !== '--cancel-on-eof'), { encoding: 'utf8' });
    if (made.status !== 0) {
      fail(`${c.shape}: the command itself failed (${made.status}): ${made.stdout.slice(0, 300)}`);
      continue;
    }
    const a = probe(viaWindow);
    const b = probe(direct);
    results.push({ ...c, window: a, command: b });
    if (a.width !== b.width || a.height !== b.height) fail(`${c.shape}: the window's video is ${a.width}x${a.height}, the command's ${b.width}x${b.height}`);
    if (Math.abs(a.seconds - b.seconds) > 0.1) fail(`${c.shape}: lengths differ by ${Math.abs(a.seconds - b.seconds).toFixed(3)} s`);
    if (a.codec !== b.codec || a.tracks !== b.tracks) fail(`${c.shape}: codec ${a.codec} against ${b.codec}, ${a.tracks} against ${b.tracks} tracks`);
  }
} finally {
  await browser.close();
  await close();
}

fs.mkdirSync(path.join(root, 'qa', 'evidence'), { recursive: true });
fs.writeFileSync(path.join(root, 'qa', 'evidence', 'real-tool.json'), JSON.stringify({ at: new Date().toISOString(), standin, results, failures, passed: failures.length === 0 }, null, 2));
fs.rmSync(work, { recursive: true, force: true, maxRetries: 20, retryDelay: 100 });
if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}
console.log(`the window and the command agree for ${results.length} Frame Shapes`);
