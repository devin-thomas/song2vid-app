// Data safety under a kill. Song2Vid has no document to lose; what it keeps across runs is the Codec
// a person chose (SPEC 27.7), and a choice must survive the process being ended at any moment. For each
// trial: start the development shell, choose HEVC in the page through its own control, terminate that
// exact process a set time after the choice, start the app again with the same data folder and read the
// Codec the page shows.
//
// Trials killed 300 ms or more after the choice must find HEVC chosen. The 60 ms trial may lose the
// choice only inside the last second (SPEC 28: at most the last second of input is lost).
//
// Usage: node qa/kill-test.ts   (writes qa/evidence/kill-test.json)
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { launchDev, root } from '../scripts/lib/launch.ts';
import { standinEnv } from './standin.ts';

const evidence = join(root, 'qa', 'evidence');
const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** What --qa-choose-codec writes: the process, the moment of the choice and the Codec chosen. */
interface Chosen {
  pid: number;
  at: number;
  expected: string;
}

/** What --qa-read-codec writes: the Codec the page shows after a relaunch. */
interface Restored {
  codec: string | null;
}

/** The JSON file the app writes at `file`, as the shape `T` that the flag documents. */
async function waitFor<T>(file: string, timeoutMs: number): Promise<T> {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    if (existsSync(file)) {
      try {
        return JSON.parse(readFileSync(file, 'utf8')) as T;
      } catch {
        // still being written
      }
    }
    await sleep(20);
  }
  throw new Error(`timed out waiting for ${file}`);
}

interface TrialResult {
  name: string;
  killedAfterMs: number;
  expected: string;
  restored: string | null;
  intact: boolean;
}

async function trial(name: string, killAfterMs: number): Promise<TrialResult> {
  const dataDir = join(root, 'qa', 'data', `kill-${name}`);
  const chosenFile = join(evidence, `kill-${name}-chosen.json`);
  const readFile = join(evidence, `kill-${name}-restored.json`);
  for (const f of [chosenFile, readFile]) rmSync(f, { force: true });
  rmSync(dataDir, { recursive: true, force: true });

  const first = launchDev({ args: [`--qa-choose-codec=${chosenFile}`], dataDir, timeoutMs: 90_000, env: standinEnv() });
  const chosen = await waitFor<Chosen>(chosenFile, 60_000);
  if (chosen.pid !== first.child.pid) throw new Error(`the app reported PID ${chosen.pid}, but ${first.child.pid} was started`);

  // Terminate that exact process, by PID (the check above proved the app's PID is the one started), the set time after the choice.
  await sleep(Math.max(0, chosen.at + killAfterMs - Date.now()));
  const killedAfterMs = Date.now() - chosen.at;
  process.kill(chosen.pid);
  await first.exited;
  await sleep(1500); // let the helper processes notice and exit

  const again = launchDev({ args: [`--qa-read-codec=${readFile}`], dataDir, timeoutMs: 90_000, env: standinEnv() });
  const restored = await waitFor<Restored>(readFile, 60_000);
  await again.exited;

  rmSync(dataDir, { recursive: true, force: true });
  for (const f of [chosenFile, readFile]) rmSync(f, { force: true });
  return { name, killedAfterMs, expected: chosen.expected, restored: restored.codec, intact: restored.codec === chosen.expected };
}

mkdirSync(evidence, { recursive: true });
const results: TrialResult[] = [];
results.push(await trial('600ms', 600));
results.push(await trial('300ms', 300));
results.push(await trial('60ms', 60));

const failures: string[] = [];
for (const r of results) {
  // Everything but the 60 ms trial must be intact; the 60 ms trial is judged by the one-second rule too (a kill that early
  // may still lose the choice only because it is inside the last second).
  if (r.name !== '60ms' && !r.intact) failures.push(`${r.name}: the page showed ${r.restored} after the relaunch, not ${r.expected}`);
  console.log(`${r.intact ? 'intact ' : 'partial'} kill at ${String(r.killedAfterMs).padStart(4)} ms after the choice (${r.name}): the page showed ${r.restored}`);
}
writeFileSync(join(evidence, 'kill-test.json'), JSON.stringify({ at: new Date().toISOString(), results, failures, passed: failures.length === 0 }, null, 2));
if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}
console.log('kill test passed');
