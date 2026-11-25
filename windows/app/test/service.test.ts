// The shell's side of each tool call (electron/tool/service.ts) against the stand-in tool, with
// the Windows dialogs replaced by a queue of answers: choosing and dropping files, the preview,
// the job and every way it ends, cancel, the job records and what a launch does with them, and
// the launch checks (SPEC 24.8, 27.2, 27.4, 27.6).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import type { TestContext } from 'node:test';
import type { AudioInfo, DropResult, EncoderReport, ImageInfo, JobUpdate, MakeRequest, ToolStatus } from '../src/bridge.ts';
import { EXIT_STATUS } from '../electron/tool/contract.ts';
import type { Limits } from '../electron/tool/adapter.ts';
import { createToolService } from '../electron/tool/service.ts';
import { sandbox, temporaryFiles, waitFor } from './helpers.ts';

interface Options {
  limits?: Partial<Limits>;
  /** Start the service on a data folder that earlier runs used. */
  box?: ReturnType<typeof sandbox>;
  start?: boolean;
}

function harness(t: TestContext, config: Record<string, unknown> = {}, options: Options = {}) {
  const box = options.box ?? sandbox(t, config);
  fs.mkdirSync(box.dataDir, { recursive: true });
  const outDir = path.join(box.dir, 'Videos');
  fs.mkdirSync(outDir, { recursive: true });
  const updates: JobUpdate[] = [];
  const encoders: EncoderReport[] = [];
  const opened: DropResult[] = [];
  const statuses: ToolStatus[] = [];
  const picks = { audio: [] as (string | null)[], image: [] as (string | null)[], save: [] as (string | null)[] };
  const saveDefaults: string[] = [];
  const shown: string[] = [];
  /** Set it to hold the save dialog open until it resolves. */
  const gate = { current: null as Promise<void> | null };
  const service = createToolService({
    located: box.located,
    dataDir: box.dataDir,
    ui: {
      pickFile: async (kind) => picks[kind].shift() ?? null,
      pickSave: async (defaultPath) => {
        saveDefaults.push(defaultPath);
        if (gate.current) await gate.current;
        return picks.save.shift() ?? null;
      },
      showInFolder: (file) => shown.push(file),
    },
    videosDir: () => outDir,
    emit: { job: (u) => updates.push(u), encoders: (r) => encoders.push(r), filesOpened: (r) => opened.push(r), toolStatus: (status) => statuses.push(status) },
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
    limits: { graceMs: 500, ...(options.limits ?? {}) },
  });
  if (options.start !== false) service.start();
  const song = path.join(box.dir, 'Song.mp3');
  const cover = path.join(box.dir, 'Cover.png');
  const finished = (ms = 20_000) => waitFor(() => updates.some((u) => u.state !== 'running'), ms);
  const last = () => updates.at(-1);
  const request = (audio: AudioInfo, image: ImageInfo, over: Partial<MakeRequest> = {}): MakeRequest => ({ audioId: audio.id, imageId: image.id, shape: '16:9', resolution: '1080p', crop: null, codec: 'h264', destination: 'ask', ...over });
  /** Choose a song and an image the way the page does, and give back what the page holds. */
  async function load() {
    picks.audio.push(song);
    picks.image.push(cover);
    const a = await service.chooseAudio();
    const i = await service.chooseImage();
    assert.ok(a.status === 'chosen' && i.status === 'chosen');
    return { audio: a.file, image: i.file };
  }
  return { box, service, updates, encoders, opened, statuses, picks, saveDefaults, shown, gate, outDir, song, cover, finished, last, request, load };
}

type H = ReturnType<typeof harness>;
const noProcessLeft = async (box: H['box'], ms = 3000) => assert.equal(await waitFor(() => box.alive().length === 0, ms), true, `still alive: ${box.alive().join(', ')}`);
const hasPath = (value: unknown, ...paths: string[]) => paths.some((p) => JSON.stringify(value).includes(JSON.stringify(p).slice(1, -1)));

// ---- the launch -------------------------------------------------------------------------

test('launch: the tool says song2vid 1.2.0 and the Encoder report arrives as an event and in the next bootstrap', async (t) => {
  const h = harness(t);
  assert.deepEqual(await h.service.status(), { state: 'ready', code: null, details: 'song2vid 1.2.0' });
  await h.service.settled();
  assert.deepEqual(h.encoders, [{ h264: { available: true, encoder: 'nvenc' }, hevc: { available: true, encoder: 'nvenc' } }]);
  assert.deepEqual(h.service.encoders(), h.encoders[0]);
  assert.deepEqual(h.box.starts().map((s) => s.argv), [['--version', '--json'], ['encoders', '--json']]);
});

test('launch: the last answer is shown at once, the launch\'s own check refreshes it in the background', async (t) => {
  const first = harness(t);
  await first.service.status();
  await first.service.settled();
  // The next launch: the tool's answers have changed (a driver update), and the version check is slow.
  fs.writeFileSync(path.join(first.box.dir, 'standin.json'), JSON.stringify({ log: path.join(first.box.dir, 'starts.ndjson'), encoders: 'encoders-no-hevc', version: 'version-ok' }));
  const second = harness(t, {}, { box: first.box, start: false });
  second.service.start();
  assert.deepEqual(await Promise.race([second.service.status(), new Promise((r) => setTimeout(() => r('waited'), 5000))]), { state: 'ready', code: null, details: 'song2vid 1.2.0' });
  assert.deepEqual(second.service.encoders(), { h264: { available: true, encoder: 'nvenc' }, hevc: { available: true, encoder: 'nvenc' } }, 'the cached report, before the refresh');
  await second.service.settled();
  assert.deepEqual(second.service.encoders(), { h264: { available: true, encoder: 'software' }, hevc: { available: false, encoder: null } });
  assert.deepEqual(second.encoders.at(-1), second.service.encoders());
});

test('launch: a tool that is no longer the right version is the one blocking state, and no job starts or asks for a folder', async (t) => {
  const h = harness(t, { version: 'version-wrong' });
  const status = await h.service.status();
  assert.deepEqual([status.state, status.code], ['damaged', 'TOOL_INCOMPATIBLE']);
  assert.deepEqual(h.service.encoders(), null, 'no encoders are asked of the wrong tool');
  const audio = { id: 'f_x' } as AudioInfo;
  const image = { id: 'f_y' } as ImageInfo;
  const started = await h.service.makeVideo(h.request(audio, image));
  assert.equal(started.status, 'started');
  await h.finished();
  const update = h.last();
  assert.ok(update?.state === 'failed');
  assert.equal(update.problem.code, 'usage', 'ids that were never given are refused first');
  h.picks.audio.push(h.song);
  const chosen = await h.service.chooseAudio();
  assert.ok(chosen.status === 'unusable');
  assert.equal(chosen.problem.code, 'TOOL_INCOMPATIBLE');
  assert.deepEqual(h.saveDefaults, []);
});

test('launch: a missing tool is TOOL_NOT_FOUND', async (t) => {
  const box = sandbox(t);
  const service = createToolService({ located: { ok: false, code: 'TOOL_NOT_FOUND', details: 'No runnable song2vid.exe' }, dataDir: box.dataDir, ui: { pickFile: async () => null, pickSave: async () => null, showInFolder: () => {} }, videosDir: () => box.dir, emit: { job: () => {}, encoders: () => {}, filesOpened: () => {} } });
  service.start();
  const status = await service.status();
  assert.deepEqual([status.state, status.code], ['damaged', 'TOOL_NOT_FOUND']);
});

test('launch: a version check that stalls with a good cache turns the ready state damaged, and a job then fails with the code', async (t) => {
  const first = harness(t);
  await first.service.settled();
  fs.writeFileSync(path.join(first.box.dir, 'standin.json'), JSON.stringify({ log: path.join(first.box.dir, 'starts.ndjson'), version: 'version-silent' }));
  const second = harness(t, {}, { box: first.box, start: false, limits: { versionMs: 500 } });
  second.service.start();
  assert.equal((await second.service.status()).state, 'ready', 'the cache serves the first answer');
  await second.service.settled();
  const status = await second.service.status();
  assert.deepEqual([status.state, status.code], ['damaged', 'TOOL_STALLED']);
  assert.deepEqual(second.statuses.map((s) => [s.state, s.code]), [['damaged', 'TOOL_STALLED']], 'the page is told as soon as the cached answer is overturned');
  assert.deepEqual(first.statuses, [], 'a launch whose check agrees with the cache says nothing more');
  await noProcessLeft(first.box);
});

// ---- choosing and dropping files -----------------------------------------------------------

test('choose: a song and an image come back with opaque ids and the tool\'s facts; no path reaches the page', async (t) => {
  const h = harness(t);
  const { audio, image } = await h.load();
  assert.deepEqual([audio.name, audio.durationSeconds], ['Song.mp3', 144]);
  assert.deepEqual([image.name, image.width, image.height, image.frames.length], ['Cover.png', 1600, 1200, 13]);
  assert.equal(hasPath([audio, image], h.box.dir, h.song, h.cover), false);
  assert.match(audio.id, /^f_[0-9a-f]{18}$/);
  assert.deepEqual(h.box.starts().filter((s) => s.argv[0] === 'check').map((s) => s.argv), [['check', h.song, '--json'], ['check', h.cover, '--json']], 'one one-file check for each');
});

test('choose: dismissing the dialog changes nothing; an unusable file says why and gets no id', async (t) => {
  const h = harness(t, { check_image: 'check-error', vars: { code: 'image_too_small', exit: 3 } });
  assert.deepEqual(await h.service.chooseAudio(), { status: 'dismissed' });
  assert.deepEqual(await h.service.chooseImage(), { status: 'dismissed' });
  h.picks.image.push(h.cover);
  const result = await h.service.chooseImage();
  assert.ok(result.status === 'unusable');
  assert.equal(result.problem.code, 'image_too_small');
  assert.equal(hasPath(result, h.box.dir), false);
  assert.equal(h.service.diagnostics()['files'], 0);
});

test('drop: a song and an image are each checked and given ids; the page decides what they replace', async (t) => {
  const h = harness(t);
  const result = await h.service.dropFiles([h.cover, h.song]);
  assert.ok(result.status === 'ok');
  assert.ok(result.audio && result.image);
  assert.deepEqual([result.audio.name, result.image.name], ['Song.mp3', 'Cover.png']);
  const one = await h.service.dropFiles([h.song]);
  assert.ok(one.status === 'ok');
  assert.deepEqual([one.audio?.name, one.image], ['Song.mp3', null]);
});

test('drop: every rejection of SPEC 4a changes nothing and holds no id', async (t) => {
  const h = harness(t);
  const folder = path.join(h.box.dir, 'Album');
  fs.mkdirSync(folder);
  const p = (name: string) => path.join(h.box.dir, name);
  const cases: [string[], string][] = [
    [[p('a.mp3'), p('b.wav')], 'more-audio'],
    [[p('a.png'), p('b.jpg')], 'more-images'],
    [[p('a.mp3'), p('b.png'), p('c.png')], 'too-many'],
    [[folder], 'folder'],
    [[p('notes.txt')], 'unsupported'],
    [[], 'unsupported'],
  ];
  for (const [paths, reason] of cases) assert.deepEqual(await h.service.dropFiles(paths), { status: 'rejected', reason }, reason);
  assert.equal(h.service.diagnostics()['files'], 0);
  assert.equal(h.box.starts().filter((s) => s.argv[0] === 'check').length, 0, 'the tool was not asked about a drop that fails by type');
});

test('drop: a file that fails the check rejects the whole drop, and a good file dropped with it keeps no id', async (t) => {
  const h = harness(t, { check_image: 'check-error', vars: { code: 'image_unreadable', exit: 3 } });
  assert.deepEqual(await h.service.dropFiles([h.song, h.cover]), { status: 'rejected', reason: 'unreadable' });
  assert.equal(h.service.diagnostics()['files'], 0, 'the song that was fine is released with it');
  assert.deepEqual(await h.service.dropFiles([h.cover]), { status: 'rejected', reason: 'unreadable' });
});

test('a file opened with the app is judged as a drop is and sent to the page', async (t) => {
  const h = harness(t);
  await h.service.openFiles([h.song]);
  assert.equal(h.opened.length, 1);
  assert.ok(h.opened[0]?.status === 'ok');
});

test('release: an id the page will not use is gone, and so is any make request that names it', async (t) => {
  const h = harness(t);
  const { audio, image } = await h.load();
  h.service.releaseFiles([audio.id]);
  const started = await h.service.makeVideo(h.request(audio, image));
  assert.equal(started.status, 'started');
  await h.finished();
  assert.ok(h.last()?.state === 'failed');
  assert.deepEqual(h.saveDefaults, [], 'no dialog for a request that is refused');
});

// ---- the preview ---------------------------------------------------------------------------

test('preview: the picture the video will see, as a data address the page\'s policy allows, and no file is kept', async (t) => {
  const h = harness(t);
  const { image } = await h.load();
  const result = await h.service.previewImage(image.id);
  assert.ok(result.status === 'ready');
  assert.match(result.src, /^data:image\/png;base64,/);
  assert.deepEqual([result.width, result.height], [2048, 1536]);
  assert.equal(Buffer.from(result.src.split(',')[1] ?? '', 'base64').subarray(1, 4).toString(), 'PNG');
  assert.deepEqual(fs.readdirSync(path.join(h.box.dataDir, 'previews')), []);
  const preview = h.box.starts().find((s) => s.argv[0] === 'preview');
  assert.deepEqual([preview?.argv[1], preview?.argv.includes('--cancel-on-eof')], [h.cover, true]);
});

test('preview: two previews at once do not disturb each other', async (t) => {
  const h = harness(t);
  const { image } = await h.load();
  h.picks.image.push(path.join(h.box.dir, 'Second.png'));
  const second = await h.service.chooseImage();
  assert.ok(second.status === 'chosen');
  const both = await Promise.all([h.service.previewImage(image.id), h.service.previewImage(second.file.id), h.service.previewImage(image.id)]);
  assert.deepEqual(both.map((r) => r.status), ['ready', 'ready', 'ready']);
  assert.deepEqual(fs.readdirSync(path.join(h.box.dataDir, 'previews')), []);
});

test('preview: an id that is not an image, and a tool that refuses, are failures with a code', async (t) => {
  const h = harness(t, { preview: 'preview-error' });
  const { audio, image } = await h.load();
  const wrong = await h.service.previewImage(audio.id);
  assert.ok(wrong.status === 'failed');
  assert.equal(wrong.problem.code, 'usage');
  const refused = await h.service.previewImage(image.id);
  assert.ok(refused.status === 'failed');
  assert.equal(refused.problem.code, 'image_unreadable');
});

test('preview: releasing the image stops a preview that is still being made', async (t) => {
  const h = harness(t, { preview: 'preview-slow' });
  const { image } = await h.load();
  const pending = h.service.previewImage(image.id);
  assert.equal(await waitFor(() => h.box.starts().some((s) => s.argv[0] === 'preview'), 5000), true);
  h.service.releaseFiles([image.id]);
  const result = await pending;
  assert.ok(result.status === 'failed');
  assert.equal(result.problem.code, 'cancelled');
  await noProcessLeft(h.box);
});

// ---- the job -------------------------------------------------------------------------------

test('make: the save dialog opens at the audio file\'s name in Videos; the video is made; the page learns the name and the folder\'s own name', async (t) => {
  const h = harness(t);
  const { audio, image } = await h.load();
  h.picks.save.push(path.join(h.outDir, 'Song.mp4'));
  const started = await h.service.makeVideo(h.request(audio, image, { codec: 'hevc' }));
  assert.ok(started.status === 'started');
  assert.deepEqual(h.saveDefaults, [path.join(h.outDir, 'Song.mp4')]);
  assert.equal(h.service.jobRunning, true);
  assert.equal(await h.finished(), true);
  const done = h.last();
  assert.ok(done?.state === 'done');
  assert.equal(done.jobId, started.jobId);
  assert.deepEqual({ ...done.result, outputId: '' }, { outputId: '', fileName: 'Song.mp4', where: 'Videos', width: 1920, height: 1080, durationSeconds: 144, bytes: 6153216, codec: 'hevc', encoder: 'nvenc', encoderFallback: false });
  assert.equal(hasPath(h.updates, h.box.dir), false, 'no path in any update');
  assert.equal(h.service.jobRunning, false, 'the controls unlock straight away');
  assert.equal(fs.readFileSync(path.join(h.outDir, 'Song.mp4'), 'utf8'), 'standin output\n');
  assert.deepEqual(temporaryFiles(h.outDir), []);
  assert.deepEqual(fs.readdirSync(path.join(h.box.dataDir, 'jobs')), [], 'the record is gone at the end');
  h.service.showInFolder(done.result.outputId);
  h.service.showInFolder('f_unknown');
  h.service.showInFolder(audio.id);
  assert.deepEqual(h.shown, [path.join(h.outDir, 'Song.mp4')], 'only the saved file, only by its output id');
  await noProcessLeft(h.box);
});

test('make: the updates run in order, percent never goes back, and the Encoder is known from the encoding stage', async (t) => {
  const h = harness(t);
  const { audio, image } = await h.load();
  h.picks.save.push(path.join(h.outDir, 'Song.mp4'));
  await h.service.makeVideo(h.request(audio, image));
  await h.finished();
  const running = h.updates.filter((u) => u.state === 'running');
  assert.ok(running.length >= 5);
  assert.equal(h.updates.filter((u) => u.state !== 'running').length, 1, 'exactly one end');
  assert.ok(h.last()?.state === 'done', 'and it is the last');
  const stages = running.map((u) => u.state === 'running' && u.stage).filter((s, i, all) => all.indexOf(s) === i);
  assert.deepEqual(stages, ['checking', 'preparing', 'encoding', 'finishing']);
  const percents = running.map((u) => (u.state === 'running' ? u.percent : null)).filter((p): p is number => p !== null);
  assert.ok(percents.every((p, i) => i === 0 || p >= (percents[i - 1] ?? 0)) && Math.max(...percents) <= 99);
  const first = running[0];
  assert.ok(first?.state === 'running');
  assert.deepEqual([first.stage, first.percent, first.encoder, first.stalled], ['checking', null, null, false]);
  assert.ok(running.some((u) => u.state === 'running' && u.stage === 'encoding' && u.encoder === 'nvenc'));
});

test('make: a second Make Video while one is running is busy', async (t) => {
  const h = harness(t, { make: 'make-slow' });
  const { audio, image } = await h.load();
  h.picks.save.push(path.join(h.outDir, 'Song.mp4'));
  const first = await h.service.makeVideo(h.request(audio, image));
  assert.equal(first.status, 'started');
  assert.deepEqual(await h.service.makeVideo(h.request(audio, image)), { status: 'busy' });
  h.service.cancelJob(first.status === 'started' ? first.jobId : null);
  await h.finished();
});

test('make: a second Make Video is busy even while the save dialog of the first is still open', async (t) => {
  const h = harness(t);
  const { audio, image } = await h.load();
  let open: () => void = () => {};
  h.gate.current = new Promise<void>((resolve) => (open = resolve));
  h.picks.save.push(path.join(h.outDir, 'Song.mp4'));
  const first = h.service.makeVideo(h.request(audio, image));
  assert.deepEqual(await h.service.makeVideo(h.request(audio, image)), { status: 'busy' });
  open();
  assert.equal((await first).status, 'started');
  await h.finished();
  assert.ok(h.last()?.state === 'done');
});

test('make: the save dialog starts in the last folder saved to, "same" reuses the destination without a dialog, a dismissed dialog starts nothing', async (t) => {
  const h = harness(t);
  const { audio, image } = await h.load();
  const elsewhere = path.join(h.box.dir, 'Elsewhere');
  fs.mkdirSync(elsewhere);
  h.picks.save.push(path.join(elsewhere, 'Mine.mp4'));
  await h.service.makeVideo(h.request(audio, image));
  await h.finished();
  assert.ok(h.last()?.state === 'done');
  assert.ok(fs.existsSync(path.join(elsewhere, 'Mine.mp4')));
  // Try Again: the same destination, with no dialog (and the person's earlier "replace" answer, here none).
  h.updates.length = 0;
  await h.service.makeVideo(h.request(audio, image, { destination: 'same' }));
  assert.deepEqual(h.saveDefaults.length, 1, 'no second dialog');
  await h.finished();
  const second = h.last();
  assert.ok(second?.state === 'done');
  const makes = h.box.starts().filter((s) => s.argv[0] === 'make');
  assert.equal(makes[1]?.argv.includes('--overwrite'), false, 'a destination that was free is still not replaced unasked');
  // A new "ask" starts in the folder used last, and closing the dialog changes nothing.
  h.updates.length = 0;
  assert.deepEqual(await h.service.makeVideo(h.request(audio, image)), { status: 'dismissed' });
  assert.deepEqual(h.saveDefaults.at(-1), path.join(elsewhere, 'Song.mp4'));
  assert.equal(h.service.jobRunning, false);
  assert.deepEqual(h.updates, []);
  assert.equal(h.box.starts().filter((s) => s.argv[0] === 'make').length, 2, 'the tool was not started');
  assert.deepEqual(fs.readdirSync(path.join(h.box.dataDir, 'jobs')), []);
});

test('make: a folder that failed is not remembered as the last folder saved to', async (t) => {
  const h = harness(t, { make: 'make-error', vars: { code: 'output_not_writable', exit: 4 } });
  const { audio, image } = await h.load();
  const elsewhere = path.join(h.box.dir, 'Elsewhere');
  fs.mkdirSync(elsewhere);
  h.picks.save.push(path.join(elsewhere, 'Song.mp4'));
  await h.service.makeVideo(h.request(audio, image));
  await h.finished();
  assert.ok(h.last()?.state === 'failed');
  assert.deepEqual(await h.service.makeVideo(h.request(audio, image)), { status: 'dismissed' });
  assert.equal(h.saveDefaults.at(-1), path.join(h.outDir, 'Song.mp4'), 'Videos again');
});

test('make: --overwrite only when the system\'s dialog found the file there and the person confirmed; a name without .mp4 gets it and never replaces', async (t) => {
  const h = harness(t);
  const { audio, image } = await h.load();
  const taken = path.join(h.outDir, 'Taken.mp4');
  fs.writeFileSync(taken, 'old');
  h.picks.save.push(taken, path.join(h.outDir, 'Fresh.mp4'), path.join(h.outDir, 'NoExtension'), taken.replace('Taken.mp4', 'Taken'));
  for (let i = 0; i < 4; i++) {
    h.updates.length = 0;
    await h.service.makeVideo(h.request(audio, image));
    await h.finished();
  }
  const outs = h.box.starts().filter((s) => s.argv[0] === 'make');
  assert.deepEqual(
    outs.map((s) => [path.basename(s.argv[s.argv.indexOf('--out') + 1] ?? ''), s.argv.includes('--overwrite')]),
    [['Taken.mp4', true], ['Fresh.mp4', false], ['NoExtension.mp4', false], ['Taken.mp4', false]],
  );
});

test('make: a request the page should never send is refused with a code, and no flag or path of the page reaches the tool', async (t) => {
  const h = harness(t);
  const { audio, image } = await h.load();
  const startsBefore = h.box.starts().length;
  for (const bad of [{ ...h.request(audio, image), shape: '--help' }, { ...h.request(audio, image), destination: 'C:\\x.mp4' }, null, { ...h.request(audio, image), imageId: audio.id }]) {
    h.updates.length = 0;
    const started = await h.service.makeVideo(bad);
    assert.equal(started.status, 'started');
    await h.finished();
    const update = h.last();
    assert.ok(update?.state === 'failed');
    assert.equal(update.problem.code, 'usage');
    assert.equal(h.service.jobRunning, false);
  }
  assert.equal(h.box.starts().length, startsBefore, 'the tool was never started');
  assert.deepEqual(h.saveDefaults, []);
});

test('make: every tool error code ends the job as failed with that code, nothing is left behind, and Try Again works at once', async (t) => {
  for (const [code, exit] of Object.entries(EXIT_STATUS)) {
    if (code === 'cancelled') continue;
    const h = harness(t, { make: 'make-error-after-encoding', vars: { code, exit, message: `message for ${code}` } });
    const { audio, image } = await h.load();
    h.picks.save.push(path.join(h.outDir, 'Song.mp4'));
    await h.service.makeVideo(h.request(audio, image));
    await h.finished();
    const update = h.last();
    assert.ok(update?.state === 'failed', code);
    assert.equal(update.problem.code, code);
    assert.equal(h.service.jobRunning, false, 'job cleared before the update');
    assert.equal(hasPath(update, h.box.dir), false, `${code}: no path in Copy Details`);
    assert.match(update.problem.details, new RegExp(`message for ${code}`));
    assert.deepEqual(fs.readdirSync(path.join(h.box.dataDir, 'jobs')), []);
    await noProcessLeft(h.box);
  }
});

test('make: a code from a newer tool is passed on for the page to give its generic sentence', async (t) => {
  const h = harness(t, { make: 'make-error', vars: { code: 'something_new', exit: 5 } });
  const { audio, image } = await h.load();
  h.picks.save.push(path.join(h.outDir, 'Song.mp4'));
  await h.service.makeVideo(h.request(audio, image));
  await h.finished();
  const update = h.last();
  assert.ok(update?.state === 'failed');
  assert.equal(update.problem.code, 'something_new');
});

test('make: a fallback to the next Encoder reaches the page', async (t) => {
  const h = harness(t, { make: 'make-fallback' });
  const { audio, image } = await h.load();
  h.picks.save.push(path.join(h.outDir, 'Song.mp4'));
  await h.service.makeVideo(h.request(audio, image));
  await h.finished();
  const done = h.last();
  assert.ok(done?.state === 'done');
  assert.deepEqual([done.result.encoder, done.result.encoderFallback], ['software', true]);
});

for (const [scenario, fault] of [
  ['make-crash', 'TOOL_CRASHED'],
  ['make-garbage', 'TOOL_PROTOCOL'],
  ['make-line-2mib', 'TOOL_PROTOCOL'],
  ['make-noise-10mb', 'TOOL_PROTOCOL'],
  ['make-silent-end', 'TOOL_CRASHED'],
  ['make-result-no-encoder', 'TOOL_PROTOCOL'],
] as const) {
  test(`make: a hostile tool (${scenario}) ends the job as export_failed, and the temporary file it left is removed (and only that one)`, async (t) => {
    const h = harness(t, { make: scenario });
    const { audio, image } = await h.load();
    const bystander = path.join(h.outDir, `.song2vid-${'c'.repeat(32)}.tmp`); // another program's job in the same folder
    fs.writeFileSync(bystander, 'not ours');
    const note = path.join(h.outDir, 'notes.txt');
    fs.writeFileSync(note, 'keep');
    h.picks.save.push(path.join(h.outDir, 'Song.mp4'));
    await h.service.makeVideo(h.request(audio, image));
    await h.finished();
    const update = h.last();
    assert.ok(update?.state === 'failed');
    assert.equal(update.problem.code, 'export_failed');
    assert.match(update.problem.details, new RegExp(fault));
    assert.equal(h.service.jobRunning, false);
    await noProcessLeft(h.box);
    const left = scenario === 'make-result-no-encoder' ? ['Song.mp4'] : [];
    assert.deepEqual(fs.readdirSync(h.outDir).filter((n) => n !== path.basename(bystander) && n !== 'notes.txt'), left);
    assert.equal(fs.existsSync(bystander), true, 'a file that was there before the job is never removed');
    assert.equal(fs.existsSync(note), true);
  });
}

test('make: a job going quiet is reported as stalled with the update, and recovers', async (t) => {
  const h = harness(t, { make: 'make-silence-mid-job' }, { limits: { stallMs: 400 } });
  const { audio, image } = await h.load();
  h.picks.save.push(path.join(h.outDir, 'Song.mp4'));
  await h.service.makeVideo(h.request(audio, image));
  await h.finished();
  const flags = h.updates.filter((u) => u.state === 'running').map((u) => u.state === 'running' && u.stalled);
  assert.ok(flags.includes(true));
  assert.equal(flags.at(-1), false);
  assert.ok(h.last()?.state === 'done');
});

test('make: the job is recorded before the tool starts and the record names the output folder only', async (t) => {
  const h = harness(t, { make: 'make-slow' });
  const { audio, image } = await h.load();
  h.picks.save.push(path.join(h.outDir, 'Song.mp4'));
  const started = await h.service.makeVideo(h.request(audio, image));
  assert.ok(started.status === 'started');
  const jobs = path.join(h.box.dataDir, 'jobs');
  assert.deepEqual(fs.readdirSync(jobs), [`${started.jobId}.json`], 'recorded as soon as the job is started');
  const record = JSON.parse(fs.readFileSync(path.join(jobs, `${started.jobId}.json`), 'utf8')) as Record<string, unknown>;
  assert.deepEqual(Object.keys(record).sort(), ['folder', 'jobId', 'startedAt']);
  assert.equal(record['folder'], h.outDir);
  h.service.cancelJob(started.jobId);
  await h.finished();
  assert.deepEqual(fs.readdirSync(jobs), []);
});

// ---- cancel ---------------------------------------------------------------------------------

test('cancel: the tool stops, removes its temporary file and the job ends cancelled within 2 s of the click', async (t) => {
  const h = harness(t, { make: 'make-slow' }, { limits: { graceMs: 2500 } });
  const { audio, image } = await h.load();
  h.picks.save.push(path.join(h.outDir, 'Song.mp4'));
  const started = await h.service.makeVideo(h.request(audio, image));
  assert.ok(started.status === 'started');
  assert.equal(await waitFor(() => h.updates.some((u) => u.state === 'running' && (u.percent ?? 0) >= 10), 10_000), true);
  h.service.cancelJob('j_not_this_one');
  assert.equal(h.service.jobRunning, true, 'a cancel for another job does nothing');
  const at = Date.now();
  h.service.cancelJob(started.jobId);
  assert.equal(await h.finished(2500), true);
  assert.ok(h.last()?.state === 'cancelled');
  assert.ok(Date.now() - at < 2000, `took ${Date.now() - at} ms`);
  assert.deepEqual(h.box.events().map((e) => e.event), ['cancel']);
  assert.deepEqual(fs.readdirSync(h.outDir), [], 'no video and no temporary file');
  assert.equal(h.service.jobRunning, false);
  await noProcessLeft(h.box, 2000);
});

test('cancel: a tool that ignores it is killed 3 s after stdin closes, and the temporary file it could not remove is removed', async (t) => {
  const h = harness(t, { make: 'make-cancel-ignored' }, { limits: { graceMs: 3000 } });
  const { audio, image } = await h.load();
  h.picks.save.push(path.join(h.outDir, 'Song.mp4'));
  const bystander = path.join(h.outDir, `.song2vid-${'d'.repeat(32)}.tmp`);
  fs.writeFileSync(bystander, 'not ours');
  const started = await h.service.makeVideo(h.request(audio, image));
  assert.ok(started.status === 'started');
  assert.equal(await waitFor(() => h.updates.some((u) => u.state === 'running' && u.percent === 5), 10_000), true);
  const at = Date.now();
  h.service.cancelJob(started.jobId);
  assert.equal(await h.finished(8000), true);
  const took = Date.now() - at;
  assert.ok(h.last()?.state === 'cancelled');
  assert.ok(took >= 2900 && took < 6000, `ended after ${took} ms`);
  assert.deepEqual(fs.readdirSync(h.outDir), [path.basename(bystander)]);
  await noProcessLeft(h.box, 2000);
});

// ---- the next launch ---------------------------------------------------------------------------

test('the next launch removes a leftover .song2vid-<32 hex>.tmp in a recorded folder, and nothing else', async (t) => {
  const box = sandbox(t);
  fs.mkdirSync(box.dataDir, { recursive: true });
  const recorded = path.join(box.dir, 'Recorded');
  const unrecorded = path.join(box.dir, 'Unrecorded');
  fs.mkdirSync(recorded);
  fs.mkdirSync(unrecorded);
  const leftover = `.song2vid-${'0123456789abcdef'.repeat(2)}.tmp`;
  const lookalikes = [`.song2vid-${'0123456789abcdef'.repeat(2)}.tmp.part`, '.song2vid-short.tmp', `${leftover.slice(1)}`, 'Song.mp4', `.example-${'0123456789abcdef'.repeat(2)}.tmp`];
  for (const folder of [recorded, unrecorded]) {
    fs.writeFileSync(path.join(folder, leftover), 'x');
    for (const name of lookalikes) fs.writeFileSync(path.join(folder, name), 'x');
  }
  const jobs = path.join(box.dataDir, 'jobs');
  fs.mkdirSync(jobs, { recursive: true });
  fs.writeFileSync(path.join(jobs, 'j_killed.json'), JSON.stringify({ jobId: 'j_killed', folder: recorded, startedAt: new Date().toISOString() }));
  const h = harness(t, {}, { box });
  assert.deepEqual(fs.readdirSync(recorded).sort(), [...lookalikes].sort());
  assert.deepEqual(fs.readdirSync(unrecorded).sort(), [leftover, ...lookalikes].sort(), 'a folder with no record is never touched');
  assert.deepEqual(fs.readdirSync(jobs), []);
  assert.deepEqual(h.service.diagnostics()['reconciled'], { records: 1, removed: 1 });
  await h.service.settled();
});
