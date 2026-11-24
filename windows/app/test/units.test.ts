// The adapter's plain pieces: the line reader, the contract's arguments and readers, the locator,
// the report cache, the job records, the file ids, a drop's judgement, a make request and the
// progress model. No process is started here.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import type { TestContext } from 'node:test';
import { createLineReader } from '@uppercut-labs/electron-child-process-runner';
import { checkArgs, encodersArgs, makeArgs, previewArgs, readAudio, readEncoders, readError, readImage, readMade, readProgress, readVersion, STAGING_NAME, versionArgs, VERSION_LINE } from '../electron/tool/contract.ts';
import type { Line } from '../electron/tool/contract.ts';
import { createFileRegistry, judgeDrop, kindOfName } from '../electron/tool/files.ts';
import { createJobRecords } from '../electron/tool/jobs.ts';
import { folderName, locateTool } from '../electron/tool/locate.ts';
import type { Located } from '../electron/tool/locate.ts';
import { createProgressModel, HOLD } from '../electron/tool/progress.ts';
import { readRequest } from '../electron/tool/service.ts';
import { createReportCache, toolStatus } from '../electron/tool/status.ts';

const tmp = (t: TestContext) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'song2vid-unit-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
};
const line = (body: Record<string, unknown>): Line => ({ api_version: '1', type: 'result', ...body });

test('line reader: splits, tolerates CRLF, caps a long line and the total, and keeps draining', () => {
  const lines: string[] = [];
  const over: string[] = [];
  const reader = createLineReader({ maxLineBytes: 16, maxTotalBytes: 64, onLine: (l) => lines.push(l), onOverflow: (k) => over.push(k) });
  reader.push(Buffer.from('one\r\ntw'));
  reader.push(Buffer.from('o\n' + 'x'.repeat(40) + '\nthree\n'));
  assert.deepEqual(lines, ['one', 'two', 'three']);
  assert.deepEqual(over, ['line']);
  reader.push(Buffer.alloc(100, 0x41));
  assert.deepEqual(over, ['line', 'total']);
  reader.push(Buffer.from('four\n'));
  assert.deepEqual(lines, ['one', 'two', 'three'], 'nothing after the total cap');
});

test('arguments: absolute paths, the job flags, and the options the contract names', () => {
  const base = { audio: '/a/Song.mp3', image: '/a/Cover.png', output: '/a/Song.mp4', codec: 'h264' as const, overwrite: false };
  assert.deepEqual(makeArgs({ ...base, shape: '4:3', resolution: '2160p', crop: { h: 0, v: 1 } }), ['make', '/a/Song.mp3', '/a/Cover.png', '--out', '/a/Song.mp4', '--shape', '4:3', '--resolution', '2160p', '--crop', '0,1', '--codec', 'h264', '--json', '--cancel-on-eof']);
  assert.deepEqual(checkArgs(['/a/Song.mp3']), ['check', '/a/Song.mp3', '--json']);
  assert.deepEqual(checkArgs(['/a/Song.mp3', '/a/Cover.png']), ['check', '/a/Song.mp3', '/a/Cover.png', '--json']);
  assert.deepEqual(previewArgs('/a/Cover.png', '/a/p.png'), ['preview', '/a/Cover.png', '--out', '/a/p.png', '--overwrite', '--json', '--cancel-on-eof']);
  assert.deepEqual(encodersArgs(), ['encoders', '--json']);
  assert.deepEqual([versionArgs(true), versionArgs(false)], [['--version', '--json'], ['--version']]);
  assert.throws(() => makeArgs({ ...base, audio: '--help', shape: '16:9', resolution: '1080p', crop: null }), /absolute/);
  assert.throws(() => makeArgs({ ...base, output: 'Song.mp4', shape: '16:9', resolution: '1080p', crop: null }), /absolute/);
});

test('readers: the version line is exact; a result lacking a key is null, never a guess', () => {
  assert.equal(readVersion('song2vid 1.2.0\n'), VERSION_LINE);
  assert.equal(readVersion('song2vid 1.2.0\r\n'), VERSION_LINE);
  assert.equal(readVersion('song2vid 1.1.0\n'), 'song2vid 1.1.0');
  for (const bad of ['', 'song2vid\n', 'song2vid 1.2.0 extra\n', '{"type":"result"}\n', 'song2vid 1.2.0\nmore\n']) assert.equal(readVersion(bad), null, JSON.stringify(bad));
  assert.deepEqual(readAudio(line({ audio: { name: 'a.mp3', duration_seconds: 3.5, sample_rate: 44100, channels: 2 } })), { name: 'a.mp3', durationSeconds: 3.5 });
  assert.equal(readAudio(line({ audio: { name: 'a.mp3' } })), null);
  assert.equal(readAudio(line({ image: {} })), null);
  assert.equal(readImage(line({ image: { name: 'i.png', width: 4, height: 4 }, frames: [{ shape: 'bogus', resolution: null, width: null, height: null, placement: null, enlarged: null }] })), null);
  assert.equal(readImage(line({ image: { name: 'i.png', width: 4, height: 4 } })), null, 'no table');
  assert.deepEqual(readEncoders(line({ codecs: { h264: { available: true, encoder: 'apple' }, hevc: { available: false, encoder: null } } })), { h264: { available: true, encoder: 'apple' }, hevc: { available: false, encoder: null } });
  assert.equal(readEncoders(line({ codecs: { h264: { available: true, encoder: 'apple' } } })), null);
  assert.equal(readMade(line({ output: { name: 'a.mp4' } })), null);
  assert.deepEqual(readError({ api_version: '1', type: 'error' }), { code: 'UNKNOWN', message: '' });
  assert.deepEqual(readError({ api_version: '1', type: 'error', error: { code: 'disk_full', message: 'x' } }), { code: 'disk_full', message: 'x' });
});

test('readers: a progress line keeps what it knows and ignores the rest', () => {
  assert.deepEqual(readProgress(line({ type: 'progress', stage: 'encoding', percent: 52, elapsed_seconds: 4.1, remaining_seconds: 3.8, encoder: 'nvenc', extra: 1 })), { stage: 'encoding', percent: 52, elapsedSeconds: 4.1, remainingSeconds: 3.8, encoder: 'nvenc' });
  assert.deepEqual(readProgress(line({ type: 'progress', stage: 'warming-up', percent: null })), { stage: null, percent: null, elapsedSeconds: null, remainingSeconds: null, encoder: null });
});

test('locator: one folder name, packaged never searches PATH, a missing tool is TOOL_NOT_FOUND', (t) => {
  const dir = tmp(t);
  const platform = 'linux';
  const bin = path.join(dir, 'resources', 'bin', folderName(platform, 'x64'));
  fs.mkdirSync(bin, { recursive: true });
  fs.writeFileSync(path.join(bin, 'song2vid'), '#!/bin/sh\n', { mode: 0o755 });
  const found = locateTool({ packaged: true, resourcesPath: path.join(dir, 'resources'), platform, arch: 'x64', toolName: 'song2vid', helpers: ['ffmpeg'], env: { PATH: process.env['PATH'] } });
  if (process.platform !== 'win32') {
    assert.ok(found.ok);
    assert.equal(found.source, 'packaged');
    assert.deepEqual(found.helpers['ffmpeg'], { file: null, source: null }, 'a packaged app never looks on PATH');
  }
  const missing = locateTool({ packaged: true, resourcesPath: path.join(dir, 'nowhere'), platform, arch: 'x64', toolName: 'song2vid' });
  assert.ok(!missing.ok);
  assert.equal(missing.code, 'TOOL_NOT_FOUND');
  const override = locateTool({ packaged: true, resourcesPath: path.join(dir, 'nowhere'), toolName: 'song2vid', override: { script: import.meta.filename, node: process.execPath } });
  assert.equal(override.ok, false, 'the stand-in override is never honoured in a packaged app');
});

test('status: answers map to ready or damaged, and the cache is keyed by the binaries', (t) => {
  const dir = tmp(t);
  assert.deepEqual(toolStatus({ ok: true, version: VERSION_LINE }), { state: 'ready', code: null, details: VERSION_LINE });
  const damaged = toolStatus({ ok: false, error: { code: 'TOOL_INCOMPATIBLE', message: 'm', fault: 'TOOL_INCOMPATIBLE', details: {} } });
  assert.equal(damaged.state, 'damaged');
  assert.equal(damaged.code, 'TOOL_INCOMPATIBLE');
  const binary = path.join(dir, 'song2vid.bin');
  fs.writeFileSync(binary, 'a');
  const located: Located = { ok: true, command: binary, prefixArgs: [], source: 'development', binary, helpers: {} };
  const cache = createReportCache(dir);
  const report = { version: VERSION_LINE, encoders: { h264: { available: true, encoder: 'nvenc' as const }, hevc: { available: false, encoder: null } } };
  cache.write(located, report);
  assert.deepEqual(cache.read(located), report);
  fs.writeFileSync(binary, 'a changed tool');
  assert.equal(cache.read(located), null, 'a changed binary invalidates the answer');
  cache.write(located, report);
  cache.write(located, null);
  assert.equal(cache.read(located), null, 'a tool that failed its check is forgotten');
});

test('job records: only a regular file named .song2vid-<32 hex>.tmp directly in the recorded folder is removed', (t) => {
  const dir = tmp(t);
  const out = path.join(dir, 'out');
  const other = path.join(dir, 'other');
  fs.mkdirSync(out);
  fs.mkdirSync(other);
  const hex = '0123456789abcdef0123456789abcdef';
  const leftover = `.song2vid-${hex}.tmp`;
  const keep = [
    `.song2vid-${hex.slice(1)}.tmp`, // 31 hex
    `.song2vid-${hex}0.tmp`, // 33 hex
    `.song2vid-${hex}.tmp.bak`,
    `song2vid-${hex}.tmp`, // no leading dot
    `.example-${hex}.tmp`, // the starter's name
    `.song2vid-${hex.replace('0', 'g')}.tmp`, // not hex
    'Song.mp4',
  ];
  fs.writeFileSync(path.join(out, leftover), 'x');
  for (const name of keep) fs.writeFileSync(path.join(out, name), 'x');
  fs.mkdirSync(path.join(out, `.song2vid-${hex.replace(/0/g, '1')}.tmp`)); // a folder of that name is not removed
  fs.mkdirSync(path.join(out, 'sub'));
  fs.writeFileSync(path.join(out, 'sub', leftover), 'x'); // not directly in the folder
  fs.writeFileSync(path.join(other, leftover), 'x'); // another folder
  const records = createJobRecords(path.join(dir, 'jobs'), STAGING_NAME);
  const startedAt = new Date().toISOString();
  records.write({ jobId: 'j_a', folder: out, startedAt });
  assert.deepEqual(records.reconcile(), { records: 1, removed: 1 });
  assert.deepEqual(fs.readdirSync(out).sort(), [...keep, `.song2vid-${hex.replace(/0/g, '1')}.tmp`, 'sub'].sort());
  assert.equal(fs.existsSync(path.join(out, 'sub', leftover)), true);
  assert.equal(fs.existsSync(path.join(other, leftover)), true);
  assert.deepEqual(fs.readdirSync(path.join(dir, 'jobs')), [], 'the record goes with it');
});

test('job records: an odd record names nothing to remove; the current job\'s record stays; a kept name stays', (t) => {
  const dir = tmp(t);
  const out = path.join(dir, 'out');
  fs.mkdirSync(out);
  const mine = `.song2vid-${'a'.repeat(32)}.tmp`;
  const before = `.song2vid-${'b'.repeat(32)}.tmp`;
  fs.writeFileSync(path.join(out, mine), 'x');
  fs.writeFileSync(path.join(out, before), 'x');
  const records = createJobRecords(path.join(dir, 'jobs'), STAGING_NAME);
  const startedAt = new Date().toISOString();
  fs.mkdirSync(path.join(dir, 'jobs'));
  fs.writeFileSync(path.join(dir, 'jobs', 'j_bad.json'), '{not json');
  fs.writeFileSync(path.join(dir, 'jobs', 'j_rel.json'), JSON.stringify({ jobId: 'j_rel', folder: 'out', startedAt }));
  fs.writeFileSync(path.join(dir, 'jobs', 'j_num.json'), JSON.stringify({ jobId: 'j_num', folder: 7, startedAt }));
  records.write({ jobId: 'j_now', folder: out, startedAt });
  assert.deepEqual(records.reconcile('j_now'), { records: 3, removed: 0 });
  assert.deepEqual(fs.readdirSync(path.join(dir, 'jobs')), ['j_now.json']);
  assert.equal(records.removeLeftovers(out, new Set([before])), 1, 'only what is new in the folder');
  assert.deepEqual(fs.readdirSync(out), [before]);
  assert.equal(records.removeLeftovers(path.join(dir, 'missing')), 0);
});

test('files: ids are opaque, belong to one kind, and can be released', () => {
  const registry = createFileRegistry();
  const song = registry.add('audio', '/a/Song.mp3');
  const cover = registry.add('image', '/a/Cover.png');
  assert.match(song, /^f_[0-9a-f]{18}$/);
  assert.equal(song.includes('Song'), false);
  assert.equal(registry.get(song, 'audio'), '/a/Song.mp3');
  assert.equal(registry.get(song, 'image'), null, 'a song id is not an image id');
  assert.equal(registry.get('/a/Song.mp3', 'audio'), null, 'a path is not an id');
  assert.equal(registry.get(42, 'audio'), null);
  assert.deepEqual(registry.release([song, 'f_unknown', 7]), [song]);
  assert.equal(registry.get(song, 'audio'), null);
  assert.equal(registry.get(cover, 'image'), '/a/Cover.png');
  assert.deepEqual(registry.release('not a list'), []);
});

test('drop: sorted by name alone, in the order the Mac app judges (SPEC 4a)', (t) => {
  const dir = tmp(t);
  const folder = path.join(dir, 'Folder.mp3'); // a folder, whatever its name says
  fs.mkdirSync(folder);
  const p = (name: string) => path.join(dir, name);
  assert.equal(kindOfName('X.MP3'), 'audio');
  assert.equal(kindOfName('x.HEIC'), 'image');
  assert.equal(kindOfName('x.txt'), null);
  assert.deepEqual(judgeDrop([p('a.mp3')]), { ok: true, audio: p('a.mp3'), image: null });
  assert.deepEqual(judgeDrop([p('a.jpg'), p('b.flac')]), { ok: true, audio: p('b.flac'), image: p('a.jpg') });
  assert.deepEqual(judgeDrop([]), { ok: false, reason: 'unsupported' });
  assert.deepEqual(judgeDrop([p('a.mp3'), p('b.wav')]), { ok: false, reason: 'more-audio' });
  assert.deepEqual(judgeDrop([p('a.png'), p('b.gif')]), { ok: false, reason: 'more-images' });
  assert.deepEqual(judgeDrop([p('a.mp3'), p('b.png'), p('c.png')]), { ok: false, reason: 'too-many' });
  assert.deepEqual(judgeDrop([folder]), { ok: false, reason: 'folder' });
  assert.deepEqual(judgeDrop([p('a.mp3'), p('b.png'), folder]), { ok: false, reason: 'folder' }, 'a folder before the count');
  assert.deepEqual(judgeDrop([p('a.mp3'), p('b.txt')]), { ok: false, reason: 'unsupported' });
  assert.deepEqual(judgeDrop(['', p('a.mp3')]), { ok: false, reason: 'unsupported' }, 'a dropped thing with no place on disk');
  assert.deepEqual(judgeDrop('a.mp3'), { ok: false, reason: 'unsupported' });
});

test('make request: read field by field; anything off is refused', () => {
  const ok = { audioId: 'f_a', imageId: 'f_b', shape: '16:9', resolution: '1080p', crop: null, codec: 'h264', destination: 'ask' };
  assert.deepEqual(readRequest(ok), ok);
  assert.deepEqual(readRequest({ ...ok, shape: '1:1', crop: { h: 0, v: 1 } })?.crop, { h: 0, v: 1 });
  assert.deepEqual(readRequest({ ...ok, shape: 'original', resolution: null, codec: 'hevc', destination: 'same' })?.resolution, null);
  assert.deepEqual(readRequest({ ...ok, extra: '--overwrite' }), ok, 'a field the page invents is dropped');
  for (const bad of [
    null,
    'make',
    { ...ok, shape: '3:2' },
    { ...ok, resolution: '720p' },
    { ...ok, resolution: null },
    { ...ok, shape: 'original' },
    { ...ok, codec: 'av1' },
    { ...ok, destination: 'C:\\Videos\\x.mp4' },
    { ...ok, crop: { h: 0.5, v: 0.5 } },
    { ...ok, shape: '4:3', crop: { h: 1.5, v: 0.5 } },
    { ...ok, shape: '4:3', crop: { h: 'x', v: 0.5 } },
    { ...ok, audioId: 7 },
  ]) assert.equal(readRequest(bad), null, JSON.stringify(bad));
});

test('progress: percent is null until known, never goes back and never reaches 100; the Encoder and stage stick', () => {
  const model = createProgressModel();
  assert.deepEqual(model.snapshot(), { stage: 'checking', percent: null, elapsedSeconds: 0, remainingSeconds: null, encoder: null, stalled: false });
  assert.equal(model.onLine(line({ type: 'result' })), false, 'only a progress line moves the snapshot');
  model.onLine(line({ type: 'progress', stage: 'preparing', percent: null, elapsed_seconds: 0.1 }));
  assert.deepEqual([model.snapshot().stage, model.snapshot().percent], ['preparing', null]);
  model.onLine(line({ type: 'progress', stage: 'encoding', percent: 50, elapsed_seconds: 0.5, encoder: 'nvenc' }));
  model.onLine(line({ type: 'progress', stage: 'encoding', percent: 30, elapsed_seconds: 0.6 }));
  assert.deepEqual([model.snapshot().percent, model.snapshot().encoder], [50, 'nvenc']);
  model.onLine(line({ type: 'progress', stage: 'warming-up', percent: 100, elapsed_seconds: 0.7 }));
  assert.deepEqual([model.snapshot().percent, model.snapshot().stage], [HOLD, 'encoding']);
});

test('progress: time left waits for 1 s of encoding and 5%, changes at most once a second and never jumps up', () => {
  const model = createProgressModel();
  const seen: [number, number | null][] = [];
  for (let t = 0; t <= 8000; t += 250) {
    const percent = 1 + t / 100;
    model.onLine(line({ type: 'progress', stage: 'encoding', percent, elapsed_seconds: t / 1000, remaining_seconds: Math.max(0.5, 10 - t / 1000) }));
    seen.push([t, model.snapshot().remainingSeconds]);
  }
  assert.ok(seen.filter(([t, r]) => t < 1000 && r !== null).length === 0, 'nothing in the first second of encoding');
  assert.ok(seen.some(([, r]) => r !== null), 'shown once trustworthy');
  const changes = seen.filter(([, r], i) => i > 0 && r !== seen[i - 1]?.[1] && r !== null).map(([t]) => t);
  for (let i = 1; i < changes.length; i++) assert.ok((changes[i] ?? 0) - (changes[i - 1] ?? 0) >= 1000, `changed twice within a second: ${changes.join(', ')}`);
  const stalled = createProgressModel();
  stalled.onLine(line({ type: 'progress', stage: 'encoding', percent: 10, elapsed_seconds: 0, remaining_seconds: 9 }));
  stalled.onLine(line({ type: 'progress', stage: 'encoding', percent: 20, elapsed_seconds: 2, remaining_seconds: 8 }));
  assert.equal(stalled.snapshot().remainingSeconds, 8);
  stalled.setStalled(true);
  assert.deepEqual([stalled.snapshot().remainingSeconds, stalled.snapshot().stalled], [null, true], 'a quiet tool has no time left');
});

test('progress: with no elapsed count from the tool, the shell\'s own clock moves the update', () => {
  let clock = 1_000_000;
  const model = createProgressModel({ now: () => clock });
  clock += 2500;
  model.onLine(line({ type: 'progress', stage: 'preparing', percent: null }));
  assert.equal(model.snapshot().elapsedSeconds, 2.5);
});
