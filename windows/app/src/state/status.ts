// The status bar's words, tone and buttons for any state of the window (SPEC 27.4, 27.5). One bar, one
// height: the bar is as tall as its longest message at the width it has, so every state sits in the same
// place (premium bar rule 97) and no sentence is ever cut (S2V-031). Plain TypeScript, tested in
// test/words.test.ts and test/app.test.ts.
import type { Codec, EncoderName } from '../bridge.ts';
import { outputFrame } from './frame.ts';
import type { AppState } from './model.ts';
import {
  ACTION_LABELS,
  ENCODER_NAMES,
  FAILURES,
  NOTHING_DROPPED,
  REJECTION_REASONS,
  STAGE_WORDS,
  WAIT_LINES,
  doneFacts,
  encoderName,
  failureLines,
  rejectionLines,
  shortName,
  timeLeftWords,
} from './words.ts';
import type { FailureAction } from './words.ts';

export interface StatusButton {
  /** What pressing it does. `show-in-folder` and `cancel` are not failure actions. */
  action: FailureAction | 'show-in-folder' | 'cancel';
  label: string;
  /** Filled: the button that can succeed. Cancel is not filled. */
  filled: boolean;
  disabled?: boolean;
}

/** What the bar looks like: a failure and a refusal are not a status (a mark and a colour), a saved video is not idle. */
export type Tone = 'neutral' | 'success' | 'danger' | 'warning';

export interface StatusView {
  kind: 'idle' | 'notice' | 'starting' | 'running' | 'cancelling' | 'stalled' | 'cancelled' | 'done' | 'failure' | 'blocked';
  tone: Tone;
  first: string;
  second: string;
  /** Present while a job runs: null is the indeterminate bar. */
  progress?: { percent: number | null };
  button?: StatusButton;
}

const SHOW_IN_FOLDER = 'Show in File Explorer';

/** The status bar for a state, in one place so every state has words and a test. */
export function statusOf(state: AppState): StatusView {
  const view = statusWithoutNotice(state);
  // A message of a few seconds takes the two lines and leaves the progress and its button where they are.
  return state.notice ? { ...view, kind: 'notice', tone: 'warning', first: state.notice.first, second: state.notice.second } : view;
}

const failureView = (code: string, again: boolean): StatusView => {
  const lines = failureLines(code, again);
  return { kind: 'failure', tone: 'danger', first: lines.first, second: lines.second, button: { action: lines.action, label: ACTION_LABELS[lines.action], filled: true } };
};

function statusWithoutNotice(state: AppState): StatusView {
  const { job, failure } = state;

  // The tool is missing: the card says so and has the buttons; the bar says nothing that could be taken for "ready".
  if (state.tool.state === 'damaged') return { kind: 'blocked', tone: 'neutral', first: '', second: '' };

  if (job.phase === 'starting') return { kind: 'starting', tone: 'neutral', first: 'Getting ready', second: '' };

  if (job.phase === 'running') {
    if (job.cancelling) return { kind: 'cancelling', tone: 'neutral', first: 'Cancelling', second: '', progress: { percent: job.percent }, button: { action: 'cancel', label: 'Cancel', filled: false, disabled: true } };
    const cancel: StatusButton = { action: 'cancel', label: 'Cancel', filled: false };
    if (job.stalled) return { kind: 'stalled', tone: 'neutral', first: 'Still working…', second: '', progress: { percent: job.percent }, button: cancel };
    // The percent is said once, here; the bar above carries no number (S2V-031).
    const percent = job.percent === null ? '' : ` · ${job.percent}%`;
    // The store keeps `remaining` only once encoding has run 1 s and passed 5% (SPEC 27.4).
    const left = job.remaining ? timeLeftWords(job.remaining.seconds) : '';
    const encoder = job.stage === 'encoding' ? encoderName(job.encoder) : null;
    const second = [encoder ? `Using the ${encoder}` : '', left].filter(Boolean).join(' · ');
    return { kind: 'running', tone: 'neutral', first: `${STAGE_WORDS[job.stage]}${percent}`, second, progress: { percent: job.percent }, button: cancel };
  }

  if (failure) return failureView(failure.code, failure.again);

  if (job.phase === 'cancelled') return { kind: 'cancelled', tone: 'neutral', first: 'Cancelled. Nothing was saved.', second: '' };

  if (job.phase === 'done') {
    const { result } = job;
    return {
      kind: 'done',
      tone: 'success',
      first: `Saved ${shortName(result.fileName, 36)} to ${shortName(result.where, 20)}.`,
      second: doneFacts(result),
      button: { action: 'show-in-folder', label: SHOW_IN_FOLDER, filled: true },
    };
  }

  // An image that cannot be made into a frame says what blocks Make Video, in the table's own words.
  if (state.image && !outputFrame({ width: state.image.width, height: state.image.height }, state.shape, state.tier, state.crop)) return failureView('image_too_small', false);

  if (!state.audio && !state.image) return { kind: 'idle', tone: 'neutral', first: 'Choose a song and an image to begin.', second: '' };
  if (!state.audio) return { kind: 'idle', tone: 'neutral', first: 'Choose a song to go with the image.', second: '' };
  if (!state.image) return { kind: 'idle', tone: 'neutral', first: 'Choose an image to go with the song.', second: '' };
  return { kind: 'idle', tone: 'neutral', first: 'Ready to make your video.', second: '' };
}

/** The whole text of the bar as one sentence, for its accessible name. */
export const statusSentence = (view: StatusView): string => (view.second ? `${view.first}${/[.…!?]$/.test(view.first) ? ' ' : '. '}${view.second}` : view.first);

/**
 * Every message the bar can say, with the button that goes with it, so the bar can be as tall as its longest at any
 * width without a script measuring it (src/components/StatusBar.tsx draws them invisibly beside the live one). The
 * file name of a saved video and the dropped file's name are cut by `shortName`, which is what bounds these.
 */
export function everyStatusView(): StatusView[] {
  const views: StatusView[] = [];
  const longName = 'A very long song name that goes on.mp4';
  for (const code of Object.keys(FAILURES)) {
    views.push(failureView(code, false), failureView(code, true));
  }
  views.push(failureView('something_new', false), failureView('something_new', true));
  for (const reason of REJECTION_REASONS) {
    const lines = rejectionLines(reason, [longName]);
    views.push({ kind: 'notice', tone: 'warning', first: lines.first, second: lines.second });
  }
  views.push({ kind: 'notice', tone: 'warning', first: WAIT_LINES.first, second: WAIT_LINES.second, button: { action: 'cancel', label: 'Cancel', filled: false } });
  views.push({ kind: 'notice', tone: 'warning', first: NOTHING_DROPPED.first, second: NOTHING_DROPPED.second });
  const codecs: Codec[] = ['h264', 'hevc'];
  const encoders = Object.keys(ENCODER_NAMES) as EncoderName[];
  for (const codec of codecs) {
    for (const encoder of encoders) {
      views.push({
        kind: 'done',
        tone: 'success',
        first: `Saved ${shortName(longName, 36)} to ${shortName('Music videos made with Song2Vid', 20)}.`,
        second: doneFacts({ codec, encoder, durationSeconds: 3599 }),
        button: { action: 'show-in-folder', label: SHOW_IN_FOLDER, filled: true },
      });
    }
  }
  for (const encoder of encoders) {
    views.push({ kind: 'running', tone: 'neutral', first: `${STAGE_WORDS.encoding} · 99%`, second: `Using the ${ENCODER_NAMES[encoder]} · about 10 minutes left`, progress: { percent: 99 }, button: { action: 'cancel', label: 'Cancel', filled: false } });
  }
  views.push({ kind: 'cancelled', tone: 'neutral', first: 'Cancelled. Nothing was saved.', second: '' });
  views.push({ kind: 'idle', tone: 'neutral', first: 'Choose a song and an image to begin.', second: '' });
  return views;
}
