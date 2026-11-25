// The stand-in for the desktop shell. It implements DesktopBridge in a plain browser so the page,
// the headless audit and the screenshot script can reach every state without Electron or the
// tool. It is loaded only when `window.desktop` is absent (src/desktop.ts), as its own chunk.
//
// The parts every stand-in needs (call log, menu hook, storage, timers, address options) come
// from @uppercut-labs/electron-bridge-test-double; this file holds Song2Vid's fixtures. Its
// dialogs answer at once with generated files, the way the shell's would answer with a chosen
// one, so a script reaches "both files chosen" with Ctrl+O and Ctrl+Shift+O.
//
// The scenario comes from the address's fragment, so every state can be opened and photographed
// directly:
//
//   #fixture=default
//   #fixture=make-fail-output_in_use&image=small&platform=macos
//
// Fixtures (one per state the app can be in; one `make-fail-<code>` for each row of SPEC 27.5):
//
//   default                the tool is ready, every Encoder works, and a video is made in about 1.2 s
//   no-hevc                this computer cannot make HEVC (SPEC 23)
//   tool-damaged           the tool is missing at launch: the one blocking state
//   tool-damaged-late      ready at launch, then the version check overturns the cached answer
//   make-hold              a job runs and holds at 40% while encoding, with time left
//   make-hold-early        a job holds while preparing, with no percent
//   make-stalled           a job holds with no line for 30 s: "Still working…"
//   make-done              a job finishes at once
//   make-fallback          a job finishes after the first Encoder failed (SPEC 23)
//   make-slow-cancel       a job that takes a moment to answer Cancel (so "Cancelling" can be seen)
//   make-ignore-cancel     a job that never answers Cancel (for the "Cancelling" state)
//   make-dismissed         the save dialog is closed without a choice
//   make-fail-<code>       a job fails with this code, every time (any SPEC 27.5 code, or one the page does not know)
//   choose-fail-<code>     the open dialog's file fails its check with this code
//
// Options, added with `&`:
//
//   platform=windows|macos|linux   what bootstrap() reports (default windows)
//   image=wide|tall|square|small|tiny|huge   the image the open dialog gives (default wide, 1600x900)
//   preview=slow|failed            the preview takes 1.5 s, or fails
//
// For the scripts only: every call is appended to `window.__desktopCalls`, the last menu state
// is `window.__menuState`, `window.__menuCommand(id)` sends a command as the shell's menu would,
// and `window.__openFiles(["Song.mp3", "Cover.png"])` hands files over as a second launch would.
import { createBridgeHarness, instrument, parseHashParams } from '@uppercut-labs/electron-bridge-test-double';
import type { AudioInfo, Bootstrap, Codec, DesktopBridge, DropResult, EncoderName, EncoderReport, FrameRow, ImageInfo, JobUpdate, MakeRequest, MakeStart, PreviewResult, Problem } from './bridge';
import { outputFrame, SHAPES, TIERS } from './state/frame';
import type { Resolution } from './bridge';

const NOTICES = `Third-party notices

Song2Vid for Windows uses FFmpeg to read songs and pictures and to write the video.

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later (LGPL).
Its source code, and the one configure line this copy was built with, are at
https://ffmpeg.org/ and in the repository named under About.
This copy contains no GPL or non-free parts: no x264, no x265.

The app's window is built on Electron and Chromium, whose notices are in LICENSE and
LICENSES.chromium.html beside the program.
`;

const IMAGES: Record<string, { name: string; width: number; height: number }> = {
  wide: { name: 'Cover.png', width: 1600, height: 900 },
  tall: { name: 'Poster.png', width: 900, height: 1600 },
  square: { name: 'Square.png', width: 1200, height: 1200 },
  small: { name: 'Thumbnail.png', width: 320, height: 240 },
  tiny: { name: 'Dot.png', width: 15, height: 16 },
  huge: { name: 'A very long photograph name that keeps going past the edge of its line.png', width: 4032, height: 3024 },
};

const AUDIO_EXTENSIONS = ['mp3', 'm4a', 'aac', 'wav', 'aif', 'aiff', 'flac', 'alac', 'caf'];
const IMAGE_EXTENSIONS = ['jpg', 'jpeg', 'png', 'heic', 'heif', 'tif', 'tiff', 'webp', 'gif', 'bmp'];

/** The Encoder report the tool would give. */
const ENCODERS: EncoderReport = { h264: { available: true, encoder: 'nvenc' }, hevc: { available: true, encoder: 'nvenc' } };
const ENCODERS_NO_HEVC: EncoderReport = { h264: { available: true, encoder: 'software' }, hevc: { available: false, encoder: null } };

/** The table `check` gives for an image (SPEC 14.3), from the same arithmetic the page draws with. */
function framesFor(width: number, height: number): FrameRow[] {
  const rows: FrameRow[] = [];
  for (const shape of SHAPES) {
    if (shape === 'original') {
      const frame = outputFrame({ width, height }, 'original', '1080p');
      rows.push({ shape, resolution: null, width: frame?.size.width ?? null, height: frame?.size.height ?? null, placement: frame ? 'fit' : null, enlarged: false });
      continue;
    }
    for (const tier of TIERS) {
      const frame = outputFrame({ width, height }, shape, tier);
      rows.push({ shape, resolution: tier as Resolution, width: frame?.size.width ?? null, height: frame?.size.height ?? null, placement: shape === '1:1' || shape === '4:3' ? 'crop' : 'fit', enlarged: frame?.enlarged ?? false });
    }
  }
  return rows;
}

/** A flat-coloured cover drawn from numbers, so the preview has something to place and the tokens gate has no colour literal to read. */
function coverPicture(width: number, height: number): string {
  const w = Math.min(640, width);
  const h = Math.max(1, Math.round((w * height) / width));
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const context = canvas.getContext('2d');
  if (!context) return '';
  const data = context.createImageData(w, h);
  const cx = w / 2;
  const cy = h / 2;
  const radius = Math.min(w, h) * 0.3;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const at = (y * w + x) * 4;
      const inside = (x - cx) ** 2 + (y - cy) ** 2 < radius ** 2;
      const left = x < cx;
      const top = y < cy;
      const color = inside ? [244, 196, 74] : left ? (top ? [52, 96, 170] : [38, 142, 128]) : top ? [196, 74, 92] : [92, 68, 148];
      data.data[at] = color[0] ?? 0;
      data.data[at + 1] = color[1] ?? 0;
      data.data[at + 2] = color[2] ?? 0;
      data.data[at + 3] = 255;
    }
  }
  context.putImageData(data, 0, 0);
  return canvas.toDataURL('image/png');
}

const extensionOf = (name: string): string => name.slice(name.lastIndexOf('.') + 1).toLowerCase();

export function createFakeBridge(storagePrefix: string): DesktopBridge {
  const h = createBridgeHarness({ storagePrefix });
  const params = parseHashParams();
  const fixture = params.get('fixture') ?? 'default';
  const platform = h.option('platform', ['windows', 'macos', 'linux'] as const, 'windows');
  const imageKind = h.option('image', ['wide', 'tall', 'square', 'small', 'tiny', 'huge'] as const, 'wide');
  const previewMode = h.option('preview', ['normal', 'slow', 'failed'] as const, 'normal');
  const jobUpdates = h.channel<JobUpdate>('job');
  const encoderReports = h.channel<EncoderReport>('encoders');
  const toolStatuses = h.channel<Bootstrap['tool']>('tool');
  const opened = h.channel<DropResult>('opened');
  const saved = h.storage.load();
  const prefsKey = `${storagePrefix}.preferences.v1`;
  const readCodec = (): Codec => {
    try {
      const value = (JSON.parse(saved[prefsKey] ?? '{}') as { codec?: unknown }).codec;
      return value === 'hevc' ? 'hevc' : 'h264';
    } catch {
      return 'h264';
    }
  };

  let ids = 0;
  let jobs = 0;
  let running: string | null = null;
  let saves = 0;
  const released: string[] = [];
  const later = (ms: number, run: () => void) => void h.scheduler.after(ms, run);
  const emit = (update: JobUpdate) => {
    if (update.state !== 'running') running = null;
    jobUpdates.emit(update);
  };
  const problem = (code: string): Problem => ({ code, details: JSON.stringify({ code, message: 'stand-in failure', details: {} }, null, 2) });

  const encoders = fixture === 'no-hevc' ? ENCODERS_NO_HEVC : ENCODERS;

  function audioInfo(name = 'Song.mp3'): AudioInfo {
    return { id: `f_audio${++ids}`, name, durationSeconds: 144 };
  }
  function imageInfo(spec: { name: string; width: number; height: number } = IMAGES[imageKind] ?? IMAGES['wide']!): ImageInfo {
    return { id: `f_image${++ids}`, name: spec.name, width: spec.width, height: spec.height, frames: framesFor(spec.width, spec.height) };
  }

  /** The file the dialog "chooses" for a file kind, or the failure its check gives (SPEC 14.6). */
  const failing = (kind: 'audio' | 'image'): string | null => {
    const prefix = 'choose-fail-';
    if (!fixture.startsWith(prefix)) return null;
    const code = fixture.slice(prefix.length);
    return code.startsWith(`${kind}_`) ? code : null;
  };

  /** A drop, judged as the shell judges it: by type, in the Mac app's order, then each file. */
  function judge(files: { name: string; type: string; size: number }[]): DropResult {
    if (files.some((f) => f.size === 0 && f.type === '' && !f.name.includes('.'))) return { status: 'rejected', reason: 'folder' };
    if (files.length > 2) return { status: 'rejected', reason: 'too-many' };
    const kinds = files.map((f) => (AUDIO_EXTENSIONS.includes(extensionOf(f.name)) ? 'audio' : IMAGE_EXTENSIONS.includes(extensionOf(f.name)) ? 'image' : 'other'));
    if (kinds.includes('other')) return { status: 'rejected', reason: 'unsupported' };
    if (kinds.filter((k) => k === 'audio').length > 1) return { status: 'rejected', reason: 'more-audio' };
    if (kinds.filter((k) => k === 'image').length > 1) return { status: 'rejected', reason: 'more-images' };
    if (fixture.startsWith('drop-unreadable')) return { status: 'rejected', reason: 'unreadable' };
    const song = files.find((_, i) => kinds[i] === 'audio');
    const picture = files.find((_, i) => kinds[i] === 'image');
    const spec = picture ? (Object.values(IMAGES).find((i) => i.name === picture.name) ?? { ...(IMAGES[imageKind] ?? IMAGES['wide']!), name: picture.name }) : null;
    return { status: 'ok', audio: song ? audioInfo(song.name) : null, image: spec ? imageInfo({ ...spec, name: picture?.name ?? spec.name }) : null };
  }

  const hook = globalThis as unknown as { __openFiles?: (names: string[]) => void; __released?: string[] };
  hook.__released = released;
  hook.__openFiles = (names) => opened.emit(judge(names.map((name) => ({ name, type: '', size: 1 }))));

  const startJob = (request: MakeRequest): MakeStart => {
    if (running) return { status: 'busy' };
    if (fixture === 'make-dismissed' && request.destination === 'ask') return { status: 'dismissed' };
    const jobId = `job-${++jobs}`;
    running = jobId;
    saves += 1;
    const step = (stage: 'checking' | 'preparing' | 'encoding' | 'finishing', percent: number | null, elapsed: number, remaining: number | null, encoder: EncoderName | null = encoders[request.codec].encoder, stalled = false) =>
      emit({ jobId, state: 'running', stage, percent, elapsedSeconds: elapsed, remainingSeconds: remaining, encoder: stage === 'encoding' || stage === 'finishing' ? encoder : null, stalled });
    const done = () =>
      emit({
        jobId,
        state: 'done',
        result: {
          outputId: `f_out${jobs}`,
          fileName: 'Song.mp4',
          where: 'Videos',
          width: 1920,
          height: 1080,
          durationSeconds: 144,
          bytes: 15_000_000,
          codec: request.codec,
          encoder: encoders[request.codec].encoder ?? 'software',
          encoderFallback: fixture === 'make-fallback',
        },
      });
    later(0, () => {
      step('checking', null, 0, null);
      if (fixture.startsWith('make-fail-')) {
        const code = fixture.slice('make-fail-'.length);
        later(120, () => step('preparing', null, 0.1, null));
        later(260, () => emit({ jobId, state: 'failed', problem: problem(code) }));
        return;
      }
      if (fixture === 'make-hold') return later(80, () => step('encoding', 40, 6, 9));
      if (fixture === 'make-hold-early') return later(80, () => step('preparing', null, 1, null));
      if (fixture === 'make-stalled') return later(80, () => step('encoding', 40, 31, null, 'nvenc', true));
      if (fixture === 'make-ignore-cancel') return later(80, () => step('encoding', 20, 3, 12));
      if (fixture === 'make-slow-cancel') return later(80, () => step('encoding', 20, 3, 12));
      if (fixture === 'make-done' || fixture === 'make-fallback') return later(60, done);
      later(250, () => step('preparing', null, 0.3, null));
      later(500, () => step('encoding', 12, 1.2, 9));
      later(800, () => step('encoding', 55, 2.3, 4));
      later(1100, () => step('finishing', 99, 3.1, 0));
      later(1200, done);
    });
    return { status: 'started', jobId };
  };

  const bridge: DesktopBridge = {
    async bootstrap(): Promise<Bootstrap> {
      const damaged = fixture === 'tool-damaged';
      return {
        stored: saved,
        platform,
        preferences: { codec: readCodec() },
        about: { appVersion: '1.2.0', dataDir: 'Kept on this computer' },
        tool: damaged ? { state: 'damaged', code: 'TOOL_NOT_FOUND', details: 'TOOL_NOT_FOUND\nNo runnable song2vid.exe was found (stand-in).' } : { state: 'ready', code: null, details: 'song2vid 1.2.0 (stand-in)' },
        encoders: damaged ? null : encoders,
      };
    },
    setTheme() {},
    saveState(key, json) {
      h.storage.save(key, json);
    },
    setPreferences(update) {
      if (update.codec === 'h264' || update.codec === 'hevc') {
        saved[prefsKey] = JSON.stringify({ codec: update.codec });
        h.storage.save(prefsKey, saved[prefsKey]);
      }
    },

    async chooseAudio() {
      const code = failing('audio');
      if (code) return { status: 'unusable', problem: problem(code) };
      return { status: 'chosen', file: audioInfo() };
    },
    async chooseImage() {
      const code = failing('image');
      if (code) return { status: 'unusable', problem: problem(code) };
      return { status: 'chosen', file: imageInfo() };
    },
    async dropFiles(files) {
      return judge(Array.from(files, (f) => ({ name: f.name, type: f.type, size: f.size })));
    },
    onFilesOpened: (listener) => opened.add(listener),
    releaseFiles(list) {
      released.push(...list);
    },
    async previewImage(): Promise<PreviewResult> {
      if (previewMode === 'slow') await h.scheduler.wait(1500);
      if (previewMode === 'failed') return { status: 'failed', problem: problem('image_unreadable') };
      const spec = IMAGES[imageKind] ?? IMAGES['wide']!;
      const src = coverPicture(spec.width, spec.height);
      return { status: 'ready', src, width: Math.min(2048, spec.width), height: Math.round((Math.min(2048, spec.width) * spec.height) / spec.width) };
    },
    onEncoders: (listener) => encoderReports.add(listener),
    onToolStatus: (listener) => {
      if (fixture === 'tool-damaged-late') later(300, () => toolStatuses.emit({ state: 'damaged', code: 'TOOL_INCOMPATIBLE', details: 'TOOL_INCOMPATIBLE\nsong2vid 1.1.0 (stand-in)' }));
      return toolStatuses.add(listener);
    },

    async makeVideo(request) {
      return startJob(request);
    },
    cancelJob(jobId) {
      if (running !== jobId) return;
      if (fixture === 'make-ignore-cancel') return;
      h.scheduler.cancelAll();
      later(fixture === 'make-slow-cancel' ? 600 : 120, () => emit({ jobId, state: 'cancelled' }));
    },
    onJob: (listener) => jobUpdates.add(listener),
    showInFolder() {},

    openLink() {},
    async notices() {
      return NOTICES;
    },
    onMenuCommand: (listener) => h.menuCommands.add(listener),
    setMenuState: (enabled) => h.menu.setMenuState(enabled),
  };
  // Every call is logged first; saveState logs only its key, as the document can be large; a drop logs its names, never the files.
  return instrument(bridge, h.log, { saveState: (args) => [args[0]], dropFiles: (args) => [Array.from(args[0] as File[], (f) => f.name)] });
}
