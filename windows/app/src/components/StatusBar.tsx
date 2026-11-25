import { CircleAlert, CircleCheck, TriangleAlert } from 'lucide-react';
import { memo } from 'react';
import { runAction, useApp } from '../state/app';
import { everyStatusView, statusOf } from '../state/status';
import type { StatusView, Tone } from '../state/status';
import { SHORTCUTS, ariaKeys, keysOf } from '../state/shortcuts';
import { Tip } from './ui';

// The status bar says what is happening, what happened, and what to do about it (SPEC 27.4, 27.5). Its sentences wrap and
// are never cut. It is as tall as its longest message at the width it has, in every state, so nothing around it moves
// (premium bar rule 97): the live message sits in one grid cell with every message the bar can say drawn invisibly
// in the same cell (everyStatusView), and the cell takes the height of the tallest. No script measures anything.
// A failure and a refusal carry a mark and a colour so they are not read as a status; a saved video carries a check.
// One filled button at most, and it is the step that can succeed. Progress is the bar across the top edge.

const MARKS: Record<Tone, typeof CircleAlert | null> = { neutral: null, success: CircleCheck, danger: CircleAlert, warning: TriangleAlert };

function Mark({ tone }: { tone: Tone }) {
  const Icon = MARKS[tone];
  return Icon ? <Icon className="statusbar-mark" size={18} strokeWidth={2} aria-hidden="true" /> : null;
}

/** One message laid out as the bar lays it out: the live one, or an invisible one that only sets the bar's height. */
function Layer({ view, live }: { view: StatusView; live: boolean }) {
  const cancel = SHORTCUTS['cancel'];
  const button = view.button;
  return (
    <div className="statusbar-layer" data-live={live ? '' : undefined} data-tone={view.tone} aria-hidden={live ? undefined : true} inert={live ? undefined : true}>
      <Mark tone={view.tone} />
      <div className="statusbar-text" data-status-text={live ? '' : undefined} aria-live={live ? 'polite' : undefined} aria-atomic={live ? true : undefined}>
        <p className="statusbar-first">{view.first}</p>
        <p className="statusbar-second">{view.second}</p>
      </div>
      {button && (
        <div className="statusbar-actions">
          {button.action === 'cancel' ? (
            live ? (
              <Tip label="Cancel" keys={keysOf(cancel)}>
                <button type="button" className="btn btn-secondary" aria-keyshortcuts={ariaKeys(cancel)} disabled={button.disabled} onClick={() => void runAction('cancel')}>
                  {button.label}
                </button>
              </Tip>
            ) : (
              <button type="button" className="btn" tabIndex={-1} disabled>
                {button.label}
              </button>
            )
          ) : (
            <button type="button" className={live ? 'btn btn-primary' : 'btn'} data-filled={live ? '' : undefined} data-action={live ? button.action : undefined} tabIndex={live ? undefined : -1} onClick={live ? () => void runAction(button.action) : undefined}>
              {button.label}
            </button>
          )}
        </div>
      )}
    </div>
  );
}

const VIEWS = everyStatusView();

/** The invisible messages. Static, so they are drawn once. */
const Sizing = memo(function Sizing() {
  return (
    <>
      {VIEWS.map((view, index) => (
        <Layer key={index} view={view} live={false} />
      ))}
    </>
  );
});

export function StatusBar() {
  const state = useApp((s) => s);
  const view = statusOf(state);
  const progress = view.progress;
  return (
    <footer className="statusbar" data-status-bar="" data-job={view.kind} data-tone={view.tone}>
      {progress && (
        <div
          className="statusbar-progress"
          role="progressbar"
          aria-label="Progress"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={progress.percent === null ? undefined : progress.percent}
          data-indeterminate={progress.percent === null ? '' : undefined}
        >
          {progress.percent !== null && <span style={{ transform: `scaleX(${progress.percent / 100})` }} />}
        </div>
      )}
      <div className="statusbar-stack">
        <Layer view={view} live />
        <Sizing />
      </div>
    </footer>
  );
}
