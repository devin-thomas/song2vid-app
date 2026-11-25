// Every sentence the window says that is not a label, and the small rules that format numbers:
// the tool's error table (SPEC 27.5), the drop messages (SPEC 4a), the stage names, the Encoder
// names (SPEC 24.2) and the time left (SPEC 27.4, premium bar rule 66). The shell sends codes and
// numbers; these are the page's own words. Plain TypeScript with no imports beyond types, so the
// tests run it (test/words.test.ts).
import type { Codec, DropResult, EncoderName, EncoderReport, Stage } from '../bridge.ts';

export const CODEC_NAMES: Record<Codec, string> = { h264: 'H.264', hevc: 'HEVC' };

export const ENCODER_NAMES: Record<EncoderName, string> = {
  nvenc: 'NVIDIA encoder',
  media_foundation: 'graphics hardware encoder',
  software: 'software encoder',
  apple: 'Apple encoder',
};

/** "NVIDIA encoder"; a name from a newer tool that the page does not know is left out, never shown raw. */
export const encoderName = (encoder: string | null | undefined): string | null => (encoder && Object.hasOwn(ENCODER_NAMES, encoder) ? ENCODER_NAMES[encoder as EncoderName] : null);

export const STAGE_WORDS: Record<Stage, string> = {
  checking: 'Checking your files',
  preparing: 'Getting ready',
  encoding: 'Making the video',
  finishing: 'Saving the video',
};

/** m:ss, rounded to the second. */
export function clock(seconds: number): string {
  const whole = Math.max(0, Math.round(seconds));
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
}

/** "1920×1080". */
export const dimensions = (width: number, height: number): string => `${width}×${height}`;

/**
 * A file name cut in the middle so its start and its end both stay ("A very long photo…ame.jpg"): the part a person
 * recognises and the extension. Used where a name is part of a sentence; the rows cut theirs the same way in CSS
 * (src/components/FileName.tsx).
 */
export function shortName(name: string, max = 40): string {
  const chars = Array.from(name);
  if (chars.length <= max) return name;
  const tail = Math.min(10, Math.floor((max - 1) / 2));
  return `${chars.slice(0, max - tail - 1).join('')}…${chars.slice(chars.length - tail).join('')}`;
}

// ---- errors (SPEC 27.5) ----------------------------------------------------------

/** What the filled button of a failure does. */
export type FailureAction = 'choose-audio' | 'choose-image' | 'use-h264' | 'choose-folder' | 'save-as' | 'try-again' | 'copy-details' | 'open-download-page';

export interface Failure {
  /** The first line: what happened. */
  first: string;
  /** The second line: what it means for the person's files, or what to do. */
  second: string;
  action: FailureAction;
}

export const ACTION_LABELS: Record<FailureAction, string> = {
  'choose-audio': 'Choose Audio…',
  'choose-image': 'Choose Image…',
  'use-h264': 'Use H.264',
  'choose-folder': 'Choose Another Folder…',
  'save-as': 'Save As…',
  'try-again': 'Try Again',
  'copy-details': 'Copy Details',
  'open-download-page': 'Open Download Page',
};

const GENERIC: Failure = { first: "The video couldn't be made.", second: 'Your files are unchanged.', action: 'try-again' };

/** SPEC 27.5's table, each sentence split at its sentence break so each fits one line of the status bar. */
export const FAILURES: Record<string, Failure> = {
  audio_not_found: { first: 'The song file is no longer where it was.', second: '', action: 'choose-audio' },
  image_not_found: { first: 'The image file is no longer where it was.', second: '', action: 'choose-image' },
  audio_unreadable: { first: "Song2Vid can't read this audio file.", second: '', action: 'choose-audio' },
  image_unreadable: { first: "Song2Vid can't read this image file.", second: '', action: 'choose-image' },
  image_too_small: { first: 'This image is too small.', second: 'Each side needs at least 16 pixels.', action: 'choose-image' },
  codec_unavailable: { first: "This computer can't make HEVC videos.", second: '', action: 'use-h264' },
  output_not_writable: { first: "Couldn't save to that folder.", second: 'Nothing was saved.', action: 'choose-folder' },
  disk_full: { first: 'Not enough disk space.', second: 'Nothing was saved.', action: 'choose-folder' },
  output_in_use: { first: 'Another app is using that file.', second: 'Close it, then try again.', action: 'try-again' },
  output_exists: { first: 'A file with that name appeared while the video was being made.', second: "It was kept, and the new video wasn't saved.", action: 'save-as' },
  export_failed: GENERIC,
};

/**
 * What a file row says when its file is the problem (the tool could not find it or read it, or it cannot be drawn),
 * instead of the file's facts: the row, the preview, the status bar and Make Video then say one thing (S2V-031).
 */
export const slotProblemWords = (code: string): string => (code.endsWith('_not_found') ? "Can't find it" : code === 'image_too_small' ? 'Too small' : "Can't read it");

/** Failure codes that are about a file already in a slot: that slot is the problem until another file replaces it. */
export const slotOfFailure = (code: string): 'audio' | 'image' | null => (code.startsWith('audio_') ? 'audio' : code.startsWith('image_') ? 'image' : null);

/** A code the page does not know (a newer tool's) gets the generic sentence. */
export const failureFor = (code: string): Failure => (Object.hasOwn(FAILURES, code) ? (FAILURES[code] ?? GENERIC) : GENERIC);

/** The first line for a code the page knows, else null (the preview's own words stand in for a code it does not know). */
export const knownFailureFirst = (code: string): string | null => (Object.hasOwn(FAILURES, code) ? (FAILURES[code]?.first ?? null) : null);

/** The whole sentence, for the accessible name and for Copy Details' companions: both lines in one string. */
export const sentenceOf = (failure: Pick<Failure, 'first' | 'second'>): string => [failure.first, failure.second].filter(Boolean).join(' ');

/** The two lines the status bar shows for a failure; a repeat says so and offers Copy Details (premium bar rule 69). */
export function failureLines(code: string, again: boolean): Failure {
  const base = failureFor(code);
  if (!again) return base;
  return { first: base.first, second: ['It failed again.', base.second].filter(Boolean).join(' '), action: 'copy-details' };
}

/** Codes that mean the tool itself is missing or wrong: the one blocking state (SPEC 27.5). */
export const TOOL_CODES: readonly string[] = ['TOOL_NOT_FOUND', 'TOOL_INCOMPATIBLE', 'TOOL_STALLED'];
export const isToolCode = (code: string): boolean => TOOL_CODES.includes(code);

export const BLOCKED = { first: 'Song2Vid is missing part of itself.', second: 'Reinstall it to keep making videos.', action: 'open-download-page' as FailureAction };

// ---- drops (SPEC 4a) -----------------------------------------------------------------

export const WAIT_MESSAGE = 'Wait for the current video to finish.';
export const WAIT_LINES: Refusal = { first: WAIT_MESSAGE, second: '' };
export const NOTHING_DROPPED: Refusal = { first: 'Drop a song or an image.', second: '' };

type Rejection = Extract<DropResult, { status: 'rejected' }>['reason'];

/** A refused drop in two lines: what was refused, and what to do instead (SPEC 4a; the first line is shown with the error treatment). */
export interface Refusal {
  first: string;
  second: string;
}

/** The names the page can see of a drop, for the sentence; at most one is named, the rest are counted. */
const quoted = (name: string): string => `\u201c${shortName(name, 32)}\u201d`;

/**
 * The message for a drop that changes nothing, in the Mac app's words, now saying what was refused and why (S2V-031).
 * `names` are the dropped files' names when the page has them (a drop does; a file opened with the app does not).
 */
export function rejectionLines(reason: Rejection, names: readonly string[] = []): Refusal {
  const one = names.length === 1 ? quoted(names[0] ?? '') : null;
  switch (reason) {
    case 'folder':
      return { first: "Song2Vid can't use folders.", second: 'Drop a song or an image.' };
    case 'too-many':
      return { first: names.length > 2 ? `That is ${names.length} files, and Song2Vid takes two at most.` : 'That is more than two files.', second: 'Drop one song, one image, or one of each.' };
    case 'unsupported':
      return { first: one ? `${one} is not a song or an image Song2Vid can use.` : "Song2Vid can't read this kind of file.", second: 'Drop a song or an image.' };
    case 'more-audio':
      return { first: 'Song2Vid uses one song at a time.', second: 'Drop one song, one image, or one of each.' };
    case 'more-images':
      return { first: 'Song2Vid uses one image at a time.', second: 'Drop one song, one image, or one of each.' };
    case 'unreadable':
      return { first: one ? `Song2Vid can't read ${one}.` : "Song2Vid can't read that file.", second: 'Drop a song or an image.' };
  }
}

/** The whole refusal as one sentence. */
export const rejectionMessage = (reason: Rejection, names: readonly string[] = []): string => {
  const lines = rejectionLines(reason, names);
  return `${lines.first} ${lines.second}`;
};

/** Every refusal the page can say, for sizing the status bar to its longest. */
export const REJECTION_REASONS: readonly Rejection[] = ['folder', 'too-many', 'unsupported', 'more-audio', 'more-images', 'unreadable'];

/** One item of a drag in flight: the page sees a kind and a type, never a name or a path. */
export interface DragItem {
  kind: string;
  type: string;
}

/**
 * Whether a drag held over the window could be a valid drop, from the types alone (the names are
 * not readable until the drop). An unknown type is allowed to pass: the shell judges the real file.
 * Only a drop that cannot be used gets no highlight (SPEC 4a).
 */
export function dragLooksValid(items: readonly DragItem[]): boolean {
  if (items.length === 0 || items.length > 2) return false;
  if (items.some((item) => item.kind !== 'file')) return false;
  const audio = items.filter((item) => item.type.startsWith('audio/')).length;
  const images = items.filter((item) => item.type.startsWith('image/')).length;
  if (items.some((item) => item.type !== '' && !item.type.startsWith('audio/') && !item.type.startsWith('image/') && item.type !== 'application/ogg' && item.type !== 'video/mp4')) return false;
  return audio <= 1 && images <= 1;
}

// ---- progress ----------------------------------------------------------------------------

/** Time left, in coarse words (premium bar rule 66). */
export function timeLeftWords(seconds: number): string {
  if (seconds <= 8) return 'a few seconds left';
  if (seconds < 55) return `about ${Math.max(10, Math.round(seconds / 10) * 10)} seconds left`;
  const minutes = Math.max(1, Math.round(seconds / 60));
  return minutes === 1 ? 'about a minute left' : `about ${minutes} minutes left`;
}

/**
 * Whether the time left may be shown: encoding has run 1 s and passed 5% (SPEC 27.4, a recorded
 * exception to rule 66's 3 s because these jobs take seconds).
 */
export function mayShowTimeLeft(update: { stage: Stage; percent: number | null; elapsedSeconds: number; remainingSeconds: number | null }): boolean {
  return update.stage === 'encoding' && update.percent !== null && update.percent > 5 && update.elapsedSeconds >= 1 && update.remainingSeconds !== null;
}

/**
 * The remaining seconds the page shows: the tool's number, changing at most once a second and
 * never going up by more than a second at a time (the shell does the same; this applies it again).
 */
export function steadyRemaining(previous: { seconds: number; at: number } | null, next: number, now: number): { seconds: number; at: number } {
  if (!previous) return { seconds: next, at: now };
  if (now - previous.at < 1000) return previous;
  const seconds = next > previous.seconds ? Math.min(next, previous.seconds + 1) : next;
  return { seconds, at: now };
}

/** Progress never goes back and reads under 100 until the outcome (premium bar rule 65). */
export function steadyPercent(previous: number | null, next: number | null): number | null {
  if (next === null) return previous;
  const clamped = Math.min(99, Math.max(0, Math.round(next)));
  return previous === null ? clamped : Math.max(previous, clamped);
}

/** The second line of a finished video: "H.264 · NVIDIA encoder · 0:06" (SPEC 27.4). */
export function doneFacts(done: { codec: Codec; encoder: EncoderName; durationSeconds: number }): string {
  return [CODEC_NAMES[done.codec], encoderName(done.encoder), clock(done.durationSeconds)].filter(Boolean).join(' · ');
}

/** The note under the Codec picker when HEVC cannot be made (SPEC 23). */
export const HEVC_UNAVAILABLE = "This computer can't make HEVC videos.";

/** Whether HEVC may be chosen: yes unless the report says it cannot be made here. */
export const hevcAvailable = (report: EncoderReport | null): boolean => report === null || report.hevc.available;

/** "This image is smaller than 1920×1080 and will be enlarged, so it may look soft." */
export const enlargeNote = (width: number, height: number): string => `This image is smaller than ${dimensions(width, height)} and will be enlarged, so it may look soft.`;
