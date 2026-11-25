// What the window does with each thing a person does and each thing the shell says, with a scripted
// shell in place of the real one (src/state/app.ts is plain TypeScript over src/bridge.ts). The
// states are read the way the page reads them: through the store.
import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';
import type { AudioInfo, Bootstrap, Codec, DesktopBridge, DropResult, EncoderReport, ImageInfo, JobUpdate, MakeRequest, MakeStart, ToolStatus } from '../src/bridge.ts';
import { appState, applyDrop, answerReplace, cancel, canMake, chooseAudio, chooseImage, makeVideo, nudgeCrop, resetApp, runAction, setCodec, setShape, setTier, startApp } from '../src/state/app.ts';
import { statusOf } from '../src/state/status.ts';

const song: AudioInfo = { id: 'f_song', name: 'Song.mp3', durationSeconds: 144 };
const cover: ImageInfo = { id: 'f_cover', name: 'Cover.png', width: 1600, height: 900, frames: [] };
const NVENC: EncoderReport = { h264: { available: true, encoder: 'nvenc' }, hevc: { available: true, encoder: 'nvenc' } };
const NO_HEVC: EncoderReport = { h264: { available: true, encoder: 'software' }, hevc: { available: false, encoder: null } };

/** A shell that does what it is told and records what it was asked. */
function shell(over: { codec?: Codec; encoders?: EncoderReport | null; tool?: ToolStatus; start?: MakeStart | (() => MakeStart) } = {}) {
  const calls: { name: string; args: unknown[] }[] = [];
  const jobs: ((u: JobUpdate) => void)[] = [];
  const encoders: ((r: EncoderReport) => void)[] = [];
  const tools: ((s: ToolStatus) => void)[] = [];
  const opened: ((r: DropResult) => void)[] = [];
  const log = (name: string, ...args: unknown[]) => calls.push({ name, args });
  const boot: Bootstrap = { stored: {}, platform: 'windows', preferences: { codec: over.codec ?? 'h264' }, about: null, tool: over.tool ?? { state: 'ready', code: null, details: null }, encoders: over.encoders === undefined ? NVENC : over.encoders };
  const bridge: DesktopBridge = {
    bootstrap: async () => boot,
    setTheme: () => {},
    saveState: () => {},
    setPreferences: (update) => log('setPreferences', update),
    chooseAudio: async () => (log('chooseAudio'), { status: 'chosen', file: song }),
    chooseImage: async () => (log('chooseImage'), { status: 'chosen', file: cover }),
    dropFiles: async (files) => (log('dropFiles', files), { status: 'rejected', reason: 'more-audio' }),
    onFilesOpened: (l) => (opened.push(l), () => {}),
    releaseFiles: (ids) => log('releaseFiles', ids),
    previewImage: async (id) => (log('previewImage', id), { status: 'ready', src: 'data:image/png;base64,', width: 1600, height: 900 }),
    onEncoders: (l) => (encoders.push(l), () => {}),
    onToolStatus: (l) => (tools.push(l), () => {}),
    makeVideo: async (request) => (log('makeVideo', request), typeof over.start === 'function' ? over.start() : (over.start ?? { status: 'started', jobId: 'job-1' })),
    cancelJob: (id) => log('cancelJob', id),
    onJob: (l) => (jobs.push(l), () => {}),
    showInFolder: (id) => log('showInFolder', id),
    openLink: (which) => log('openLink', which),
    notices: async () => '',
    onMenuCommand: () => () => {},
    setMenuState: () => {},
  };
  return { bridge, boot, calls, job: (u: JobUpdate) => jobs.forEach((l) => l(u)), encoders: (r: EncoderReport) => encoders.forEach((l) => l(r)), tool: (s: ToolStatus) => tools.forEach((l) => l(s)), opened: (r: DropResult) => opened.forEach((l) => l(r)) };
}

const tick = () => new Promise<void>((r) => setTimeout(r, 0));
const running = (over: Partial<Extract<JobUpdate, { state: 'running' }>> = {}): JobUpdate => ({ jobId: 'job-1', state: 'running', stage: 'encoding', percent: 40, elapsedSeconds: 3, remainingSeconds: 9, encoder: 'nvenc', stalled: false, ...over });
const failed = (code: string): JobUpdate => ({ jobId: 'job-1', state: 'failed', problem: { code, details: `{"code":"${code}"}` } });
const done = (): JobUpdate => ({
  jobId: 'job-1',
  state: 'done',
  result: { outputId: 'f_out', fileName: 'Song.mp4', where: 'Videos', width: 1920, height: 1080, durationSeconds: 144, bytes: 1, codec: 'h264', encoder: 'nvenc', encoderFallback: false },
});

async function ready(over: Parameters<typeof shell>[0] = {}) {
  const s = shell(over);
  startApp(s.bridge, s.boot);
  await tick();
  await chooseAudio();
  await chooseImage();
  await tick();
  return s;
}

beforeEach(() => resetApp());

test('a song and an image make Make Video ready, and the preview is asked for the image', async () => {
  const s = shell();
  startApp(s.bridge, s.boot);
  assert.equal(canMake(appState()), false);
  await chooseAudio();
  assert.equal(canMake(appState()), false, 'a song alone is not enough');
  await chooseImage();
  await tick();
  assert.equal(canMake(appState()), true);
  assert.deepEqual(s.calls.filter((c) => c.name === 'previewImage').map((c) => c.args), [['f_cover']]);
  assert.equal(appState().preview?.status, 'ready');
});

test('choosing a replacement releases the old id, and a new image starts a new crop and a new preview', async () => {
  const s = await ready();
  setShape('1:1');
  nudgeCrop('left', false);
  assert.equal(appState().crop.h, 0.55);
  const second: ImageInfo = { ...cover, id: 'f_cover2', name: 'Second.png' };
  s.bridge.chooseImage = async () => ({ status: 'chosen', file: second });
  await chooseImage();
  await tick();
  assert.equal(appState().crop.h, 0.5);
  assert.deepEqual(s.calls.filter((c) => c.name === 'releaseFiles').at(-1)?.args, [['f_cover']]);
  assert.equal(appState().preview?.imageId, 'f_cover2');
});

test('the crop keeps its position across a Resolution and restarts for a new Frame Shape', async () => {
  await ready();
  setShape('1:1');
  nudgeCrop('left', true);
  assert.equal(appState().crop.h, 0.75);
  setTier('2160p');
  assert.equal(appState().crop.h, 0.75);
  setShape('4:3');
  assert.equal(appState().crop.h, 0.5);
});

test('Make Video sends exactly what is chosen: the crop only for a crop shape, no Resolution for Original', async () => {
  const s = await ready();
  setShape('1:1');
  nudgeCrop('left', false);
  setCodec('hevc');
  await makeVideo('ask');
  const first = s.calls.filter((c) => c.name === 'makeVideo').at(-1)?.args[0] as MakeRequest;
  assert.deepEqual(first, { audioId: 'f_song', imageId: 'f_cover', shape: '1:1', resolution: '1080p', crop: { h: 0.55, v: 0.5 }, codec: 'hevc', destination: 'ask' });
  s.job(done());
  setShape('original');
  await makeVideo('ask');
  const second = s.calls.filter((c) => c.name === 'makeVideo').at(-1)?.args[0] as MakeRequest;
  assert.deepEqual([second.shape, second.resolution, second.crop], ['original', null, null]);
});

test('a job runs, shows progress that never goes back, and ends with what it made and where', async () => {
  const s = await ready();
  await makeVideo('ask');
  assert.equal(appState().job.phase, 'running');
  assert.equal(canMake(appState()), false, 'one job at a time');
  s.job(running({ percent: 12, elapsedSeconds: 1.2, remainingSeconds: 9 }));
  s.job(running({ percent: 8 }));
  const job = appState().job;
  assert.ok(job.phase === 'running');
  assert.equal(job.percent, 12, 'a lower number does not move the bar back');
  assert.deepEqual(job.remaining?.seconds, 9);
  s.job(running({ percent: 100 }));
  assert.equal((appState().job as { percent: number }).percent, 99, '100% only with the outcome');
  s.job(done());
  assert.equal(appState().job.phase, 'done');
  assert.equal(statusOf(appState()).first, 'Saved Song.mp4 to Videos.');
  assert.equal(canMake(appState()), true, 'the controls unlock at once');
  await runAction('show-in-folder');
  assert.deepEqual(s.calls.filter((c) => c.name === 'showInFolder').map((c) => c.args), [['f_out']]);
});

test('time left is not shown before encoding has run 1 second and passed 5%', async () => {
  const s = await ready();
  await makeVideo('ask');
  s.job(running({ percent: 4, elapsedSeconds: 2 }));
  assert.equal((appState().job as { remaining: unknown }).remaining, null);
  s.job(running({ percent: 30, elapsedSeconds: 0.5 }));
  assert.equal((appState().job as { remaining: unknown }).remaining, null);
  s.job(running({ percent: 30, elapsedSeconds: 3 }));
  assert.ok((appState().job as { remaining: unknown }).remaining);
});

test('Cancel is acknowledged at once, the job ends as cancelled only when the tool says so, and nothing is saved', async () => {
  const s = await ready();
  await makeVideo('ask');
  s.job(running());
  cancel();
  const job = appState().job;
  assert.ok(job.phase === 'running' && job.cancelling);
  assert.equal(statusOf(appState()).first, 'Cancelling');
  assert.deepEqual(s.calls.filter((c) => c.name === 'cancelJob').map((c) => c.args), [['job-1']]);
  cancel();
  assert.equal(s.calls.filter((c) => c.name === 'cancelJob').length, 1, 'a second press does not ask twice');
  s.job({ jobId: 'job-1', state: 'cancelled' });
  assert.equal(statusOf(appState()).first, 'Cancelled. Nothing was saved.');
  assert.equal(canMake(appState()), true);
});

test('Cancel pressed before the shell has named the job is sent as soon as it has', async () => {
  let release: (start: MakeStart) => void = () => {};
  const s = shell();
  s.bridge.makeVideo = (request) => new Promise<MakeStart>((resolve) => (s.calls.push({ name: 'makeVideo', args: [request] }), (release = resolve)));
  startApp(s.bridge, s.boot);
  await tick();
  await chooseAudio();
  await chooseImage();
  const pending = makeVideo('ask');
  assert.equal(appState().job.phase, 'starting');
  cancel();
  assert.equal(s.calls.filter((c) => c.name === 'cancelJob').length, 0);
  release({ status: 'started', jobId: 'job-9' });
  await pending;
  assert.deepEqual(s.calls.filter((c) => c.name === 'cancelJob').map((c) => c.args), [['job-9']]);
});

test('updates that arrive before the shell\'s answer are not lost, and updates for another job are ignored', async () => {
  const s = shell();
  s.bridge.makeVideo = async (request) => {
    s.calls.push({ name: 'makeVideo', args: [request] });
    s.job({ ...running({ percent: 20 }), jobId: 'job-7' });
    return { status: 'started', jobId: 'job-7' };
  };
  startApp(s.bridge, s.boot);
  await tick();
  await chooseAudio();
  await chooseImage();
  await makeVideo('ask');
  const job = appState().job;
  assert.ok(job.phase === 'running');
  assert.equal(job.jobId, 'job-7');
  assert.equal(job.percent, 20);
  s.job({ ...running({ percent: 90 }), jobId: 'job-other' });
  assert.equal((appState().job as { percent: number }).percent, 20);
});

test('the save dialog closed without a choice changes nothing', async () => {
  await ready({ start: { status: 'dismissed' } });
  await makeVideo('ask');
  assert.equal(appState().job.phase, 'idle');
  assert.equal(appState().failure, null);
});

test('a failure says its sentence; the same failure with the same inputs says it again; a change of inputs starts over', async () => {
  const s = await ready();
  await makeVideo('ask');
  s.job(failed('output_in_use'));
  assert.equal(appState().failure?.again, false);
  assert.equal(statusOf(appState()).button?.label, 'Try Again');
  await runAction('try-again');
  assert.equal((s.calls.filter((c) => c.name === 'makeVideo').at(-1)?.args[0] as MakeRequest).destination, 'same');
  s.job(failed('output_in_use'));
  assert.equal(appState().failure?.again, true);
  assert.equal(statusOf(appState()).button?.label, 'Copy Details');
  setShape('1:1');
  await makeVideo('ask');
  s.job(failed('output_in_use'));
  assert.equal(appState().failure?.again, false, 'different inputs: a new failure');
  await makeVideo('ask');
  s.job(done());
  await makeVideo('ask');
  s.job(failed('output_in_use'));
  assert.equal(appState().failure?.again, false, 'a success in between starts over');
});

test('each filled button does what it says: choose again, use H.264, choose another place', async () => {
  const s = await ready({ codec: 'hevc' });
  assert.equal(appState().codec, 'hevc');
  await makeVideo('ask');
  s.job(failed('codec_unavailable'));
  await runAction('use-h264');
  assert.equal(appState().codec, 'h264');
  assert.equal(appState().failure, null);
  assert.deepEqual(s.calls.filter((c) => c.name === 'setPreferences').map((c) => c.args), [[{ codec: 'h264' }]]);
  await makeVideo('ask');
  s.job(failed('image_not_found'));
  s.bridge.chooseImage = async () => (s.calls.push({ name: 'chooseImage', args: [] }), { status: 'chosen', file: { ...cover, id: 'f_cover_again' } }); // a new choice is a new id, as the shell makes it
  await runAction('choose-image');
  assert.equal(s.calls.filter((c) => c.name === 'chooseImage').length, 2);
  assert.equal(appState().failure, null, 'a new image clears the failure about the old one');
  await makeVideo('ask');
  s.job(failed('disk_full'));
  await runAction('choose-folder');
  assert.equal((s.calls.filter((c) => c.name === 'makeVideo').at(-1)?.args[0] as MakeRequest).destination, 'ask');
});

test('a tool that is missing or the wrong version is the one blocking state, and nothing can be made', async () => {
  const s = shell({ tool: { state: 'damaged', code: 'TOOL_NOT_FOUND', details: 'x' }, encoders: null });
  startApp(s.bridge, s.boot);
  await tick();
  assert.equal(canMake(appState()), false);
  await chooseAudio();
  await chooseImage();
  assert.equal(canMake(appState()), false);
  resetApp();
  const t = await ready();
  assert.equal(canMake(appState()), true);
  t.tool({ state: 'damaged', code: 'TOOL_INCOMPATIBLE', details: 'x' });
  assert.equal(canMake(appState()), false, 'a cached ready answer overturned after launch');
  resetApp();
  const u = await ready();
  await makeVideo('ask');
  u.job(failed('TOOL_NOT_FOUND'));
  assert.equal(appState().tool.state, 'damaged');
  assert.equal(appState().failure, null, 'the blocking state replaces a failure, it does not stack with one');
  assert.equal(appState().job.phase, 'idle');
});

test('HEVC: the choice starts on H.264 where it cannot be made, stays remembered, and comes back where it can', async () => {
  const s = shell({ codec: 'hevc', encoders: NO_HEVC });
  startApp(s.bridge, s.boot);
  assert.equal(appState().codec, 'h264');
  assert.equal(appState().savedCodec, 'hevc');
  setCodec('hevc');
  assert.equal(appState().codec, 'h264', 'cannot be chosen');
  assert.equal(s.calls.filter((c) => c.name === 'setPreferences').length, 0, 'and nothing is saved for it');
  s.encoders(NVENC);
  assert.equal(appState().codec, 'hevc', 'it comes back on a computer that can make it');
  s.encoders(NO_HEVC);
  assert.equal(appState().codec, 'h264');
  assert.equal(appState().savedCodec, 'hevc');
});

test('a Codec chosen is saved at once, and an unknown report does not take the choice away', async () => {
  const s = shell({ encoders: null });
  startApp(s.bridge, s.boot);
  setCodec('hevc');
  assert.deepEqual(s.calls.filter((c) => c.name === 'setPreferences').map((c) => c.args), [[{ codec: 'hevc' }]]);
  assert.equal(appState().codec, 'hevc');
  s.encoders(NVENC);
  assert.equal(appState().codec, 'hevc');
});

test('a drop into empty slots fills them; onto filled ones it asks, and Keep Current is the way out', async () => {
  const s = shell();
  startApp(s.bridge, s.boot);
  applyDrop({ status: 'ok', audio: song, image: cover });
  await tick();
  assert.equal(appState().audio?.id, 'f_song');
  assert.equal(appState().replace, null);
  const other: AudioInfo = { id: 'f_other', name: 'Other.mp3', durationSeconds: 61 };
  applyDrop({ status: 'ok', audio: other, image: null });
  assert.equal(appState().replace?.title, 'Replace the current song?');
  assert.equal(appState().audio?.id, 'f_song', 'nothing changes until the person answers');
  assert.equal(canMake(appState()), false, 'and nothing can be made while the question is open');
  answerReplace(false);
  assert.equal(appState().audio?.id, 'f_song');
  assert.deepEqual(s.calls.filter((c) => c.name === 'releaseFiles').at(-1)?.args, [['f_other']], 'the dropped file that was not kept is freed');
  applyDrop({ status: 'ok', audio: other, image: null });
  answerReplace(true);
  assert.equal(appState().audio?.id, 'f_other');
  assert.deepEqual(s.calls.filter((c) => c.name === 'releaseFiles').at(-1)?.args, [['f_song']], 'the song that was replaced is freed');
});

test('a rejected drop changes nothing and says why; a drop during a job is refused in words without asking the shell', async () => {
  const s = await ready();
  applyDrop({ status: 'rejected', reason: 'too-many' });
  assert.deepEqual(appState().notice, { first: 'That is more than two files.', second: 'Drop one song, one image, or one of each.' });
  assert.equal(appState().audio?.id, 'f_song');
  await makeVideo('ask');
  const { dropFiles } = await import('../src/state/app.ts');
  await dropFiles([]);
  assert.deepEqual(appState().notice, { first: 'Wait for the current video to finish.', second: '' });
  assert.equal(s.calls.filter((c) => c.name === 'dropFiles').length, 0);
  s.opened({ status: 'ok', audio: { id: 'f_x', name: 'X.mp3', durationSeconds: 1 }, image: null });
  assert.equal(appState().replace, null, 'a file opened with the app during a job is refused too');
  assert.deepEqual(s.calls.filter((c) => c.name === 'releaseFiles').at(-1)?.args, [['f_x']]);
});

test('a file chosen that fails its check is a failure with its filled button, and changes nothing', async () => {
  const s = shell();
  s.bridge.chooseAudio = async () => ({ status: 'unusable', problem: { code: 'audio_unreadable', details: '{}' } });
  startApp(s.bridge, s.boot);
  await chooseAudio();
  assert.equal(appState().audio, null);
  assert.equal(appState().failure?.code, 'audio_unreadable');
  assert.equal(statusOf(appState()).button?.label, 'Choose Audio…');
});

// ---- S2V-031: the controls say what the message says ---------------------------------------------

test('a job that fails because a loaded file is gone marks that slot, holds Make Video, and a new file frees it', async () => {
  const s = await ready();
  await makeVideo('ask');
  s.job(failed('audio_not_found'));
  assert.equal(appState().failure?.of, 'audio');
  assert.equal(canMake(appState()), false, 'Make Video would only fail the same way');
  assert.equal(statusOf(appState()).button?.label, 'Choose Audio…');
  // Another song replaces the one that was lost: everything comes back.
  s.bridge.chooseAudio = async () => ({ status: 'chosen', file: { id: 'f_song2', name: 'Other.mp3', durationSeconds: 10 } });
  await chooseAudio();
  assert.equal(appState().failure, null);
  assert.equal(canMake(appState()), true);
});

test('an image that cannot be drawn is a problem with the image: the bar says so and Make Video waits', async () => {
  const s = shell();
  s.bridge.previewImage = async () => ({ status: 'failed', problem: { code: 'IMAGE_UNREADABLE', details: '{}' } });
  startApp(s.bridge, s.boot);
  await chooseAudio();
  await chooseImage();
  await tick();
  assert.equal(appState().preview?.status, 'failed');
  assert.equal(appState().failure?.of, 'image');
  assert.equal(appState().failure?.code, 'image_unreadable', 'a code the page does not know is the unreadable image');
  assert.equal(canMake(appState()), false);
  assert.notEqual(statusOf(appState()).first, 'Ready to make your video.');
  assert.equal(statusOf(appState()).tone, 'danger');
});

test('a file that is rejected when chosen does not mark the slot of the file that was already good', async () => {
  const s = await ready();
  s.bridge.chooseAudio = async () => ({ status: 'unusable', problem: { code: 'audio_unreadable', details: '{}' } });
  await chooseAudio();
  assert.equal(appState().failure?.code, 'audio_unreadable');
  assert.equal(appState().failure?.of, null);
  assert.equal(canMake(appState()), true, 'the song that was chosen before is still fine');
});

test('HEVC chosen after the tool said this computer cannot make it holds Make Video until H.264 is chosen', async () => {
  const s = await ready();
  setCodec('hevc');
  await makeVideo('ask');
  s.job(failed('codec_unavailable'));
  assert.equal(canMake(appState()), false);
  assert.equal(statusOf(appState()).button?.label, 'Use H.264');
  await runAction('use-h264');
  assert.equal(canMake(appState()), true);
});

test('an image too small for its frame is said by the bar in the table\'s words, not "Ready"', async () => {
  const s = shell();
  s.bridge.chooseImage = async () => ({ status: 'chosen', file: { id: 'f_tiny', name: 'Tiny.png', width: 10, height: 10, frames: [] } });
  startApp(s.bridge, s.boot);
  await chooseAudio();
  await chooseImage();
  setShape('original');
  await tick();
  assert.equal(canMake(appState()), false);
  assert.deepEqual([statusOf(appState()).first, statusOf(appState()).second, statusOf(appState()).button?.label], ['This image is too small.', 'Each side needs at least 16 pixels.', 'Choose Image…']);
});

test('a missing tool says nothing that could be taken for ready', async () => {
  await ready({ tool: { state: 'damaged', code: 'TOOL_NOT_FOUND', details: '{}' } });
  const view = statusOf(appState());
  assert.equal(view.kind, 'blocked');
  assert.equal(view.first, '');
});

test('a dropped file that is refused is named when there is one, and the refusal has the warning tone', async () => {
  const s = await ready();
  s.bridge.dropFiles = async () => ({ status: 'rejected', reason: 'unsupported' });
  const { dropFiles } = await import('../src/state/app.ts');
  await dropFiles([{ name: 'Notes.txt' } as File]);
  assert.equal(appState().notice?.first, '\u201cNotes.txt\u201d is not a song or an image Song2Vid can use.');
  assert.equal(appState().notice?.second, 'Drop a song or an image.');
  assert.equal(statusOf(appState()).tone, 'warning');
});
