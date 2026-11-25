// What the shell does for each tool call in src/bridge.ts, without Electron: choose and drop
// files (one-file `check`, SPEC 24.8), the preview (SPEC 24.3), the job (SPEC 14.4, 24), cancel,
// the launch checks (SPEC 27.6) and the job records. electron/tool/index.ts is the thin glue that
// gives it the Windows dialogs, the window and the IPC channels; everything here is tested with
// the stand-in tool (test/service.test.ts) on every system.
//
// The page holds ids. The paths stay in `files`, and the only way a path is made is through `ui`
// (a dialog), a drop or a file opened with the app (SPEC 27.2). Nothing the page sends is passed
// to the tool as it is: a request is read field by field (`readRequest`) and the tool is given
// the arguments `contract.ts` builds from it.
import fs from 'node:fs';
import path from 'node:path';
import type { AudioInfo, ChooseResult, DropResult, EncoderReport, FileId, ImageInfo, JobUpdate, MakeDone, MakeRequest, MakeStart, PreviewResult, Problem, ToolStatus } from '../../src/bridge.ts';
import { stackOf } from '../errors.ts';
import { createAdapter } from './adapter.ts';
import type { Adapter, Limits, ToolError } from './adapter.ts';
import { CODECS, RESOLUTIONS, SHAPES, STAGING_NAME } from './contract.ts';
import { createFileRegistry, judgeDrop } from './files.ts';
import { createJobRecords, newJobId } from './jobs.ts';
import type { JobRecords } from './jobs.ts';
import type { Located } from './locate.ts';
import { createProgressModel } from './progress.ts';
import { createReportCache, toolStatus } from './status.ts';

/** The Windows dialogs and the file manager, as the service needs them. index.ts supplies the real ones. */
export interface ToolUi {
  /** The open dialog, filtered to the section 7 types of `kind`. null when the person closed it. */
  pickFile(kind: 'audio' | 'image'): Promise<string | null>;
  /** The save dialog, starting at `defaultPath`. The system asks before it replaces a file. null when the person closed it. */
  pickSave(defaultPath: string): Promise<string | null>;
  showInFolder(file: string): void;
}

export interface ServiceOptions {
  located: Located;
  dataDir: string;
  ui: ToolUi;
  /** The system's Videos folder: the save dialog's folder until one has been used. */
  videosDir: () => string;
  emit: {
    job: (update: JobUpdate) => void;
    encoders: (report: EncoderReport) => void;
    filesOpened: (result: DropResult) => void;
    /** A status that changed after the page was told it was ready: a cached answer that this launch's check did not confirm. */
    toolStatus?: (status: ToolStatus) => void;
  };
  platform?: NodeJS.Platform;
  env?: NodeJS.ProcessEnv;
  limits?: Partial<Limits>;
}

/** The text Copy Details gives: the tool's code and message and what the adapter saw. No path is in it. */
const problemOf = (error: ToolError): Problem => ({ code: error.code, details: JSON.stringify({ code: error.code, message: error.message, ...error.details }, null, 2) });

const CANCELLED: Problem = { code: 'cancelled', details: 'cancelled' };
const MAX_PREVIEW_BYTES = 48 * 1024 * 1024;

/** A request from the page, read field by field. Null when anything is off: the page is not trusted with a flag. */
export function readRequest(value: unknown): MakeRequest | null {
  if (typeof value !== 'object' || value === null) return null;
  const r = value as Record<string, unknown>;
  const shape = SHAPES.find((s) => s === r['shape']);
  const codec = CODECS.find((c) => c === r['codec']);
  if (!shape || !codec || typeof r['audioId'] !== 'string' || typeof r['imageId'] !== 'string') return null;
  if (r['destination'] !== 'ask' && r['destination'] !== 'same') return null;
  const resolution = r['resolution'] === null || r['resolution'] === undefined ? null : (RESOLUTIONS.find((x) => x === r['resolution']) ?? undefined);
  if (resolution === undefined || (shape === 'original') !== (resolution === null)) return null;
  let crop: MakeRequest['crop'] = null;
  if (r['crop'] !== null && r['crop'] !== undefined) {
    const c = r['crop'] as Record<string, unknown>;
    const inRange = (n: unknown): n is number => typeof n === 'number' && Number.isFinite(n) && n >= 0 && n <= 1;
    if (typeof c !== 'object' || !inRange(c['h']) || !inRange(c['v']) || (shape !== '1:1' && shape !== '4:3')) return null;
    crop = { h: c['h'], v: c['v'] };
  }
  return { audioId: r['audioId'], imageId: r['imageId'], shape, resolution, crop, codec, destination: r['destination'] };
}

interface Destination {
  file: string;
  /** True only when the person confirmed a replacement in the save dialog (premium bar rule 63). */
  overwrite: boolean;
}

export function createToolService(options: ServiceOptions) {
  const { located, dataDir, ui, emit } = options;
  const files = createFileRegistry();
  const previewDir = path.join(dataDir, 'previews');
  const destinationFile = path.join(dataDir, 'tool', 'destination.json');

  let records: JobRecords | null = null;
  let adapter: Adapter | null = null;
  let current: ToolStatus = { state: 'checking', code: null, details: null };
  let latestEncoders: EncoderReport | null = null;
  let checked: Promise<ToolStatus> | null = null;
  let refreshing: Promise<void> = Promise.resolve();
  let job: { jobId: string; abort: AbortController } | null = null;
  let lastDestination: Destination | null = null;
  let lastReconcile: { records: number; removed: number } | null = null;
  const previews = new Map<FileId, Set<AbortController>>();
  let previewCount = 0;

  // ---- the launch -------------------------------------------------------------

  /**
   * Check the tool and reconcile what a killed run left behind. Call once, when the app is ready.
   * The answer cached from the last run is used at once; this launch's own `--version` and
   * `encoders` refresh it in the background (SPEC 27.6).
   */
  function start(): void {
    records = createJobRecords(path.join(dataDir, 'jobs'), STAGING_NAME);
    lastReconcile = records.reconcile();
    fs.rmSync(previewDir, { recursive: true, force: true }); // the app's own picture cache: whatever a killed run left
    if (!located.ok) {
      current = { state: 'damaged', code: located.code, details: located.details };
      checked = Promise.resolve(current);
      return;
    }
    const ready = createAdapter({ located, cwd: dataDir, ...(options.env ? { env: options.env } : {}), ...(options.platform ? { platform: options.platform } : {}), ...(options.limits ? { limits: options.limits } : {}) });
    adapter = ready;
    const cache = createReportCache(dataDir);
    const cached = cache.read(located);
    if (cached) {
      current = { state: 'ready', code: null, details: cached.version };
      latestEncoders = cached.encoders;
    }
    checked = (async () => {
      const answer = await ready.version();
      const toldReady = current.state === 'ready'; // the cached answer, which the page may already have been given
      current = toolStatus(answer);
      if (!answer.ok) {
        cache.write(located, null);
        if (toldReady) emit.toolStatus?.(current); // the page learns it now, not at its next Make Video
        return current;
      }
      refreshing = (async () => {
        const fresh = await ready.encoders();
        if (fresh.status === 'ok') {
          latestEncoders = fresh.value;
          emit.encoders(fresh.value);
        }
        cache.write(located, { version: answer.version, encoders: latestEncoders });
      })().catch(() => undefined);
      return current;
    })();
  }

  /** The tool's status for bootstrap: the cached answer at once if there is one, otherwise the check (at most 10 s). */
  async function status(): Promise<ToolStatus> {
    if (current.state === 'ready' || !checked) return current;
    return checked;
  }

  /** Resolves when the launch's `--version` and `encoders` have both finished. For tests. */
  async function settled(): Promise<void> {
    await checked;
    await refreshing;
  }

  // ---- files ------------------------------------------------------------------

  type Inspected<T> = { ok: true; info: T } | { ok: false; problem: Problem };

  async function readyOrProblem(): Promise<Problem | null> {
    const ready = await status();
    return ready.state === 'ready' && adapter ? null : { code: ready.code ?? 'TOOL_NOT_FOUND', details: ready.details ?? '' };
  }

  async function inspectAudio(file: string): Promise<Inspected<AudioInfo>> {
    const notReady = await readyOrProblem();
    if (notReady || !adapter) return { ok: false, problem: notReady ?? { code: 'TOOL_NOT_FOUND', details: '' } };
    const out = await adapter.checkAudio(file);
    if (out.status === 'cancelled') return { ok: false, problem: CANCELLED };
    if (out.status === 'failed') return { ok: false, problem: problemOf(out.error) };
    return { ok: true, info: { id: files.add('audio', file), name: out.value.name, durationSeconds: out.value.durationSeconds } };
  }

  async function inspectImage(file: string): Promise<Inspected<ImageInfo>> {
    const notReady = await readyOrProblem();
    if (notReady || !adapter) return { ok: false, problem: notReady ?? { code: 'TOOL_NOT_FOUND', details: '' } };
    const out = await adapter.checkImage(file);
    if (out.status === 'cancelled') return { ok: false, problem: CANCELLED };
    if (out.status === 'failed') return { ok: false, problem: problemOf(out.error) };
    const { name, width, height, frames } = out.value;
    return { ok: true, info: { id: files.add('image', file), name, width, height, frames } };
  }

  async function chooseAudio(): Promise<ChooseResult<AudioInfo>> {
    const file = await ui.pickFile('audio');
    if (!file) return { status: 'dismissed' };
    const checkedFile = await inspectAudio(file);
    return checkedFile.ok ? { status: 'chosen', file: checkedFile.info } : { status: 'unusable', problem: checkedFile.problem };
  }

  async function chooseImage(): Promise<ChooseResult<ImageInfo>> {
    const file = await ui.pickFile('image');
    if (!file) return { status: 'dismissed' };
    const checkedFile = await inspectImage(file);
    return checkedFile.ok ? { status: 'chosen', file: checkedFile.info } : { status: 'unusable', problem: checkedFile.problem };
  }

  /**
   * SPEC 4a: judge a drop (or a file opened with the app) before anything is replaced. The shell
   * changes nothing; the page decides what an empty or a filled slot does. A drop is judged as a
   * whole: one file that fails the section 7 check rejects it, so an unreadable file never
   * replaces a good one and no id is left behind.
   */
  async function dropFiles(paths: unknown): Promise<DropResult> {
    const judged = judgeDrop(paths);
    if (!judged.ok) return { status: 'rejected', reason: judged.reason };
    const [audio, image] = await Promise.all([judged.audio ? inspectAudio(judged.audio) : null, judged.image ? inspectImage(judged.image) : null]);
    if ((audio && !audio.ok) || (image && !image.ok)) {
      files.release([audio?.ok ? audio.info.id : null, image?.ok ? image.info.id : null].filter((id): id is string => id !== null));
      return { status: 'rejected', reason: 'unreadable' };
    }
    return { status: 'ok', audio: audio?.ok ? audio.info : null, image: image?.ok ? image.info : null };
  }

  /** A file opened with the app (a second launch, or Open with): judged as a drop is, and sent to the page. */
  async function openFiles(paths: string[]): Promise<void> {
    emit.filesOpened(await dropFiles(paths));
  }

  function releaseFiles(ids: unknown): void {
    for (const id of files.release(ids)) {
      for (const abort of previews.get(id) ?? []) abort.abort();
      previews.delete(id);
    }
  }

  // ---- the preview ------------------------------------------------------------

  /** `song2vid preview` (SPEC 24.3): the image as the video will see it, as a picture the page's own policy allows. */
  async function previewImage(imageId: unknown): Promise<PreviewResult> {
    const image = files.get(imageId, 'image');
    if (!image || typeof imageId !== 'string') return { status: 'failed', problem: { code: 'usage', details: 'the image id is not known' } };
    const notReady = await readyOrProblem();
    if (notReady || !adapter) return { status: 'failed', problem: notReady ?? { code: 'TOOL_NOT_FOUND', details: '' } };
    const abort = new AbortController();
    const mine = previews.get(imageId) ?? new Set<AbortController>();
    mine.add(abort);
    previews.set(imageId, mine);
    const output = path.join(previewDir, `${path.basename(imageId)}-${Date.now().toString(36)}-${(previewCount += 1).toString(36)}.png`); // a counter too: two previews of one image can start in the same millisecond
    try {
      fs.mkdirSync(previewDir, { recursive: true });
      const before = new Set(records?.leftovers(previewDir) ?? []);
      const out = await adapter.preview(image, output, { signal: abort.signal });
      // A preview killed by the grace period may have left its temporary file: remove what is new in the folder.
      if (out.status !== 'ok' && out.killed) records?.removeLeftovers(previewDir, before);
      if (out.status === 'cancelled') return { status: 'failed', problem: CANCELLED };
      if (out.status === 'failed') return { status: 'failed', problem: problemOf(out.error) };
      const size = fs.statSync(output).size;
      if (size > MAX_PREVIEW_BYTES) return { status: 'failed', problem: { code: 'export_failed', details: JSON.stringify({ fault: 'TOOL_PROTOCOL', message: `a preview of ${size} bytes` }) } };
      return { status: 'ready', src: `data:image/png;base64,${fs.readFileSync(output).toString('base64')}`, width: out.value.width, height: out.value.height };
    } catch (error) {
      return { status: 'failed', problem: { code: 'export_failed', details: stackOf(error) } };
    } finally {
      mine.delete(abort);
      fs.rmSync(output, { force: true });
    }
  }

  // ---- the job ----------------------------------------------------------------

  function readLastFolder(): string | null {
    try {
      const saved = JSON.parse(fs.readFileSync(destinationFile, 'utf8')) as { folder?: unknown };
      return typeof saved.folder === 'string' && fs.statSync(saved.folder).isDirectory() ? saved.folder : null;
    } catch {
      return null;
    }
  }

  function rememberFolder(folder: string): void {
    try {
      fs.mkdirSync(path.dirname(destinationFile), { recursive: true });
      fs.writeFileSync(`${destinationFile}.tmp`, JSON.stringify({ folder }));
      fs.renameSync(`${destinationFile}.tmp`, destinationFile);
    } catch {
      // The folder is a convenience.
    }
  }

  /** The save dialog's start: the last folder saved to, else Videos, and the audio file's name with `.mp4` (SPEC 27.4). */
  const defaultSavePath = (audio: string): string => path.join(readLastFolder() ?? options.videosDir(), `${path.basename(audio, path.extname(audio))}.mp4`);

  /** What the person chose. `--overwrite` only when the system's own dialog asked and they confirmed (premium bar rule 63). */
  function destinationOf(picked: string): Destination {
    const named = /\.mp4$/i.test(picked);
    return { file: named ? picked : `${picked}.mp4`, overwrite: named && fs.existsSync(picked) };
  }

  /** The folder's own name for "Saved Song.mp4 to Videos." Never a path. */
  function whereOf(folder: string): string {
    const name = path.basename(folder);
    return name || path.parse(folder).root.replace(/[\\/]+$/, '') || folder;
  }

  const failLater = (jobId: string, problem: Problem): void => {
    setImmediate(() => emit.job({ jobId, state: 'failed', problem }));
  };

  async function makeVideo(raw: unknown): Promise<MakeStart> {
    if (job) return { status: 'busy' };
    const jobId = newJobId();
    const abort = new AbortController();
    job = { jobId, abort }; // held through the save dialog: a second Make Video is busy
    const refuse = (problem: Problem): MakeStart => {
      job = null;
      failLater(jobId, problem);
      return { status: 'started', jobId };
    };
    const request = readRequest(raw);
    if (!request) return refuse({ code: 'usage', details: 'the request is not a valid make request' });
    const audio = files.get(request.audioId, 'audio');
    const image = files.get(request.imageId, 'image');
    if (!audio || !image) return refuse({ code: 'usage', details: 'a file id is not known' });
    const notReady = await readyOrProblem();
    if (notReady || !adapter || !records) return refuse(notReady ?? { code: 'TOOL_NOT_FOUND', details: '' });

    let target: Destination;
    if (request.destination === 'same' && lastDestination) target = lastDestination;
    else {
      let picked: string | null;
      try {
        picked = await ui.pickSave(defaultSavePath(audio));
      } catch (error) {
        return refuse({ code: 'output_not_writable', details: stackOf(error) });
      }
      if (!picked) {
        job = null;
        return { status: 'dismissed' };
      }
      target = destinationOf(picked);
    }
    lastDestination = target;
    const folder = path.dirname(target.file);

    const tool = adapter;
    const jobs = records;
    const before = new Set(jobs.leftovers(folder));
    jobs.write({ jobId, folder, startedAt: new Date().toISOString() }); // before the tool starts
    const progress = createProgressModel({ now: Date.now });
    const push = () => emit.job({ jobId, state: 'running', ...progress.snapshot() });
    setImmediate(() => {
      void (async () => {
        let update: JobUpdate;
        let sweep = false;
        try {
          push();
          const out = await tool.make(
            { audio, image, output: target.file, shape: request.shape, resolution: request.resolution, crop: request.crop, codec: request.codec, overwrite: target.overwrite },
            {
              signal: abort.signal,
              onStall: (stalled) => {
                progress.setStalled(stalled);
                push();
              },
              onLine: (line) => {
                if (progress.onLine(line)) push();
              },
            },
          );
          if (out.status === 'ok') {
            const made = out.value;
            const encoder = made.encoder ?? progress.snapshot().encoder;
            if (!encoder) {
              update = { jobId, state: 'failed', problem: { code: 'export_failed', details: JSON.stringify({ fault: 'TOOL_PROTOCOL', message: 'the result names no Encoder' }) } };
            } else {
              const done: MakeDone = {
                outputId: files.add('output', target.file),
                fileName: made.name,
                where: whereOf(folder),
                width: made.width,
                height: made.height,
                durationSeconds: made.durationSeconds,
                bytes: made.bytes,
                codec: made.codec ?? request.codec,
                encoder,
                encoderFallback: made.encoderFallback,
              };
              update = { jobId, state: 'done', result: done };
              rememberFolder(folder); // "the last folder saved to" (SPEC 27.4)
            }
          } else if (out.status === 'cancelled') {
            update = { jobId, state: 'cancelled' };
            sweep = out.killed;
          } else {
            update = { jobId, state: 'failed', problem: problemOf(out.error) };
            sweep = out.killed || out.error.fault !== null;
          }
        } catch (error) {
          update = { jobId, state: 'failed', problem: { code: 'export_failed', details: stackOf(error) } };
          sweep = true;
        }
        // A tool that was killed or broke its contract may have left its temporary file: remove what is new in this folder.
        if (sweep) jobs.removeLeftovers(folder, before);
        jobs.remove(jobId);
        job = null;
        emit.job(update);
      })();
    });
    return { status: 'started', jobId };
  }

  /** Closes the tool's stdin; the tool is killed 3 s later if it is still there (SPEC 27.6). The job then ends with `cancelled`. */
  function cancelJob(jobId: unknown): void {
    if (job && job.jobId === jobId) job.abort.abort();
  }

  function showInFolder(outputId: unknown): void {
    const file = files.get(outputId, 'output');
    if (file) ui.showInFolder(file);
  }

  function diagnostics(): Record<string, unknown> {
    return {
      tool: located.ok ? { source: located.source, binary: located.binary, helpers: located.helpers } : { source: null, error: located.details },
      status: current,
      encoders: latestEncoders,
      job: job ? { jobId: job.jobId } : null,
      files: files.size,
      reconciled: lastReconcile,
    };
  }

  return {
    start,
    status,
    settled,
    encoders: (): EncoderReport | null => latestEncoders,
    chooseAudio,
    chooseImage,
    dropFiles,
    openFiles,
    releaseFiles,
    previewImage,
    makeVideo,
    cancelJob,
    showInFolder,
    diagnostics,
    get jobRunning(): boolean {
      return Boolean(job);
    },
    get jobId(): string | null {
      return job?.jobId ?? null;
    },
  };
}

export type ToolService = ReturnType<typeof createToolService>;

