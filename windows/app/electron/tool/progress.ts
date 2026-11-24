// From the tool's `progress` lines (SPEC 14.5, 24.5) to the `running` update in src/bridge.ts.
// Pure: no Electron, no process and no clock of its own. Time is the lines' own
// `elapsed_seconds`, so a recorded stream replays to the same numbers every time.
//
// Percent (premium-bar rule 66):
//   - null while the tool does not know it yet (the page shows an indeterminate bar);
//   - never decreasing, and held at 99 until the final line, which the caller reports as
//     `done` (the model never says 100).
// Time left (premium-bar rule 67, with SPEC 27.4's recorded exception to rule 66's 3 seconds):
//   - the tool's own `remaining_seconds`, shown only once encoding has run SHOW_AFTER_MS and
//     passed SHOW_AFTER_PERCENT, because these jobs take seconds;
//   - the published value changes at most once a second and never counts up by more than one
//     second at a time; a quiet tool has none.
import type { EncoderName, Stage } from '../../src/bridge.ts';
import { readProgress } from './contract.ts';
import type { Line } from './contract.ts';

export const SHOW_AFTER_MS = 1000;
export const SHOW_AFTER_PERCENT = 5;
export const CHANGE_EVERY_MS = 1000;
export const HOLD = 99;

export interface ProgressSnapshot {
  stage: Stage;
  percent: number | null;
  elapsedSeconds: number;
  remainingSeconds: number | null;
  encoder: EncoderName | null;
  stalled: boolean;
}

export function createProgressModel(options: { showAfterMs?: number; showAfterPercent?: number; now?: () => number } = {}) {
  const showAfterMs = options.showAfterMs ?? SHOW_AFTER_MS;
  const showAfterPercent = options.showAfterPercent ?? SHOW_AFTER_PERCENT;
  const startedAt = options.now?.() ?? 0;
  const now = options.now ?? (() => 0);
  let stage: Stage = 'checking';
  let percent: number | null = null;
  let encoder: EncoderName | null = null;
  let elapsed = 0;
  let encodingSince: number | null = null;
  let remaining: number | null = null;
  let remainingAt = -Infinity;
  let stalled = false;

  function setRemaining(value: number | null, t: number): void {
    if (value === remaining) return;
    if (value === null) {
      remaining = null;
      remainingAt = t;
      return;
    }
    if (t - remainingAt < CHANGE_EVERY_MS) return;
    remaining = remaining !== null && value > remaining ? remaining + 1 : value;
    remainingAt = t;
  }

  /** Feed one line from the tool. Returns whether the snapshot may have changed. */
  function onLine(line: Line): boolean {
    if (line.type !== 'progress') return false;
    const p = readProgress(line);
    // The tool's own count when it sends one; otherwise the shell's clock (the update still moves).
    elapsed = p.elapsedSeconds ?? Math.max(elapsed, (now() - startedAt) / 1000);
    const t = elapsed * 1000;
    if (p.stage) stage = p.stage;
    if (p.encoder) encoder = p.encoder;
    if (p.percent !== null) percent = Math.max(percent ?? 0, Math.min(Math.max(p.percent, 0), HOLD));
    if (stage === 'encoding' && encodingSince === null) encodingSince = t;
    const trusted = !stalled && stage === 'encoding' && encodingSince !== null && t - encodingSince >= showAfterMs && percent !== null && percent >= showAfterPercent && p.remainingSeconds !== null;
    setRemaining(trusted && p.remainingSeconds !== null ? Math.max(1, Math.ceil(p.remainingSeconds)) : null, t);
    return true;
  }

  /** The inactivity watch says the tool has gone quiet (or is back). A quiet tool has no trustworthy time left. */
  function setStalled(value: boolean): void {
    stalled = value;
    if (value) setRemaining(null, elapsed * 1000);
  }

  const snapshot = (): ProgressSnapshot => ({ stage, percent, elapsedSeconds: elapsed, remainingSeconds: remaining, encoder, stalled });

  return { onLine, setStalled, snapshot };
}
