import { runAction, useApp } from '../state/app';
import { statusOf } from '../state/status';
import { SHORTCUTS, ariaKeys, keysOf } from '../state/shortcuts';
import { Tip } from './ui';

// The status bar: two lines of one line each, one height in every state (premium bar rule 97). It
// says what is happening, what happened, and what to do about it (SPEC 27.4, 27.5). A long line is
// cut at its end by the stylesheet; the whole sentence is in the page, so a screen reader reads it
// all. One filled button at most, and it is the step that can succeed.

export function StatusBar() {
  const state = useApp((s) => s);
  const view = statusOf(state);
  const cancel = SHORTCUTS['cancel'];
  const button = view.button;
  const progress = view.progress;
  return (
    <footer className="statusbar" data-status-bar="" data-job={view.kind}>
      <div className="statusbar-text" data-status-text="" aria-live="polite" aria-atomic="true">
        <p className="statusbar-line">{view.first}</p>
        <p className="statusbar-line">{view.second}</p>
      </div>
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
      {button && (
        <div className="statusbar-actions">
          {button.action === 'cancel' ? (
            <Tip label="Cancel" keys={keysOf(cancel)}>
              <button type="button" className="btn btn-secondary" aria-keyshortcuts={ariaKeys(cancel)} disabled={button.disabled} onClick={() => void runAction('cancel')}>
                {button.label}
              </button>
            </Tip>
          ) : (
            <button type="button" className="btn btn-primary" data-filled="" data-action={button.action} onClick={() => void runAction(button.action)}>
              {button.label}
            </button>
          )}
        </div>
      )}
    </footer>
  );
}
