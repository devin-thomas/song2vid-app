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
// Needs a `make` that works (S2V-026). The media is generated here (a tone as a WAV, flat-coloured PNGs). Writes qa/evidence/real-tool.json; exits 1 on any difference.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { deflateSync } from 'node:zlib';
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

// ---- the media: generated here, from numbers, so nothing from outside the repository is used --------
/** A 16-bit mono WAV of a sine tone: a song Song2Vid reads (SPEC 7). */
function wav(seconds: number, hz = 440, rate = 22050): Buffer {
  const samples = Math.round(seconds * rate);
  const data = Buffer.alloc(samples * 2);
  for (let i = 0; i < samples; i++) data.writeInt16LE(Math.round(Math.sin((2 * Math.PI * hz * i) / rate) * 12000), i * 2);
  const head = Buffer.alloc(44);
  head.write('RIFF', 0);
  head.writeUInt32LE(36 + data.length, 4);
  head.write('WAVEfmt ', 8);
  head.writeUInt32LE(16, 16);
  head.writeUInt16LE(1, 20);
  head.writeUInt16LE(1, 22);
  head.writeUInt32LE(rate, 24);
  head.writeUInt32LE(rate * 2, 28);
  head.writeUInt16LE(2, 32);
  head.writeUInt16LE(16, 34);
  head.write('data', 36);
  head.writeUInt32LE(data.length, 40);
  return Buffer.concat([head, data]);
}

const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc = (buf: Buffer): number => {
  let c = 0xffffffff;
  for (const byte of buf) c = (crcTable[(c ^ byte) & 0xff] ?? 0) ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
/** An 8-bit RGB PNG of four flat colour blocks and a disc, so a crop and a fit show different parts. */
function png(width: number, height: number): Buffer {
  const rows = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const at = y * (width * 3 + 1) + 1 + x * 3;
      const inside = (x - width / 2) ** 2 + (y - height / 2) ** 2 < (Math.min(width, height) * 0.3) ** 2;
      const color = inside ? [244, 196, 74] : x < width / 2 ? (y < height / 2 ? [52, 96, 170] : [38, 142, 128]) : y < height / 2 ? [196, 74, 92] : [92, 68, 148];
      rows[at] = color[0] ?? 0;
      rows[at + 1] = color[1] ?? 0;
      rows[at + 2] = color[2] ?? 0;
    }
  }
  const chunk = (type: string, body: Buffer): Buffer => {
    const length = Buffer.alloc(4);
    length.writeUInt32BE(body.length);
    const typed = Buffer.concat([Buffer.from(type), body]);
    const check = Buffer.alloc(4);
    check.writeUInt32BE(crc(typed));
    return Buffer.concat([length, typed, check]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', deflateSync(rows)), chunk('IEND', Buffer.alloc(0))]);
}

const song = path.join(work, 'Song.wav');
const pictures = { wide: path.join(work, 'Wide.png'), tall: path.join(work, 'Tall.png'), square: path.join(work, 'Square.png') };
fs.writeFileSync(song, wav(3));
fs.writeFileSync(pictures.wide, png(1600, 900));
fs.writeFileSync(pictures.tall, png(900, 1600));
fs.writeFileSync(pictures.square, png(1200, 1200));

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
