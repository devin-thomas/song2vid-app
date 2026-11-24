// The adapter against the stand-in tool: the launch questions, one file's facts, the preview,
// a job's outcomes, every protocol fault, cancellation and a hostile tool (premium-bar rules
// 58, 59, 60 and 65; SPEC 27.6). Runs the same on Windows, macOS and Linux.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import type { TestContext } from 'node:test';
import { createAdapter } from '../electron/tool/adapter.ts';
import type { Limits } from '../electron/tool/adapter.ts';
import { EXIT_STATUS } from '../electron/tool/contract.ts';
import type { Line, MakeArgs } from '../electron/tool/contract.ts';
import { sandbox, temporaryFiles, waitFor } from './helpers.ts';
import type { Sandbox } from './helpers.ts';

function setup(t: TestContext, config: Record<string, unknown>, limits: Partial<Limits> = {}) {
  const box = sandbox(t, config);
  fs.mkdirSync(box.dataDir, { recursive: true });
  fs.mkdirSync(path.join(box.dir, 'out'));
  const adapter = createAdapter({ located: box.located, cwd: box.dataDir, env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' }, limits: { graceMs: 500, ...limits } });
  const song = path.join(box.dir, 'Song.mp3');
  const cover = path.join(box.dir, 'Cover.png');
  const output = path.join(box.dir, 'out', 'Song.mp4');
  const args = (over: Partial<MakeArgs> = {}): MakeArgs => ({ audio: song, image: cover, output, shape: '16:9', resolution: '1080p', crop: null, codec: 'h264', overwrite: false, ...over });
  return { box, adapter, song, cover, output, outDir: path.join(box.dir, 'out'), args };
}

const noProcessLeft = async (box: Sandbox, ms = 3000) => assert.equal(await waitFor(() => box.alive().length === 0, ms), true, `still alive: ${box.alive().join(', ')}`);

// ---- the launch questions (SPEC 27.6) -------------------------------------------------

test('version: song2vid 1.2.0 is ready, and the tool is asked --version --json', async (t) => {
  const { box, adapter } = setup(t, {});
  const answer = await adapter.version();
  assert.deepEqual(answer, { ok: true, version: 'song2vid 1.2.0' });
  assert.deepEqual(box.starts().map((s) => s.argv), [['--version', '--json']]);
  assert.equal(box.starts()[0]?.['runAsNode'], false, 'ELECTRON_RUN_AS_NODE never reaches the tool');
});

test('version: a tool that refuses --json is asked plain --version, and either form must print the line', async (t) => {
  const { box, adapter } = setup(t, { version: 'version-ok-without-json' });
  assert.deepEqual(await adapter.version(), { ok: true, version: 'song2vid 1.2.0' });
  assert.deepEqual(box.starts().map((s) => s.argv), [['--version', '--json'], ['--version']]);
});

for (const [scenario, code, limits] of [
  ['version-wrong', 'TOOL_INCOMPATIBLE', {}],
  ['version-garbage', 'TOOL_INCOMPATIBLE', {}],
  ['version-silent', 'TOOL_STALLED', { versionMs: 600 }],
] as [string, string, Partial<Limits>][]) {
  test(`version: ${scenario} is ${code}, and no tool is left`, async (t) => {
    const { box, adapter } = setup(t, { version: scenario }, limits);
    const answer = await adapter.version();
    assert.ok(!answer.ok);
    assert.equal(answer.error.code, code);
    await noProcessLeft(box);
  });
}

test('version: a tool that cannot be started is TOOL_NOT_FOUND', async (t) => {
  const { box } = setup(t, {});
  const adapter = createAdapter({ located: { ...box.located, command: path.join(box.dir, 'no-such-program') }, cwd: box.dataDir });
  const answer = await adapter.version();
  assert.ok(!answer.ok);
  assert.equal(answer.error.code, 'TOOL_NOT_FOUND');
});

test('encoders: the answer is read as the contract gives it', async (t) => {
  const { box, adapter } = setup(t, {});
  const out = await adapter.encoders();
  assert.ok(out.status === 'ok');
  assert.deepEqual(out.value, { h264: { available: true, encoder: 'nvenc' }, hevc: { available: true, encoder: 'nvenc' } });
  assert.deepEqual(box.starts().map((s) => s.argv), [['encoders', '--json']]);
});

test('encoders: HEVC unavailable, an Encoder name from a newer tool, and garbage', async (t) => {
  const none = await setup(t, { encoders: 'encoders-no-hevc' }).adapter.encoders();
  assert.ok(none.status === 'ok');
  assert.deepEqual(none.value, { h264: { available: true, encoder: 'software' }, hevc: { available: false, encoder: null } });
  const newer = await setup(t, { encoders: 'encoders-newer-encoder' }).adapter.encoders();
  assert.ok(newer.status === 'ok');
  assert.deepEqual(newer.value.h264, { available: true, encoder: null }, 'available, name unknown: the page can still use the Codec');
  const garbage = await setup(t, { encoders: 'encoders-garbage' }).adapter.encoders();
  assert.ok(garbage.status === 'failed');
  assert.equal(garbage.error.fault, 'TOOL_PROTOCOL');
});

// ---- one file's facts and the preview ---------------------------------------------------

test('check: one song, one image, and the argument lists (no cancel flag: a check never reads stdin)', async (t) => {
  const { box, adapter, song, cover } = setup(t, {});
  const audio = await adapter.checkAudio(song);
  assert.ok(audio.status === 'ok');
  assert.deepEqual(audio.value, { name: 'Song.mp3', durationSeconds: 144 });
  const image = await adapter.checkImage(cover);
  assert.ok(image.status === 'ok');
  assert.equal(image.value.name, 'Cover.png');
  assert.deepEqual([image.value.width, image.value.height], [1600, 1200]);
  assert.equal(image.value.frames.length, 13, 'four shapes at three sizes, and Original');
  assert.deepEqual(image.value.frames[0], { shape: '16:9', resolution: '480p', width: 854, height: 480, placement: 'fit', enlarged: false });
  assert.deepEqual(image.value.frames[12], { shape: 'original', resolution: null, width: 1600, height: 1200, placement: 'fit', enlarged: false });
  assert.deepEqual(box.starts().map((s) => s.argv), [['check', song, '--json'], ['check', cover, '--json']]);
});

test('check: an image the tool calls too small has no size and no placement', async (t) => {
  const { adapter, cover } = setup(t, { check_image: 'check-image-tiny' });
  const image = await adapter.checkImage(cover);
  assert.ok(image.status === 'ok');
  assert.deepEqual(image.value.frames.at(-1), { shape: 'original', resolution: null, width: null, height: null, placement: null, enlarged: false });
  assert.equal(image.value.frames[0]?.enlarged, true);
});

test('check: the tool\'s error code arrives unchanged; an answer of the wrong kind or of no kind is a protocol fault; a silent tool is stopped at its limit', async (t) => {
  const refused = await setup(t, { check_audio: 'check-error', vars: { code: 'audio_unreadable', exit: 3 } }).adapter.checkAudio('/x/Song.mp3');
  assert.ok(refused.status === 'failed');
  assert.deepEqual([refused.error.code, refused.error.fault], ['audio_unreadable', null]);
  const wrong = await setup(t, { check_audio: 'check-wrong-kind' }).adapter.checkAudio('/x/Song.mp3');
  assert.ok(wrong.status === 'failed');
  assert.deepEqual([wrong.error.code, wrong.error.fault], ['export_failed', 'TOOL_PROTOCOL']);
  const text = await setup(t, { check_audio: 'check-garbage' }).adapter.checkAudio('/x/Song.mp3');
  assert.ok(text.status === 'failed');
  assert.equal(text.error.fault, 'TOOL_PROTOCOL');
  const quiet = setup(t, { check_audio: 'check-silent' }, { checkMs: 500 });
  const stopped = await quiet.adapter.checkAudio('/x/Song.mp3');
  assert.ok(stopped.status === 'failed');
  assert.equal(stopped.error.fault, 'TOOL_STALLED');
  await noProcessLeft(quiet.box);
});

test('every path given to the tool is absolute: a relative one is a programming error, never a flag', async (t) => {
  const { adapter } = setup(t, {});
  assert.throws(() => void adapter.checkAudio('-song.mp3'), /absolute/);
  assert.throws(() => void adapter.preview('relative.png', '/x/out.png'), /absolute/);
});

test('preview: the picture is written, the arguments are the contract\'s, and it can be cancelled', async (t) => {
  const { box, adapter, cover, outDir } = setup(t, {});
  const picture = path.join(outDir, 'cover-preview.png');
  const out = await adapter.preview(cover, picture);
  assert.ok(out.status === 'ok');
  assert.deepEqual(out.value, { width: 2048, height: 1536 });
  assert.equal(fs.readFileSync(picture).subarray(1, 4).toString(), 'PNG');
  assert.deepEqual(box.starts()[0]?.argv, ['preview', cover, '--out', picture, '--overwrite', '--json', '--cancel-on-eof']);

  const slow = setup(t, { preview: 'preview-slow' });
  const abort = new AbortController();
  setTimeout(() => abort.abort(), 300);
  const stopped = await slow.adapter.preview(slow.cover, path.join(slow.outDir, 'p.png'), { signal: abort.signal });
  assert.equal(stopped.status, 'cancelled');
  await noProcessLeft(slow.box);
});

test('preview: the tool\'s error code arrives unchanged', async (t) => {
  const { adapter, cover, outDir } = setup(t, { preview: 'preview-error' });
  const out = await adapter.preview(cover, path.join(outDir, 'p.png'));
  assert.ok(out.status === 'failed');
  assert.equal(out.error.code, 'image_unreadable');
});

// ---- the job ---------------------------------------------------------------------------

test('make: the lines arrive in order, the file is published in one step and the arguments are the contract\'s', async (t) => {
  const { box, adapter, args, output, outDir, song, cover } = setup(t, {});
  const lines: Line[] = [];
  const out = await adapter.make(args(), { onLine: (line) => lines.push(line) });
  assert.ok(out.status === 'ok');
  assert.equal(out.killed, false);
  assert.deepEqual(out.value, { name: 'Song.mp4', width: 1920, height: 1080, durationSeconds: 144, bytes: 6153216, codec: 'h264', encoder: 'nvenc', encoderFallback: false });
  assert.equal(lines.at(-1)?.type, 'result');
  assert.deepEqual([...new Set(lines.map((l) => l.type))], ['progress', 'result']);
  assert.deepEqual(lines.filter((l) => l.type === 'progress').map((l) => l['stage']).filter((s, i, all) => all.indexOf(s) === i), ['checking', 'preparing', 'encoding', 'finishing']);
  assert.equal(fs.readFileSync(output, 'utf8'), 'standin output\n');
  assert.deepEqual(temporaryFiles(outDir), []);
  assert.deepEqual(box.starts().map((s) => s.argv), [['make', song, cover, '--out', output, '--shape', '16:9', '--resolution', '1080p', '--codec', 'h264', '--json', '--cancel-on-eof']]);
  assert.equal(box.starts()[0]?.['runAsNode'], false);
});

test('make: Original takes no resolution, a crop is two fractions, --overwrite only when asked', async (t) => {
  const { box, adapter, args, song, cover, output } = setup(t, {});
  await adapter.make(args({ shape: 'original', resolution: null, codec: 'hevc' }));
  await adapter.make(args({ shape: '1:1', crop: { h: 0.25, v: 0.123456 }, overwrite: true }));
  const [original, square] = box.starts().map((s) => s.argv);
  assert.deepEqual(original, ['make', song, cover, '--out', output, '--shape', 'original', '--codec', 'hevc', '--json', '--cancel-on-eof']);
  assert.deepEqual(square, ['make', song, cover, '--out', output, '--shape', '1:1', '--resolution', '1080p', '--crop', '0.25,0.1235', '--codec', 'h264', '--overwrite', '--json', '--cancel-on-eof']);
});

test('make: a fallback to the next Encoder is reported', async (t) => {
  const { adapter, args } = setup(t, { make: 'make-fallback' });
  const out = await adapter.make(args());
  assert.ok(out.status === 'ok');
  assert.deepEqual([out.value.encoder, out.value.encoderFallback], ['software', true]);
});

test('make: unknown keys, line types and stages are ignored', async (t) => {
  const { adapter, args } = setup(t, { make: 'make-unknown-keys' });
  const out = await adapter.make(args());
  assert.equal(out.status, 'ok');
});

test('make: every error code of the contract reaches the shell unchanged with the exit status the table gives, and a code from a newer tool too', async (t) => {
  for (const [code, exit] of Object.entries(EXIT_STATUS)) {
    if (code === 'cancelled') continue; // not an error: its own test
    const { box, adapter, args } = setup(t, { make: 'make-error', vars: { code, exit, message: `message for ${code}` } });
    const out = await adapter.make(args());
    assert.ok(out.status === 'failed', code);
    assert.deepEqual([out.error.code, out.error.fault, out.error.message], [code, null, `message for ${code}`]);
    assert.equal(out.error.details['exitCode'], exit, `${code} exits ${exit}`);
    await noProcessLeft(box);
  }
  const { adapter, args } = setup(t, { make: 'make-error', vars: { code: 'something_new', exit: 5 } });
  const out = await adapter.make(args());
  assert.ok(out.status === 'failed');
  assert.equal(out.error.code, 'something_new');
});

for (const [scenario, code, fault, limits] of [
  ['make-crash', 'export_failed', 'TOOL_CRASHED', {}],
  ['make-silent-end', 'export_failed', 'TOOL_CRASHED', {}],
  ['make-result-exit-1', 'export_failed', 'TOOL_CRASHED', {}],
  ['make-garbage', 'export_failed', 'TOOL_PROTOCOL', {}],
  ['make-line-2mib', 'export_failed', 'TOOL_PROTOCOL', {}],
  ['make-noise-10mb', 'export_failed', 'TOOL_PROTOCOL', {}],
  ['make-noise-10mb-lines', 'export_failed', 'TOOL_PROTOCOL', {}],
  ['make-no-api-version', 'export_failed', 'TOOL_PROTOCOL', {}],
  ['make-other-api-version', 'TOOL_INCOMPATIBLE', 'TOOL_INCOMPATIBLE', {}],
  ['make-two-finals', 'export_failed', 'TOOL_PROTOCOL', {}],
  ['make-line-after-final', 'export_failed', 'TOOL_PROTOCOL', {}],
  ['make-result-missing-keys', 'export_failed', 'TOOL_PROTOCOL', {}],
] as [string, string, string, Partial<Limits>][]) {
  test(`a hostile tool (${scenario}) ends in ${code} (${fault}) and leaves no process`, async (t) => {
    const { box, adapter, args } = setup(t, { make: scenario }, limits);
    const before = process.memoryUsage().rss;
    const out = await adapter.make(args());
    assert.ok(out.status === 'failed');
    assert.deepEqual([out.error.code, out.error.fault], [code, fault]);
    assert.equal(out.error.details['fault'], fault);
    await noProcessLeft(box);
    assert.ok(process.memoryUsage().rss - before < 64 * 1024 * 1024, 'the adapter did not hold the noise');
  });
}

test('a crash\'s details keep the tool\'s stderr and no path of the person\'s', async (t) => {
  const { adapter, args, output } = setup(t, { make: 'make-crash' });
  const out = await adapter.make(args());
  assert.ok(out.status === 'failed');
  const text = JSON.stringify(out.error);
  assert.match(text, /panicked/);
  assert.equal(text.includes(path.dirname(output)), false);
});

test('a tool that cannot be started fails the job as TOOL_NOT_FOUND', async (t) => {
  const { box, args } = setup(t, {});
  const adapter = createAdapter({ located: { ...box.located, command: path.join(box.dir, 'no-such-program') }, cwd: box.dataDir });
  const out = await adapter.make(args());
  assert.ok(out.status === 'failed');
  assert.deepEqual([out.error.code, out.error.fault], ['TOOL_NOT_FOUND', 'TOOL_NOT_FOUND']);
});

test('a job that goes quiet is reported as stalled and recovers, but is never killed by the adapter', async (t) => {
  const { adapter, args } = setup(t, { make: 'make-silence-mid-job' }, { stallMs: 400 });
  const seen: boolean[] = [];
  const out = await adapter.make(args(), { onStall: (s) => seen.push(s) });
  assert.equal(out.status, 'ok');
  assert.ok(seen.includes(true), 'the quiet stretch was reported');
  assert.equal(seen.at(-1), false, 'and its end');
  assert.ok(seen.every((s, i) => i === 0 || s !== seen[i - 1]), `reports alternate: ${seen.join(', ')}`);
});

// ---- cancel --------------------------------------------------------------------------------

test('cancel closes stdin; the tool removes its temporary file and says cancelled within 2 s', async (t) => {
  // A grace period longer than the 2 s the SPEC gives the tool, so a busy machine cannot turn an honoured cancel into a kill.
  const { box, adapter, args, output, outDir } = setup(t, { make: 'make-slow' }, { graceMs: 2500 });
  const abort = new AbortController();
  let at = 0;
  const out = await adapter.make(args(), {
    signal: abort.signal,
    onLine: (line) => {
      if (line.type === 'progress' && Number(line['percent']) >= 10 && !at) {
        at = Date.now();
        abort.abort();
      }
    },
  });
  assert.equal(out.status, 'cancelled');
  assert.equal(out.killed, false, 'the tool stopped by itself');
  assert.ok(Date.now() - at < 2000, `took ${Date.now() - at} ms`);
  assert.equal(fs.existsSync(output), false, 'no output');
  assert.deepEqual(temporaryFiles(outDir), [], 'no temporary file');
  assert.deepEqual(box.events().map((e) => e.event), ['cancel']);
  await noProcessLeft(box, 2000);
});

test('a tool that ignores the cancel is killed 3 s after stdin closes (the default grace period)', async (t) => {
  const { box, adapter, args, outDir } = setup(t, { make: 'make-cancel-ignored' }, { graceMs: 3000 });
  const abort = new AbortController();
  let at = 0;
  const out = await adapter.make(args(), {
    signal: abort.signal,
    onLine: () => {
      if (!at) {
        at = Date.now();
        abort.abort();
      }
    },
  });
  const took = Date.now() - at;
  assert.equal(out.status, 'cancelled');
  assert.equal(out.killed, true);
  assert.ok(took >= 2900 && took < 6000, `killed after ${took} ms`);
  assert.deepEqual(box.events().map((e) => e.event), ['stdin-closed'], 'stdin was closed at once');
  await noProcessLeft(box, 2000);
  assert.equal(temporaryFiles(outDir).length, 1, 'a killed tool leaves its temporary file: the service removes it');
});

test('aborting before the tool has started cancels without running a job to its end', async (t) => {
  const { box, adapter, args } = setup(t, { make: 'make-slow' });
  const abort = new AbortController();
  abort.abort();
  const out = await adapter.make(args(), { signal: abort.signal });
  assert.equal(out.status, 'cancelled');
  await noProcessLeft(box);
});
