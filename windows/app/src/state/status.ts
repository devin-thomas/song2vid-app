// The status bar's words and buttons for any state of the window (SPEC 27.4, 27.5). One bar, one
// height: two short lines, each cut at its end by the stylesheet with the whole sentence kept in
// the accessible name (premium bar rules 97 and 71). Plain TypeScript, tested in test/status.test.ts.
import type { AppState } from './model.ts';
import { ACTION_LABELS, STAGE_WORDS, doneFacts, encoderName, failureLines, timeLeftWords } from './words.ts';
import type { FailureAction } from './words.ts';

export interface StatusButton {
  /** What pressing it does. `show-in-folder` and `cancel` are not failure actions. */
  action: FailureAction | 'show-in-folder' | 'cancel';
  label: string;
  /** Filled: the button that can succeed. Cancel is not filled. */
  filled: boolean;
  disabled?: boolean;
}

export interface StatusView {
  kind: 'idle' | 'notice' | 'starting' | 'running' | 'cancelling' | 'stalled' | 'cancelled' | 'done' | 'failure';
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
  return state.notice ? { ...view, kind: 'notice', first: state.notice, second: '' } : view;
}

function statusWithoutNotice(state: AppState): StatusView {
  const { job, failure } = state;

  if (job.phase === 'starting') return { kind: 'starting', first: 'Getting ready', second: '' };

  if (job.phase === 'running') {
    if (job.cancelling) return { kind: 'cancelling', first: 'Cancelling', second: '', progress: { percent: job.percent }, button: { action: 'cancel', label: 'Cancel', filled: false, disabled: true } };
    const cancel: StatusButton = { action: 'cancel', label: 'Cancel', filled: false };
    if (job.stalled) return { kind: 'stalled', first: 'Still working…', second: '', progress: { percent: job.percent }, button: cancel };
    const percent = job.percent === null ? '' : ` · ${job.percent}%`;
    // The store keeps `remaining` only once encoding has run 1 s and passed 5% (SPEC 27.4).
    const left = job.remaining ? timeLeftWords(job.remaining.seconds) : '';
    const encoder = job.stage === 'encoding' ? encoderName(job.encoder) : null;
    const second = [encoder ? `Using the ${encoder}` : '', left].filter(Boolean).join(' · ');
    return { kind: 'running', first: `${STAGE_WORDS[job.stage]}${percent}`, second, progress: { percent: job.percent }, button: cancel };
  }

  if (failure) {
    const lines = failureLines(failure.code, failure.again);
    return { kind: 'failure', first: lines.first, second: lines.second, button: { action: lines.action, label: ACTION_LABELS[lines.action], filled: true } };
  }

  if (job.phase === 'cancelled') return { kind: 'cancelled', first: 'Cancelled. Nothing was saved.', second: '' };

  if (job.phase === 'done') {
    const { result } = job;
    return {
      kind: 'done',
      first: `Saved ${result.fileName} to ${result.where}.`,
      second: doneFacts(result),
      button: { action: 'show-in-folder', label: SHOW_IN_FOLDER, filled: true },
    };
  }

  if (!state.audio && !state.image) return { kind: 'idle', first: 'Choose a song and an image to begin.', second: '' };
  if (!state.audio) return { kind: 'idle', first: 'Choose a song to go with the image.', second: '' };
  if (!state.image) return { kind: 'idle', first: 'Choose an image to go with the song.', second: '' };
  return { kind: 'idle', first: 'Ready to make your video.', second: '' };
}

/** The whole text of the bar as one sentence, for its accessible name. */
export const statusSentence = (view: StatusView): string => (view.second ? `${view.first}${/[.…!?]$/.test(view.first) ? ' ' : '. '}${view.second}` : view.first);
