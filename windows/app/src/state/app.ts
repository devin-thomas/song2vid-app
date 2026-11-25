// The window's state and everything a person does to it. A store outside React (store.ts): a
// change made in an event handler is applied in the same task as the input, so Cancel is
// acknowledged on the next frame and a control never trails its value (premium bar rules 58, 67).
//
// The words are the page's own (words.ts, status.ts). The shell sends codes and numbers; the
// tool's text arrives as `details`, which only Copy Details touches. Files are opaque ids: the
// page never holds a path (src/bridge.ts).
import type { Bootstrap, Codec, DesktopBridge, DropResult, EncoderReport, FileId, JobUpdate, MakeRequest } from '../bridge.ts';
import { decideDrop, idsToRelease } from './drops.ts';
import { CENTER, drag, isCropShape, nudge, outputFrame, overflow } from './frame.ts';
import type { Crop, Direction, Frame, Shape, Tier } from './frame.ts';
import { jobBusy, startingCodec } from './model.ts';
import type { AppState, JobView, Notice, Slots } from './model.ts';
import { createStore, useStore } from './store.ts';
import { WAIT_LINES, isToolCode, mayShowTimeLeft, rejectionLines, slotOfFailure, steadyPercent, steadyRemaining } from './words.ts';
import type { FailureAction } from './words.ts';

const initialState = (): AppState => ({
  tool: { state: 'checking', code: null, details: null },
  encoders: null,
  audio: null,
  image: null,
  shape: '16:9',
  tier: '1080p',
  codec: 'h264',
  savedCodec: 'h264',
  crop: CENTER,
  preview: null,
  job: { phase: 'idle' },
  failure: null,
  notice: null,
  replace: null,
  dragging: false,
});

const store = createStore<AppState>(initialState());

let bridge: DesktopBridge | null = null;
/** The inputs of the last failed job, to tell a repeat from a new failure. */
let lastFailureKey: string | null = null;
let noticeTimer: ReturnType<typeof setTimeout> | null = null;
let noticeId = 0;
let previewId = 0;
/** Cancel was pressed before the shell had named the job: it is sent as soon as the name arrives. */
let cancelWhenNamed = false;
/** The last full request, for Try Again after a repeat and for the repeat key. */
let lastRequestKey: string | null = null;

const get = (): AppState => store.get();
const set = (patch: Partial<AppState> | ((s: AppState) => Partial<AppState>)): void => store.set((s) => ({ ...s, ...(typeof patch === 'function' ? patch(s) : patch) }));

/** Back to a window that has not started: for the tests, which run several windows in one process. */
export function resetApp(): void {
  if (noticeTimer) clearTimeout(noticeTimer);
  noticeTimer = null;
  bridge = null;
  lastFailureKey = null;
  lastRequestKey = null;
  cancelWhenNamed = false;
  store.set(initialState());
}

// ---- starting up ------------------------------------------------------------------------------

/** Takes what bootstrap() knows, and listens to the shell. Call once, before the first paint. */
export function startApp(desktop: DesktopBridge, boot: Bootstrap): void {
  bridge = desktop;
  const saved = boot.preferences.codec;
  set({ tool: boot.tool, encoders: boot.encoders, savedCodec: saved, codec: startingCodec(saved, boot.encoders) });
  desktop.onJob(onJob);
  desktop.onEncoders(applyEncoders);
  desktop.onToolStatus((status) => set({ tool: status }));
  desktop.onFilesOpened((result) => applyDrop(result));
  // A report or a status that arrived between bootstrap() and the subscriptions above is not
  // missed: ask once more (BRIDGE.md, "The stand-in" and the open points of S2V-029).
  void desktop.bootstrap().then((again) => {
    if (again.encoders) applyEncoders(again.encoders);
    if (again.tool.state !== get().tool.state) set({ tool: again.tool });
  });
}

function applyEncoders(report: EncoderReport): void {
  set((s) => {
    // The remembered Codec comes back on a computer that can make it (SPEC 23): the choice follows the report, the memory does not.
    if (!report.hevc.available) return { encoders: report, codec: s.codec === 'hevc' ? 'h264' : s.codec };
    return { encoders: report, codec: s.savedCodec === 'hevc' && !jobBusy(s.job) ? 'hevc' : s.codec };
  });
}

// ---- reading the state ------------------------------------------------------------------------

/** The frame the tool will make for the current choices, as the preview draws it. Null without an image, or an Original that is too small. */
export function frameOf(s: AppState): Frame | null {
  return s.image ? outputFrame({ width: s.image.width, height: s.image.height }, s.shape, s.tier, s.crop) : null;
}

/** How far the image can move on each axis in the current frame. */
export function roomOf(s: AppState): { h: number; v: number } {
  const frame = frameOf(s);
  return frame ? overflow(frame, s.shape) : { h: 0, v: 0 };
}

export const canAdjustCrop = (s: AppState): boolean => !jobBusy(s.job) && (roomOf(s).h > 0 || roomOf(s).v > 0);

export const toolReady = (s: AppState): boolean => s.tool.state !== 'damaged';

/**
 * Make Video: both files loaded, the tool usable, nothing running, and a frame the tool can make. It waits while the bar
 * says a loaded file is the problem, and while HEVC is chosen after the tool said this computer cannot make it, so the button
 * never offers what the message says will fail (S2V-031).
 */
export function canMake(s: AppState): boolean {
  if (s.failure?.of) return false;
  if (s.failure?.code === 'codec_unavailable' && s.codec === 'hevc') return false;
  return Boolean(s.audio && s.image && toolReady(s) && !jobBusy(s.job) && !s.replace && frameOf(s) !== null);
}

/** "Output: W×H" for Original, from the tool's own table when it has the row. */
export function originalSize(s: AppState): { width: number; height: number } | null {
  const row = s.image?.frames.find((r) => r.shape === 'original');
  if (row && row.width !== null && row.height !== null) return { width: row.width, height: row.height };
  return frameOf({ ...s, shape: 'original' })?.size ?? null;
}

// ---- small things -----------------------------------------------------------------------------

/** A message for a few seconds in the status bar: what was refused, and what to do instead. */
export function say(notice: Notice, ms = 4000): void {
  const id = ++noticeId;
  if (noticeTimer) clearTimeout(noticeTimer);
  set({ notice });
  noticeTimer = setTimeout(() => {
    if (id === noticeId) set({ notice: null });
  }, ms);
}

function dropNotice(): void {
  noticeId += 1;
  if (noticeTimer) clearTimeout(noticeTimer);
  noticeTimer = null;
  if (get().notice) set({ notice: null });
}

const release = (ids: FileId[]): void => {
  if (ids.length) bridge?.releaseFiles(ids);
};

// ---- choosing files -----------------------------------------------------------------------------

/** Puts files in the slots. A new image starts a new preview and a new crop; the old ids are freed. */
function useSlots(slots: Slots): void {
  const before = get();
  const imageChanged = slots.image?.id !== before.image?.id;
  const audioChanged = slots.audio?.id !== before.audio?.id;
  set((s) => ({
    audio: slots.audio,
    image: slots.image,
    crop: imageChanged ? CENTER : s.crop,
    failure: s.failure && ((imageChanged && s.failure.code.startsWith('image_')) || (audioChanged && s.failure.code.startsWith('audio_'))) ? null : s.failure,
    job: s.job.phase === 'done' || s.job.phase === 'cancelled' ? { phase: 'idle' } : s.job,
    preview: imageChanged ? null : s.preview,
  }));
  release(idsToRelease([before.audio, before.image], slots));
  if (imageChanged && slots.image) void loadPreview(slots.image.id);
}

async function loadPreview(imageId: FileId): Promise<void> {
  if (!bridge) return;
  const mine = ++previewId;
  set({ preview: { imageId, status: 'loading' } });
  const result = await bridge.previewImage(imageId);
  if (mine !== previewId || get().image?.id !== imageId) return;
  if (result.status === 'ready') {
    set({ preview: { imageId, status: 'ready', src: result.src, width: result.width, height: result.height } });
    return;
  }
  set({ preview: { imageId, status: 'failed', code: result.problem.code } });
  if (jobBusy(get().job)) return;
  // An image that cannot be drawn is a problem with the image: the bar says so with its button, and Make Video waits.
  const code = slotOfFailure(result.problem.code) === 'image' ? result.problem.code : 'image_unreadable';
  fail(code, result.problem.details, null, 'image');
}

export async function chooseAudio(): Promise<void> {
  if (!bridge || jobBusy(get().job) || get().replace) return;
  dropNotice();
  const result = await bridge.chooseAudio();
  if (result.status === 'dismissed') return;
  if (result.status === 'unusable') return fail(result.problem.code, result.problem.details, null);
  useSlots({ audio: result.file, image: get().image });
}

export async function chooseImage(): Promise<void> {
  if (!bridge || jobBusy(get().job) || get().replace) return;
  dropNotice();
  const result = await bridge.chooseImage();
  if (result.status === 'dismissed') return;
  if (result.status === 'unusable') return fail(result.problem.code, result.problem.details, null);
  useSlots({ audio: get().audio, image: result.file });
}

/** A failure of a file or of a job: shown in the status bar with its filled button. A tool that is missing or wrong blocks the window instead. */
function fail(code: string, details: string, key: string | null, slot: 'audio' | 'image' | null = key !== null ? slotOfFailure(code) : null): void {
  if (isToolCode(code)) {
    set((s) => ({ tool: { state: 'damaged', code, details }, failure: null, job: jobBusy(s.job) ? { phase: 'idle' } : s.job }));
    return;
  }
  const again = key !== null && key === lastFailureKey;
  lastFailureKey = key;
  set({ failure: { code, details, again, of: slot }, job: { phase: 'idle' } });
}

// ---- drops ------------------------------------------------------------------------------------

/** The drag in flight: highlight only for a drop that could be used. */
export function setDragging(on: boolean): void {
  if (get().dragging !== on) set({ dragging: on });
}

/** The files of a drop: refused while a video is made, else judged by the shell and applied or asked about. */
export async function dropFiles(files: File[]): Promise<void> {
  if (!bridge) return;
  set({ dragging: false });
  if (jobBusy(get().job)) return say(WAIT_LINES, 3000);
  if (get().replace) return;
  dropNotice();
  applyDrop(await bridge.dropFiles(files), files.map((file) => file.name));
}

/** A judged drop (or a file opened with the app): nothing changes for a rejected one; an empty slot is filled; a filled one asks. */
export function applyDrop(result: DropResult, names: readonly string[] = []): void {
  if (result.status === 'rejected') return say(rejectionLines(result.reason, names), 5000);
  const s = get();
  if (jobBusy(s.job)) {
    release([result.audio?.id, result.image?.id].filter((id): id is FileId => id !== undefined));
    return say(WAIT_LINES, 3000);
  }
  const dropped: Slots = { audio: result.audio, image: result.image };
  if (!dropped.audio && !dropped.image) return;
  const decision = decideDrop({ audio: s.audio, image: s.image }, dropped);
  if (decision.kind === 'apply') return useSlots(decision.slots);
  // The slots that can already be filled are filled whichever way the person answers; the question is about the rest.
  set({ replace: decision.question });
}

/** The answer to the Replace question: Replace uses the dropped files; Keep Current keeps what is loaded and fills only empty slots. */
export function answerReplace(replace: boolean): void {
  const question = get().replace;
  if (!question) return;
  set({ replace: null });
  const chosen = replace ? question.ifReplaced : question.ifKept;
  const dropped = [question.ifReplaced.audio, question.ifReplaced.image];
  useSlots(chosen);
  // Whatever was dropped and not used is freed, and so is what was replaced.
  release(idsToRelease(dropped, chosen));
}

// ---- the options ------------------------------------------------------------------------------

export function setShape(shape: Shape): void {
  const s = get();
  if (jobBusy(s.job) || s.shape === shape) return;
  set({ shape, crop: CENTER, failure: s.failure?.code === 'image_too_small' ? null : s.failure });
}

export function setTier(tier: Tier): void {
  const s = get();
  if (jobBusy(s.job) || s.tier === tier) return;
  set({ tier });
}

export function setCodec(codec: Codec): void {
  const s = get();
  if (jobBusy(s.job)) return;
  if (codec === 'hevc' && s.encoders && !s.encoders.hevc.available) return;
  set({ codec, savedCodec: codec, failure: s.failure?.code === 'codec_unavailable' ? null : s.failure });
  bridge?.setPreferences({ codec });
}

export function nudgeCrop(direction: Direction, large: boolean): void {
  const s = get();
  if (!canAdjustCrop(s)) return;
  const next = nudge(s.crop, direction, large, roomOf(s));
  if (next !== s.crop) set({ crop: next });
}

export function setCropFromDrag(start: Crop, dx: number, dy: number): void {
  const s = get();
  if (!canAdjustCrop(s)) return;
  const next = drag(start, dx, dy, roomOf(s), s.crop);
  if (next.h !== s.crop.h || next.v !== s.crop.v) set({ crop: next });
}

/** Home and End on the Crop position control: the start and the end of the axis that can move. */
export function setCropEdge(end: boolean): void {
  const s = get();
  if (!canAdjustCrop(s)) return;
  const room = roomOf(s);
  const value = end ? 1 : 0;
  set({ crop: room.h > 0 ? { h: value, v: s.crop.v } : { h: s.crop.h, v: value } });
}

export function resetCrop(): void {
  const s = get();
  if (jobBusy(s.job) || !isCropShape(s.shape)) return;
  if (s.crop.h !== CENTER.h || s.crop.v !== CENTER.v) set({ crop: CENTER });
}

// ---- making the video -------------------------------------------------------------------------

function requestFrom(s: AppState, destination: 'ask' | 'same'): MakeRequest | null {
  if (!s.audio || !s.image) return null;
  return {
    audioId: s.audio.id,
    imageId: s.image.id,
    shape: s.shape,
    resolution: s.shape === 'original' ? null : s.tier,
    crop: isCropShape(s.shape) ? { h: s.crop.h, v: s.crop.v } : null,
    codec: s.codec,
    destination,
  };
}

const keyOf = (request: MakeRequest): string => JSON.stringify({ ...request, destination: undefined });

/** Make Video: opens the save dialog (`ask`), or reuses the last destination (`same`, Try Again). */
export async function makeVideo(destination: 'ask' | 'same' = 'ask'): Promise<void> {
  const s = get();
  if (!bridge || !canMake(s)) return;
  const request = requestFrom(s, destination);
  if (!request) return;
  dropNotice();
  cancelWhenNamed = false;
  lastRequestKey = keyOf(request);
  set({ job: { phase: 'starting' }, failure: null });
  const start = await bridge.makeVideo(request);
  if (start.status === 'dismissed') {
    if (get().job.phase === 'starting') set({ job: { phase: 'idle' } });
    return;
  }
  if (start.status === 'busy') return;
  const now = get();
  if (now.job.phase === 'starting') {
    set({ job: runningJob(start.jobId) });
  } else if (now.job.phase === 'running' && now.job.jobId === null) set({ job: { ...now.job, jobId: start.jobId } });
  if (cancelWhenNamed) {
    cancelWhenNamed = false;
    bridge.cancelJob(start.jobId);
  }
}

const runningJob = (jobId: string | null): JobView => ({ phase: 'running', jobId, stage: 'checking', percent: null, remaining: null, encoder: null, stalled: false, cancelling: false });

function onJob(update: JobUpdate): void {
  const s = get();
  const job = s.job;
  // Before the shell has named the job, the first update names it.
  const adopt = job.phase === 'starting' || (job.phase === 'running' && job.jobId === null);
  if (!adopt && !(job.phase === 'running' && job.jobId === update.jobId)) return; // an update for a job the page no longer follows
  const current: Extract<JobView, { phase: 'running' }> = job.phase === 'running' ? { ...job, jobId: update.jobId } : (runningJob(update.jobId) as Extract<JobView, { phase: 'running' }>);
  switch (update.state) {
    case 'running': {
      const percent = steadyPercent(current.percent, update.percent);
      const showLeft = mayShowTimeLeft({ stage: update.stage, percent, elapsedSeconds: update.elapsedSeconds, remainingSeconds: update.remainingSeconds });
      const remaining = showLeft && update.remainingSeconds !== null ? steadyRemaining(current.remaining, update.remainingSeconds, Date.now()) : current.remaining;
      set({ job: { ...current, stage: update.stage, percent, remaining, encoder: update.encoder ?? current.encoder, stalled: update.stalled } });
      return;
    }
    case 'done':
      lastFailureKey = null;
      set({ job: { phase: 'done', result: update.result }, failure: null });
      return;
    case 'cancelled':
      set({ job: { phase: 'cancelled' } });
      return;
    case 'failed':
      fail(update.problem.code, update.problem.details, lastRequestKey);
      return;
  }
}

/** Cancel: "Cancelling" on the next frame, "Cancelled. Nothing was saved." when the tool exits. */
export function cancel(): void {
  const s = get();
  if (!bridge) return;
  const job = s.job;
  if (job.phase === 'starting') {
    cancelWhenNamed = true;
    return;
  }
  if (job.phase !== 'running' || job.cancelling) return;
  set({ job: { ...job, cancelling: true } });
  if (job.jobId) bridge.cancelJob(job.jobId);
  else cancelWhenNamed = true;
}

// ---- after a job ------------------------------------------------------------------------------

export function showInFolder(): void {
  const job = get().job;
  if (job.phase === 'done') bridge?.showInFolder(job.result.outputId);
}

/** The filled button of a failure or of the finished video. */
export async function runAction(action: FailureAction | 'show-in-folder' | 'cancel'): Promise<void> {
  switch (action) {
    case 'choose-audio':
      return chooseAudio();
    case 'choose-image':
      return chooseImage();
    case 'use-h264':
      return setCodec('h264');
    case 'choose-folder':
    case 'save-as':
      return makeVideo('ask');
    case 'try-again':
      return makeVideo('same');
    case 'copy-details':
      return copyDetails();
    case 'open-download-page':
      return bridge?.openLink('download-page');
    case 'show-in-folder':
      return showInFolder();
    case 'cancel':
      return cancel();
  }
}

/** Copy Details: the developer text goes to the clipboard and is never shown. */
export async function copyDetails(): Promise<void> {
  const s = get();
  const text = s.failure?.details ?? s.tool.details ?? '';
  try {
    await (navigator as { clipboard?: { writeText(text: string): Promise<void> } }).clipboard?.writeText(text);
  } catch {
    // No clipboard: the sentences on screen still say what happened.
  }
}

export function openRepository(): void {
  bridge?.openLink('repository');
}

export function openDownloadPage(): void {
  bridge?.openLink('download-page');
}

// ---- for React --------------------------------------------------------------------------------

export const useApp = <S>(selector: (state: AppState) => S): S => useStore(store, selector);
export const appState = (): AppState => store.get();
