#!/usr/bin/env node
// A stand-in for `song2vid.exe` (SPEC 14, 24, 26 and 27.6), for the tests and for running the
// shell without a built tool (STANDIN_TOOL in electron/tool/index.ts). It takes the command's
// own arguments and replays a scenario from test/scenarios/: the JSON lines the real tool is
// specified to write, plus the faults a hostile or broken tool could add.
//
//   node standin-tool.ts [--standin-config=FILE] <the command's arguments>
//
// What it understands of the command line: `--version`, the subcommands `check`, `make`,
// `preview` and `encoders`, `--json`, `--cancel-on-eof`, `--overwrite` and the options that take a
// value (`--out`, `--shape`, `--resolution`, `--crop`, `--codec`). Any other flag is ignored, as
// a stand-in need not judge the line; the tests read what it was given from its log.
//
// A scenario is test/scenarios/NAME.json:
//   { "vars": { ... }, "cancel": "honour" | "ignore", "steps": [ ... ] }
// A step is one of:
//   { "delay_ms": N }                         wait
//   { "line": {...} }                         one JSON line, with "api_version":"1" added
//   { "line": {...}, "verbatim": true }       exactly as written (no api_version added)
//   { "raw": "text" }                         bytes as written (what `--version` prints)
//   { "noise_bytes": N, "newline_every": M }  N bytes of rubbish, with a newline every M bytes
//   { "line_bytes": N }                       one valid line of an unknown type, padded to N bytes
//   { "stderr": "text" }
//   { "progress": { "stage", "from", "to", "count", "every_ms", "encoder" } }
//                                             `count` progress lines from `from` to `to` percent;
//                                             "from": null writes lines with a null percent
//   { "temp": true, "content": "png" }        make the temporary file `.song2vid-<32 hex>.tmp` beside --out
//   { "publish": true }                       move it into place under the --out name
//   { "exit": N }                             leave now with this status
// Any step may say "only": "json" or "no-json", to be played only with or without `--json`.
// Strings may hold ${name}: the operands' names (name0, name1), the output's name (out_name), the
// options (shape, resolution, codec) and the scenario's vars. A string that is only ${name} keeps
// the value's type, so a number stays a number.
//
// Configuration (a JSON file named by --standin-config or STANDIN_CONFIG):
//   version, encoders, check_audio, check_image, preview, make
//                      the scenario for each kind of call (defaults: version-ok, encoders-ok,
//                      check-audio-ok, check-image-ok, preview-ok, make-ok)
//   vars               values for ${name} in the scenario, over the scenario's own "vars"
//   speed              divide every delay by this
//   log                append one JSON line per start ({ pid, argv }) and per cancel request
//                      ({ pid, event, at }) to this file
//   max_life_ms        leave after this long whatever happens (default 120000)
//
// Like the tool, it reads stdin only when `--cancel-on-eof` is given; end-of-file or a line
// `cancel` is then a cancel request (SPEC 24.4): the temporary file is removed, `cancelled` is
// written and it exits 130. A scenario with "cancel": "ignore" reads stdin and does nothing.
//
// Two lessons from build 2 are built in. It leaves from its write callback, so its last line is
// flushed before it exits (a stand-in that called exit after write lost the last line on Windows
// pipes). And it exits quietly when its reader goes away, as the real tool must.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

/** One step of a scenario (see above). */
interface Step {
  only?: 'json' | 'no-json';
  delay_ms?: number;
  line?: Record<string, unknown>;
  verbatim?: boolean;
  raw?: string;
  noise_bytes?: number;
  newline_every?: number;
  line_bytes?: number;
  stderr?: string;
  progress?: { stage: string; from: number | null; to?: number; count: number; every_ms: number; encoder?: string };
  temp?: boolean;
  content?: 'png';
  publish?: boolean;
  exit?: number | string;
}
interface Scenario {
  vars?: Record<string, unknown>;
  steps?: Step[];
  cancel?: 'honour' | 'ignore';
}
interface Config {
  version?: string;
  encoders?: string;
  check_audio?: string;
  check_image?: string;
  preview?: string;
  make?: string;
  vars?: Record<string, unknown>;
  speed?: number;
  log?: string;
  max_life_ms?: number;
}
const messageOf = (error: unknown) => (error instanceof Error ? error.message : String(error));

const started = Date.now();
const argv = process.argv.slice(2);

let configFile = process.env['STANDIN_CONFIG'] || null;
const rest: string[] = [];
for (const a of argv) {
  if (a.startsWith('--standin-config=')) configFile = a.slice('--standin-config='.length);
  else rest.push(a);
}
let config: Config = {};
if (configFile) {
  try {
    config = JSON.parse(fs.readFileSync(configFile, 'utf8')) as Config;
  } catch (error) {
    process.stderr.write(`standin: cannot read ${configFile}: ${messageOf(error)}\n`);
    process.exit(97);
  }
}

const VALUE_OPTIONS = new Map([
  ['--out', 'out'],
  ['-o', 'out'],
  ['--shape', 'shape'],
  ['-s', 'shape'],
  ['--resolution', 'resolution'],
  ['-r', 'resolution'],
  ['--crop', 'crop'],
  ['-c', 'crop'],
  ['--codec', 'codec'],
  ['-C', 'codec'],
]);
const opts = { command: null as string | null, version: false, json: false, cancelOnEof: false, overwrite: false, values: {} as Record<string, string>, operands: [] as string[] };
for (let i = 0; i < rest.length; i++) {
  const a = rest[i] ?? '';
  const valueName = VALUE_OPTIONS.get(a);
  if (valueName) opts.values[valueName] = rest[++i] ?? '';
  else if (a === '--version' || a === '-v') opts.version = true;
  else if (a === '--json' || a === '-j') opts.json = true;
  else if (a === '--cancel-on-eof' || a === '-E') opts.cancelOnEof = true;
  else if (a === '--overwrite' || a === '-w') opts.overwrite = true;
  else if (a.startsWith('-')) continue;
  else if (opts.command === null && ['check', 'make', 'preview', 'encoders'].includes(a)) opts.command = a;
  else opts.operands.push(a);
}

if (config.log) {
  try {
    fs.appendFileSync(config.log, `${JSON.stringify({ pid: process.pid, argv: rest, runAsNode: 'ELECTRON_RUN_AS_NODE' in process.env, at: started })}\n`);
  } catch {
    // The log is for tests.
  }
}
const logEvent = (event: string) => {
  if (!config.log) return;
  try {
    fs.appendFileSync(config.log, `${JSON.stringify({ pid: process.pid, event, at: Date.now() })}\n`);
  } catch {
    // The log is for tests.
  }
};

setTimeout(() => process.exit(98), config.max_life_ms ?? 120_000).unref();
process.stdout.on('error', () => process.exit(0)); // the reader went away

const write = (stream: NodeJS.WriteStream, data: string | Buffer) => new Promise<void>((resolve) => stream.write(data, () => resolve()));
async function leave(code: number): Promise<void> {
  await write(process.stdout, '');
  process.exit(code);
}

const isImageName = (name: string) => /\.(jpe?g|png|heic|tiff?|webp|gif|bmp)$/i.test(name);
let scenarioName: string;
if (opts.version) scenarioName = config.version ?? 'version-ok';
else if (opts.command === 'encoders') scenarioName = config.encoders ?? 'encoders-ok';
else if (opts.command === 'preview') scenarioName = config.preview ?? 'preview-ok';
else if (opts.command === 'make') scenarioName = config.make ?? 'make-ok';
else if (opts.command === 'check') scenarioName = isImageName(opts.operands[0] ?? '') ? (config.check_image ?? 'check-image-ok') : (config.check_audio ?? 'check-audio-ok');
else {
  process.stderr.write('standin: nothing to do for these arguments\n');
  process.exit(95);
}
const file = path.isAbsolute(scenarioName) ? scenarioName : path.join(import.meta.dirname, 'scenarios', `${scenarioName}.json`);
let scenario: Scenario = {};
try {
  scenario = JSON.parse(fs.readFileSync(file, 'utf8')) as Scenario;
} catch (error) {
  process.stderr.write(`standin: no scenario ${file}: ${messageOf(error)}\n`);
  process.exit(96);
}
const speed = config.speed ?? 1;
const base = (p: string | undefined) => (p ? path.basename(p) : '');
const vars: Record<string, unknown> = {
  name0: base(opts.operands[0]),
  name1: base(opts.operands[1]),
  out_name: base(opts.values['out']),
  shape: opts.values['shape'] ?? '',
  resolution: opts.values['resolution'] ?? '',
  codec: opts.values['codec'] ?? '',
  ...scenario.vars,
  ...config.vars,
};

/** Fills ${name} in every string of a value. A string that is only ${name} becomes the value itself. */
function fill<T>(value: T): T {
  if (typeof value === 'string') {
    const whole = /^\$\{(\w+)\}$/.exec(value);
    if (whole?.[1] !== undefined && whole[1] in vars) return vars[whole[1]] as T;
    return value.replace(/\$\{(\w+)\}/g, (match, name: string) => (name in vars ? String(vars[name]) : match)) as T;
  }
  if (Array.isArray(value)) return value.map(fill) as T;
  if (value !== null && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, fill(v)])) as T;
  return value;
}

let temp: string | null = null;
let finished = false;

function cleanUp() {
  if (temp) fs.rmSync(temp, { force: true });
  temp = null;
}

const lineOf = (body: Record<string, unknown>, verbatim = false) => `${JSON.stringify(verbatim ? body : { api_version: '1', ...body })}\n`;

// Cancel requests, as SPEC 24.4 describes them. Without --cancel-on-eof stdin is never read.
if (opts.cancelOnEof && scenario.cancel !== 'ignore') {
  let buffer = '';
  const cancel = async () => {
    if (finished) return;
    finished = true;
    logEvent('cancel');
    cleanUp();
    await write(process.stdout, lineOf({ type: 'error', error: { code: 'cancelled', message: 'Cancelled.' } }));
    await leave(130);
  };
  process.stdin.on('data', (chunk: Buffer) => {
    buffer += chunk.toString('utf8');
    if (buffer.split('\n').some((text) => text.trim() === 'cancel')) void cancel();
  });
  process.stdin.on('end', () => void cancel());
  process.stdin.on('error', () => void cancel());
} else if (opts.cancelOnEof) {
  process.stdin.on('data', () => {});
  process.stdin.on('end', () => logEvent('stdin-closed'));
  process.stdin.on('error', () => {});
}

const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');

async function play(): Promise<void> {
  for (const raw of scenario.steps ?? []) {
    if (finished) return;
    if ((raw.only === 'json' && !opts.json) || (raw.only === 'no-json' && opts.json)) continue;
    const step = fill(raw);
    if (step.delay_ms !== undefined) await new Promise((r) => setTimeout(r, step.delay_ms! / speed));
    else if (step.line) await write(process.stdout, lineOf(step.line, step.verbatim));
    else if (step.raw !== undefined) await write(process.stdout, step.raw);
    else if (step.noise_bytes) {
      const every = step.newline_every ?? 0;
      let left = step.noise_bytes;
      while (left > 0) {
        const size = Math.min(left, 64 * 1024);
        const chunk = Buffer.alloc(size, 0x7a);
        if (every) for (let i = every - 1; i < size; i += every) chunk[i] = 0x0a;
        await write(process.stdout, chunk);
        left -= size;
      }
    } else if (step.line_bytes) {
      const pad = 'x'.repeat(Math.max(0, step.line_bytes - lineOf({ type: 'unknown-padding', pad: '' }).length));
      await write(process.stdout, lineOf({ type: 'unknown-padding', pad }));
    } else if (step.stderr !== undefined) await write(process.stderr, step.stderr);
    else if (step.progress) {
      const { stage, from, count, every_ms: every } = step.progress;
      const to = step.progress.to ?? from ?? 0;
      for (let i = 0; i < count; i++) {
        if (finished) return;
        const percent = from === null ? null : count === 1 ? to : Math.round((from + ((to - from) * i) / (count - 1)) * 10) / 10;
        const elapsed = Math.round((Date.now() - started) / 100) / 10;
        const left = percent === null || percent <= 0 ? null : Math.round(((elapsed * (100 - percent)) / percent) * 10) / 10;
        await write(process.stdout, lineOf({ type: 'progress', stage, percent, elapsed_seconds: elapsed, remaining_seconds: left, ...(step.progress.encoder ? { encoder: step.progress.encoder } : {}) }));
        await new Promise((r) => setTimeout(r, every / speed));
      }
    } else if (step.temp) {
      const out = opts.values['out'];
      if (out) {
        temp = path.join(path.dirname(path.resolve(out)), `.song2vid-${crypto.randomBytes(16).toString('hex')}.tmp`);
        fs.writeFileSync(temp, step.content === 'png' ? PNG : 'standin output\n');
      }
    } else if (step.publish) {
      const out = opts.values['out'];
      if (temp && out) {
        fs.renameSync(temp, path.resolve(out));
        temp = null;
      }
    } else if (step.exit !== undefined) {
      finished = true;
      await leave(Number(step.exit));
    }
  }
  if (finished) return;
  finished = true;
  await leave(0);
}

void play();
