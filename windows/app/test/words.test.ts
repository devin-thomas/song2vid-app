// The page's own words and small rules (src/state/words.ts, status.ts, drops.ts): the error table of
// SPEC 27.5 sentence by sentence, the drop messages, the Encoder names, the time left and progress rules
// of premium bar rules 65 and 66, and the status bar for each state.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { AudioInfo, ImageInfo } from '../src/bridge.ts';
import { decideDrop, idsToRelease } from '../src/state/drops.ts';
import type { AppState } from '../src/state/model.ts';
import { startingCodec } from '../src/state/model.ts';
import { statusOf, statusSentence } from '../src/state/status.ts';
import { ACTION_LABELS, BLOCKED, ENCODER_NAMES, FAILURES, clock, doneFacts, dragLooksValid, encoderName, enlargeNote, failureFor, failureLines, hevcAvailable, mayShowTimeLeft, rejectionMessage, sentenceOf, steadyPercent, steadyRemaining, timeLeftWords } from '../src/state/words.ts';

// SPEC 27.5, as written there.
const TABLE: [code: string, sentence: string, filled: string][] = [
  ['audio_not_found', 'The song file is no longer where it was.', 'Choose Audio…'],
  ['image_not_found', 'The image file is no longer where it was.', 'Choose Image…'],
  ['audio_unreadable', "Song2Vid can't read this audio file.", 'Choose Audio…'],
  ['image_unreadable', "Song2Vid can't read this image file.", 'Choose Image…'],
  ['image_too_small', 'This image is too small. Each side needs at least 16 pixels.', 'Choose Image…'],
  ['codec_unavailable', "This computer can't make HEVC videos.", 'Use H.264'],
  ['output_not_writable', "Couldn't save to that folder. Nothing was saved.", 'Choose Another Folder…'],
  ['disk_full', 'Not enough disk space. Nothing was saved.', 'Choose Another Folder…'],
  ['output_in_use', 'Another app is using that file. Close it, then try again.', 'Try Again'],
  ['output_exists', "A file with that name appeared while the video was being made. It was kept, and the new video wasn't saved.", 'Save As…'],
  ['export_failed', "The video couldn't be made. Your files are unchanged.", 'Try Again'],
];

test('the error table says SPEC 27.5\'s sentence and offers its filled button, for every code', () => {
  for (const [code, sentence, filled] of TABLE) {
    const failure = failureFor(code);
    assert.equal(sentenceOf(failure), sentence, code);
    assert.equal(ACTION_LABELS[failure.action], filled, code);
  }
  assert.deepEqual(Object.keys(FAILURES).sort(), TABLE.map(([code]) => code).sort(), 'one row for each code of the table, and no other');
});

test('a code the page does not know gets the generic sentence and Try Again', () => {
  for (const code of ['something_new', 'TOOL_PROTOCOL', '', 'constructor']) {
    const failure = failureFor(code);
    assert.equal(sentenceOf(failure), "The video couldn't be made. Your files are unchanged.", code);
    assert.equal(ACTION_LABELS[failure.action], 'Try Again');
  }
});

test('a failure that happens again says so and its filled button becomes Copy Details (rule 69)', () => {
  for (const [code, sentence] of TABLE) {
    const again = failureLines(code, true);
    assert.equal(ACTION_LABELS[again.action], 'Copy Details', code);
    assert.ok(sentenceOf(again).includes('It failed again.'), code);
    assert.ok(sentenceOf(again).startsWith(sentence.split('. ')[0] ?? ''), code);
  }
  assert.equal(ACTION_LABELS[failureLines('disk_full', false).action], 'Choose Another Folder…');
});

test('no filled button ever reads Details, Show details or OK (rule 69)', () => {
  for (const label of Object.values(ACTION_LABELS)) assert.doesNotMatch(label, /^(show |hide )?details$|^ok$/i);
});

test('the blocking state says SPEC 27.5\'s sentence and offers the download page', () => {
  assert.equal(`${BLOCKED.first} ${BLOCKED.second}`, 'Song2Vid is missing part of itself. Reinstall it to keep making videos.');
  assert.equal(ACTION_LABELS[BLOCKED.action], 'Open Download Page');
});

test('the Encoder names are the SPEC 24.2 words, and a name from a newer tool is never shown raw', () => {
  assert.deepEqual(ENCODER_NAMES, { nvenc: 'NVIDIA encoder', media_foundation: 'graphics hardware encoder', software: 'software encoder', apple: 'Apple encoder' });
  assert.equal(encoderName('nvenc'), 'NVIDIA encoder');
  assert.equal(encoderName('quantum'), null);
  assert.equal(encoderName(null), null);
  assert.equal(doneFacts({ codec: 'h264', encoder: 'nvenc', durationSeconds: 6 }), 'H.264 · NVIDIA encoder · 0:06');
  assert.equal(doneFacts({ codec: 'hevc', encoder: 'media_foundation', durationSeconds: 144 }), 'HEVC · graphics hardware encoder · 2:24');
});

test('a length reads m:ss', () => {
  assert.deepEqual([0, 6, 59.6, 144, 3600].map(clock), ['0:00', '0:06', '1:00', '2:24', '60:00']);
});

test('the drop messages are the Mac app\'s words, one for each reason', () => {
  assert.equal(rejectionMessage('folder'), "Song2Vid can't use folders. Drop a song or an image.");
  assert.equal(rejectionMessage('too-many'), 'Drop no more than two files: one song, one image, or one of each.');
  assert.equal(rejectionMessage('unsupported'), "Song2Vid can't read this kind of file. Drop a song or an image.");
  assert.equal(rejectionMessage('more-audio'), 'Drop one song, one image, or one of each.');
  assert.equal(rejectionMessage('more-images'), 'Drop one song, one image, or one of each.');
  assert.match(rejectionMessage('unreadable'), /can't read/);
});

test('only a drag that could be used is highlighted (SPEC 4a)', () => {
  const song = { kind: 'file', type: 'audio/mpeg' };
  const picture = { kind: 'file', type: 'image/png' };
  assert.equal(dragLooksValid([song]), true);
  assert.equal(dragLooksValid([picture]), true);
  assert.equal(dragLooksValid([song, picture]), true);
  assert.equal(dragLooksValid([{ kind: 'file', type: '' }]), true, 'a type the browser does not know (HEIC) is judged by the shell');
  assert.equal(dragLooksValid([]), false);
  assert.equal(dragLooksValid([song, song]), false);
  assert.equal(dragLooksValid([picture, picture]), false);
  assert.equal(dragLooksValid([song, picture, picture]), false);
  assert.equal(dragLooksValid([{ kind: 'file', type: 'text/plain' }]), false);
  assert.equal(dragLooksValid([{ kind: 'string', type: 'text/plain' }]), false);
});

test('time left is worded in coarse units and appears only once it can be trusted (rule 66)', () => {
  assert.equal(timeLeftWords(3), 'a few seconds left');
  assert.equal(timeLeftWords(22), 'about 20 seconds left');
  assert.equal(timeLeftWords(40), 'about 40 seconds left');
  assert.equal(timeLeftWords(60), 'about a minute left');
  assert.equal(timeLeftWords(300), 'about 5 minutes left');
  const base = { stage: 'encoding' as const, percent: 12, elapsedSeconds: 1.2, remainingSeconds: 9 };
  assert.equal(mayShowTimeLeft(base), true);
  assert.equal(mayShowTimeLeft({ ...base, elapsedSeconds: 0.9 }), false, 'before encoding has run 1 s');
  assert.equal(mayShowTimeLeft({ ...base, percent: 5 }), false, 'not past 5%');
  assert.equal(mayShowTimeLeft({ ...base, percent: null }), false);
  assert.equal(mayShowTimeLeft({ ...base, remainingSeconds: null }), false);
  assert.equal(mayShowTimeLeft({ ...base, stage: 'preparing' }), false, 'only while encoding');
});

test('the time left changes at most once a second and never goes up by more than a second (rule 66)', () => {
  let shown = steadyRemaining(null, 30, 0);
  assert.equal(shown.seconds, 30);
  shown = steadyRemaining(shown, 25, 400);
  assert.equal(shown.seconds, 30, 'inside a second: unchanged');
  shown = steadyRemaining(shown, 25, 1100);
  assert.equal(shown.seconds, 25);
  shown = steadyRemaining(shown, 60, 2200);
  assert.equal(shown.seconds, 26, 'up by one second at most');
  shown = steadyRemaining(shown, 60, 3300);
  assert.equal(shown.seconds, 27);
});

test('progress never goes back and never reads 100% before the outcome (rule 65)', () => {
  assert.equal(steadyPercent(null, null), null);
  assert.equal(steadyPercent(null, 12), 12);
  assert.equal(steadyPercent(40, 30), 40);
  assert.equal(steadyPercent(40, null), 40);
  assert.equal(steadyPercent(40, 100), 99);
  assert.equal(steadyPercent(null, -5), 0);
  assert.equal(steadyPercent(99, 100), 99);
});

test('the Codec starts as the remembered one unless this computer cannot make it (SPEC 23)', () => {
  const yes = { h264: { available: true, encoder: 'nvenc' as const }, hevc: { available: true, encoder: 'nvenc' as const } };
  const no = { h264: { available: true, encoder: 'software' as const }, hevc: { available: false, encoder: null } };
  assert.equal(startingCodec('hevc', yes), 'hevc');
  assert.equal(startingCodec('hevc', no), 'h264');
  assert.equal(startingCodec('hevc', null), 'hevc', 'no report yet: the choice stands until one says otherwise');
  assert.equal(startingCodec('h264', no), 'h264');
  assert.equal(hevcAvailable(null), true);
  assert.equal(hevcAvailable(no), false);
});

test('the enlarge note is the Mac app\'s sentence', () => {
  assert.equal(enlargeNote(1920, 1080), 'This image is smaller than 1920×1080 and will be enlarged, so it may look soft.');
});

// ---- the status bar ---------------------------------------------------------------------

const audio: AudioInfo = { id: 'f_a', name: 'Song.mp3', durationSeconds: 144 };
const image: ImageInfo = { id: 'f_i', name: 'Cover.png', width: 1600, height: 900, frames: [] };
const base = (over: Partial<AppState> = {}): AppState => ({
  tool: { state: 'ready', code: null, details: null },
  encoders: null,
  audio: null,
  image: null,
  shape: '16:9',
  tier: '1080p',
  codec: 'h264',
  savedCodec: 'h264',
  crop: { h: 0.5, v: 0.5 },
  preview: null,
  job: { phase: 'idle' },
  failure: null,
  notice: null,
  replace: null,
  dragging: false,
  ...over,
});

test('the status bar says what is happening, in two short lines, in every state', () => {
  assert.equal(statusSentence(statusOf(base())), 'Choose a song and an image to begin.');
  assert.equal(statusOf(base({ audio })).first, 'Choose an image to go with the song.');
  assert.equal(statusOf(base({ image })).first, 'Choose a song to go with the image.');
  assert.equal(statusOf(base({ audio, image })).first, 'Ready to make your video.');
  assert.equal(statusOf(base({ audio, image, job: { phase: 'starting' } })).kind, 'starting');
  const running = statusOf(base({ audio, image, job: { phase: 'running', jobId: 'j', stage: 'encoding', percent: 40, remaining: { seconds: 22, at: 0 }, encoder: 'nvenc', stalled: false, cancelling: false } }));
  assert.deepEqual([running.first, running.second, running.progress?.percent, running.button?.label], ['Making the video · 40%', 'Using the NVIDIA encoder · about 20 seconds left', 40, 'Cancel']);
  const early = statusOf(base({ audio, image, job: { phase: 'running', jobId: 'j', stage: 'preparing', percent: null, remaining: null, encoder: null, stalled: false, cancelling: false } }));
  assert.deepEqual([early.first, early.second, early.progress?.percent], ['Getting ready', '', null]);
  const stalled = statusOf(base({ audio, image, job: { phase: 'running', jobId: 'j', stage: 'encoding', percent: 40, remaining: null, encoder: 'nvenc', stalled: true, cancelling: false } }));
  assert.deepEqual([stalled.first, stalled.button?.label, stalled.button?.disabled ?? false], ['Still working…', 'Cancel', false]);
  const cancelling = statusOf(base({ audio, image, job: { phase: 'running', jobId: 'j', stage: 'encoding', percent: 40, remaining: null, encoder: 'nvenc', stalled: false, cancelling: true } }));
  assert.deepEqual([cancelling.first, cancelling.button?.disabled], ['Cancelling', true]);
  assert.equal(statusSentence(statusOf(base({ audio, image, job: { phase: 'cancelled' } }))), 'Cancelled. Nothing was saved.');
  const done = statusOf(base({ audio, image, job: { phase: 'done', result: { outputId: 'f_o', fileName: 'Song.mp4', where: 'Videos', width: 1920, height: 1080, durationSeconds: 6, bytes: 1, codec: 'h264', encoder: 'nvenc', encoderFallback: false } } }));
  assert.deepEqual([done.first, done.second, done.button?.label, done.button?.filled], ['Saved Song.mp4 to Videos.', 'H.264 · NVIDIA encoder · 0:06', 'Show in File Explorer', true]);
});

test('a failure shows its two lines and one filled button; a repeat says so', () => {
  const once = statusOf(base({ audio, image, failure: { code: 'output_exists', details: '{}', again: false } }));
  assert.deepEqual([once.first, once.second, once.button?.label, once.button?.filled], ['A file with that name appeared while the video was being made.', "It was kept, and the new video wasn't saved.", 'Save As…', true]);
  const twice = statusOf(base({ audio, image, failure: { code: 'output_in_use', details: '{}', again: true } }));
  assert.deepEqual([twice.second, twice.button?.label], ['It failed again. Close it, then try again.', 'Copy Details']);
});

test('a notice takes the two lines and leaves the progress and Cancel where they are', () => {
  const view = statusOf(base({ audio, image, notice: 'Wait for the current video to finish.', job: { phase: 'running', jobId: 'j', stage: 'encoding', percent: 40, remaining: null, encoder: 'nvenc', stalled: false, cancelling: false } }));
  assert.deepEqual([view.kind, view.first, view.second, view.progress?.percent, view.button?.label], ['notice', 'Wait for the current video to finish.', '', 40, 'Cancel']);
});

// ---- the Replace question ----------------------------------------------------------------

test('a drop fills an empty slot at once and asks before replacing a filled one (SPEC 4a)', () => {
  const other: AudioInfo = { id: 'f_b', name: 'Other.mp3', durationSeconds: 61 };
  const otherImage: ImageInfo = { id: 'f_j', name: 'Other.png', width: 640, height: 480, frames: [] };
  const empty = decideDrop({ audio: null, image: null }, { audio, image });
  assert.deepEqual(empty, { kind: 'apply', slots: { audio, image } });
  const song = decideDrop({ audio, image }, { audio: other, image: null });
  assert.ok(song.kind === 'ask');
  assert.equal(song.question.title, 'Replace the current song?');
  assert.deepEqual(song.question.lines, [{ now: 'Song now: Song.mp3, 2:24', dropped: 'Dropped song: Other.mp3, 1:01' }]);
  assert.deepEqual(song.question.ifReplaced, { audio: other, image });
  assert.deepEqual(song.question.ifKept, { audio, image });
  const both = decideDrop({ audio, image }, { audio: other, image: otherImage });
  assert.ok(both.kind === 'ask');
  assert.equal(both.question.title, 'Replace the current song and image?');
  assert.equal(both.question.lines.length, 2);
  assert.equal(both.question.lines[1]?.dropped, 'Dropped image: Other.png, 640×480');
  // One slot empty, one filled: the empty one is filled whichever way the person answers.
  const mixed = decideDrop({ audio, image: null }, { audio: other, image });
  assert.ok(mixed.kind === 'ask');
  assert.equal(mixed.question.title, 'Replace the current song?');
  assert.deepEqual(mixed.question.ifKept, { audio, image });
  assert.deepEqual(mixed.question.ifReplaced, { audio: other, image });
});

test('the ids the page does not keep are freed', () => {
  const kept = { audio, image };
  const other: AudioInfo = { id: 'f_b', name: 'Other.mp3', durationSeconds: 61 };
  assert.deepEqual(idsToRelease([other, null, audio], kept), ['f_b']);
  assert.deepEqual(idsToRelease([audio, image], kept), []);
  assert.deepEqual(idsToRelease([other, other], { audio: null, image: null }), ['f_b']);
});
