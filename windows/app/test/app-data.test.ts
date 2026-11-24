// What the app saves between runs, the two links and the notices text (electron/app-data.ts), and the
// development-only answers for the dialogs (electron/tool/qa-picks.ts).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import type { TestContext } from 'node:test';
import { DEFAULT_PREFERENCES, LINKS, linkFor, readNotices, readPreferences, writePreferences } from '../electron/app-data.ts';
import { answerOpen, answerSave, readQaPicks } from '../electron/tool/qa-picks.ts';

const folder = (t: TestContext): string => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 's2v-appdata-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
};

test('the Codec is H.264 until a person chooses HEVC, and then it is remembered', (t) => {
  const dir = folder(t);
  assert.deepEqual(readPreferences(dir), { codec: 'h264' });
  assert.deepEqual(writePreferences(dir, { codec: 'hevc' }), { codec: 'hevc' });
  assert.deepEqual(readPreferences(dir), { codec: 'hevc' });
  assert.deepEqual(writePreferences(dir, { codec: 'h264' }), { codec: 'h264' });
  assert.deepEqual(readPreferences(dir), { codec: 'h264' });
  assert.deepEqual(fs.readdirSync(dir), ['preferences.json'], 'no temporary file is left');
});

test('the page is not trusted with the shape of an update', (t) => {
  const dir = folder(t);
  writePreferences(dir, { codec: 'hevc' });
  for (const bad of [{ codec: 'av1' }, { codec: 5 }, { codec: null }, {}, null, undefined, 'hevc', [], { other: 'x' }, { codec: { toString: 'h264' } }]) {
    assert.deepEqual(writePreferences(dir, bad), { codec: 'hevc' }, JSON.stringify(bad));
  }
  assert.deepEqual(readPreferences(dir), { codec: 'hevc' });
});

test('a damaged or foreign preferences file gives the defaults', (t) => {
  const dir = folder(t);
  for (const text of ['{not json', '', 'null', '[]', '{"codec":"vp9"}', '{"codec":7}']) {
    fs.writeFileSync(path.join(dir, 'preferences.json'), text);
    assert.deepEqual(readPreferences(dir), DEFAULT_PREFERENCES, text);
  }
});

test('a data folder that cannot be written does not stop the choice from applying for this run', (t) => {
  const dir = folder(t);
  const blocked = path.join(dir, 'a-file');
  fs.writeFileSync(blocked, 'x');
  assert.deepEqual(writePreferences(path.join(blocked, 'inside'), { codec: 'hevc' }), { codec: 'hevc' });
});

test('the page names one of two places and never an address', () => {
  assert.equal(linkFor('repository'), LINKS.repository);
  assert.equal(linkFor('download-page'), LINKS['download-page']);
  for (const bad of ['https://example.com/', '', null, undefined, 3, {}, '__proto__', 'toString']) assert.equal(linkFor(bad), null, String(bad));
  for (const address of Object.values(LINKS)) assert.match(address, /^https:\/\/[a-z0-9.-]+\//);
});

test('the notices are read from where the packaged app and a development run keep them', (t) => {
  const dir = folder(t);
  fs.mkdirSync(path.join(dir, 'res'));
  fs.mkdirSync(path.join(dir, 'proj', 'third-party'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'res', 'THIRD-PARTY-NOTICES.txt'), 'packaged text');
  fs.writeFileSync(path.join(dir, 'proj', 'third-party', 'THIRD-PARTY-NOTICES.txt'), 'development text');
  assert.equal(readNotices({ packaged: true, resourcesPath: path.join(dir, 'res'), projectDir: path.join(dir, 'proj') }), 'packaged text');
  assert.equal(readNotices({ packaged: false, resourcesPath: path.join(dir, 'res'), projectDir: path.join(dir, 'proj') }), 'development text');
  assert.match(readNotices({ packaged: true, resourcesPath: path.join(dir, 'nowhere'), projectDir: dir }), /could not be read/);
});

test('the dialogs\' development answers are read only from an unpackaged launch, and only a real file answers', (t) => {
  const dir = folder(t);
  const song = path.join(dir, 'Song.mp3');
  fs.writeFileSync(song, 'x');
  const argv = ['--no-activate', `--qa-pick-audio=${song}`, `--qa-pick-image=${path.join(dir, 'missing.png')}`, `--qa-pick-save=${path.join(dir, 'Out.mp4')}`];
  assert.equal(readQaPicks(argv, true), null, 'a packaged app never looks');
  assert.equal(readQaPicks(['--no-activate'], false), null);
  const picks = readQaPicks(argv, false);
  assert.ok(picks);
  assert.equal(answerOpen(picks, 'audio'), song);
  assert.equal(answerOpen(picks, 'image'), null, 'a file that does not exist is a closed dialog');
  assert.equal(answerSave(picks), path.join(dir, 'Out.mp4'));
  assert.equal(answerOpen(null, 'audio'), null);
  assert.equal(answerSave(null), null);
});
