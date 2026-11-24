// Latency in the real shell. Starts the development shell without taking focus and times the
// palette shortcut to the palette. Song2Vid has no text field, so there is no typing run (SPEC 28:
// rules 27, 29, 41, 41b and 44 are N/A, and the gate says so). Measured by
// @uppercut-labs/electron-qa-measurements inside the app (electron/qa.ts) and judged by
// qa/premium-gate.ts against the published premium bar (palette within 50 ms, the window never focused).
//
// The times run from the key event's timestamp to the end of the frame that
// rendered the change, on the page's clock. They leave out the compositor and
// the display, so they are a floor, not key-to-photon.
//
// The window opens on the primary display. Run it only when the owner has said
// the machine is free.
//
// Usage: node qa/typing.ts   (writes qa/evidence/typing.json)
import { mkdirSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import type { PaletteResult } from '@uppercut-labs/electron-qa-measurements';
import type { GateResult } from './premium-gate.ts';
import { launchDev, root } from '../scripts/lib/launch.ts';
import { standinEnv } from './standin.ts';

interface Report {
  display: { hz: number; scale: number };
  palette: PaletteResult;
  gate: GateResult;
  passed: boolean;
  error?: string;
}

const evidence = join(root, 'qa', 'evidence');
const dataDir = join(root, 'qa', 'data', 'typing');
const out = join(evidence, 'typing.json');

mkdirSync(evidence, { recursive: true });
rmSync(out, { force: true });
rmSync(dataDir, { recursive: true, force: true });
const app = launchDev({ args: [`--qa-typing=${out}`], dataDir, timeoutMs: 120_000, env: standinEnv() });
await app.exited;
rmSync(dataDir, { recursive: true, force: true });

const report = JSON.parse(readFileSync(out, 'utf8')) as Report;
if (report.error) {
  console.error(`typing run FAILED inside the app: ${report.error}`);
  process.exit(1);
}
console.log(`display ${report.display.hz} Hz at ${report.display.scale}x`);
console.log(`palette open           p50 ${report.palette.open.p50} ms, max ${report.palette.open.max} ms over ${report.palette.open.samples} opens`);
console.log(report.gate.summary);
if (!report.passed) {
  console.error(`typing gate FAILED (${report.gate.judgedBy}): ${report.gate.reasons.join('; ')}`);
  process.exit(1);
}
console.log(`typing gate passed (${report.gate.judgedBy})`);
