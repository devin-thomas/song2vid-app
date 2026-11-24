// The adapter's calls against the tool, as SPEC 14, 24 and 27.6 describe them: the launch checks
// (`--version`, `encoders`), one file's facts (`check`), the picture the video will see
// (`preview`) and the job (`make`). No Electron in here, so the tests drive it with the stand-in
// tool (test/standin-tool.ts) on every system.
//
// Starting the tool and owning its lifetime is @uppercut-labs/electron-child-process-runner:
// absolute executable, argument array, no shell and no window; stdin kept open as the cancel
// channel (`--cancel-on-eof`) and closed to cancel; stdout and stderr always drained, with a
// bounded stderr tail; the process tree killed if it is still there after the grace period (a
// process group on macOS and Linux, taskkill /T on Windows); ELECTRON_RUN_AS_NODE never reaches
// the tool.
//
// What it guarantees the rest of the shell (premium-bar rules 59, 60, 65; SPEC 27.6):
//   - the tool's stdout is read as a stream of capped lines and every line is checked: JSON, an
//     `api_version` of "1" and a `type`. A line that is not JSON, a line over 1 MiB, or an exit
//     without exactly one final `result` or `error` line ends the call as `export_failed`, after
//     the rest of the output has been drained and the tool stopped;
//   - exactly one outcome per call: ok, cancelled or failed with a code;
//   - unknown keys and line types are ignored (SPEC 24.5);
//   - no job is ever killed for being silent: after `stallMs` with no line `onStall` says so and
//     the person can cancel. Only the short questions (version, encoders, check) have a limit;
//   - a cancel closes stdin, and the tool is killed `graceMs` (3 s) later if it is still there.
import { createLineReader, startProcess } from '@uppercut-labs/electron-child-process-runner';
import type { Outcome, RunningProcess } from '@uppercut-labs/electron-child-process-runner';
import type { EncoderReport } from '../../src/bridge.ts';
import { API_VERSION, VERSION_LINE, checkArgs, encodersArgs, makeArgs, previewArgs, readAudio, readEncoders, readError, readImage, readMade, readPreview, readVersion, versionArgs } from './contract.ts';
import type { AudioFacts, ImageFacts, Line, MadeFacts, MakeArgs } from './contract.ts';
import type { Located } from './locate.ts';

export const DEFAULTS = {
  /** `--version` must answer within this. */
  versionMs: 10_000,
  /** `encoders` finishes within 5 s (SPEC 26.4); the adapter allows twice that. */
  encodersMs: 10_000,
  /** `check` finishes within 3 s on Titan (SPEC 26.4); a slow disk gets ten times that. */
  checkMs: 30_000,
  maxLineBytes: 1024 * 1024,
  maxTotalBytes: 64 * 1024 * 1024,
  /** SPEC 27.6: after this long with no line the status bar says "Still working…". */
  stallMs: 30_000,
  /** SPEC 27.6: the time between closing stdin and killing the process. */
  graceMs: 3000,
};
export type Limits = typeof DEFAULTS;

/** Why the adapter, not the tool, ended a call. `code` is `export_failed` for the last three (SPEC 27.6). */
export type Fault = 'TOOL_NOT_FOUND' | 'TOOL_INCOMPATIBLE' | 'TOOL_PROTOCOL' | 'TOOL_CRASHED' | 'TOOL_STALLED';

export interface ToolError {
  /** A tool error code (SPEC 14.6, 24.6), a code from a newer tool, or a shell code (docs/BRIDGE.md). */
  code: string;
  /** Developer text: never shown, only copied. Holds no path. */
  message: string;
  /** Set when the adapter, not the tool, made this error. */
  fault: Fault | null;
  details: Record<string, unknown>;
}

/** `killed`: the tool was still there after its grace period (or its limit) and was killed, so it may have left its temporary file. */
export type CallOutcome<T> = { status: 'ok'; value: T; killed: boolean } | { status: 'cancelled'; killed: boolean } | { status: 'failed'; error: ToolError; killed: boolean };

export interface CallHooks {
  /** Every line, in order, before the call ends. */
  onLine?: (line: Line) => void;
  onStall?: (stalled: boolean) => void;
  /** Aborting it cancels: stdin is closed and the tool is killed after the grace period. */
  signal?: AbortSignal;
}

export type VersionAnswer = { ok: true; version: string } | { ok: false; error: ToolError };

export interface AdapterOptions {
  located: Extract<Located, { ok: true }>;
  cwd: string;
  platform?: NodeJS.Platform;
  env?: NodeJS.ProcessEnv;
  limits?: Partial<Limits>;
}

/** The code the page sees for a fault: the three that mean "the tool did not do what it said" are `export_failed` (SPEC 27.6). */
const codeOfFault = (fault: Fault): string => (fault === 'TOOL_NOT_FOUND' || fault === 'TOOL_INCOMPATIBLE' ? fault : 'export_failed');

/** Replaces each path (and its folder) in `text` with `<path>`, longest first, so Copy Details never carries one. */
function withoutPaths(text: string, paths: string[]): string {
  const names = [...new Set(paths.filter((p) => p.length > 3))].sort((a, b) => b.length - a.length);
  return names.reduce((out, name) => out.split(name).join('<path>'), text);
}

export function createAdapter(options: AdapterOptions) {
  const limits: Limits = { ...DEFAULTS, ...(options.limits ?? {}) };
  const { located, cwd } = options;

  function spawn(args: string[], onStdout: (chunk: Buffer) => void): RunningProcess {
    return startProcess({
      command: located.command,
      args: [...located.prefixArgs, ...args],
      cwd,
      ...(options.env ? { env: options.env } : {}),
      ...(options.platform ? { platform: options.platform } : {}),
      graceMs: limits.graceMs,
      onStdout,
    });
  }

  const pathsIn = (args: string[]): string[] => args.filter((a) => a.includes('/') || a.includes('\\')).flatMap((a) => [a, a.replace(/[\\/][^\\/]*$/, '')]);

  const failure = (fault: Fault, message: string, outcome: Outcome | null, args: string[], extra: Record<string, unknown> = {}): ToolError => ({
    code: codeOfFault(fault),
    message,
    fault,
    details: {
      fault,
      ...extra,
      ...(outcome ? { exitCode: outcome.exitCode, exitSignal: outcome.exitSignal, stderrTail: withoutPaths(outcome.stderrTail.slice(-2000), pathsIn(args)) } : {}),
    },
  });

  interface Run {
    final: Line | null;
    fault: { fault: Fault; message: string } | null;
    outcome: Outcome;
    timedOut: boolean;
    cancelRequested: boolean;
  }

  /**
   * One run of the tool whose stdout is JSON Lines. Resolves when the process and its pipes are
   * done; every fault of the stream is recorded, the tool is stopped and the rest is drained.
   */
  async function exchange(args: string[], opts: { limitMs?: number; hooks?: CallHooks }): Promise<Run> {
    const hooks = opts.hooks ?? {};
    let final: Line | null = null;
    let problem: { fault: Fault; message: string } | null = null;
    let stallTimer: ReturnType<typeof setTimeout> | undefined;
    let limitTimer: ReturnType<typeof setTimeout> | undefined;
    let stalled = false;
    let timedOut = false;
    let cancelRequested = false;
    let tool: RunningProcess | null = null;

    const fault = (kind: Fault, message: string): void => {
      if (problem) return;
      problem = { fault: kind, message };
      reader.stop();
      tool?.stop('protocol');
    };
    const watch = () => {
      clearTimeout(stallTimer);
      if (stalled) {
        stalled = false;
        hooks.onStall?.(false);
      }
      stallTimer = setTimeout(() => {
        stalled = true;
        hooks.onStall?.(true);
      }, limits.stallMs);
    };
    const reader = createLineReader({
      maxLineBytes: limits.maxLineBytes,
      maxTotalBytes: limits.maxTotalBytes,
      onOverflow: (kind) => fault('TOOL_PROTOCOL', kind === 'line' ? `a line over ${limits.maxLineBytes} bytes` : `over ${limits.maxTotalBytes} bytes of output`),
      onLine: (text) => {
        if (!text.trim()) return;
        let parsed: unknown;
        try {
          parsed = JSON.parse(text);
        } catch {
          return fault('TOOL_PROTOCOL', 'a line that is not JSON');
        }
        if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed) || typeof (parsed as { type?: unknown }).type !== 'string') return fault('TOOL_PROTOCOL', 'a line without a type');
        const line = parsed as Line;
        if (line.api_version === undefined) return fault('TOOL_PROTOCOL', 'a line without api_version');
        if (line.api_version !== API_VERSION) return fault('TOOL_INCOMPATIBLE', `api_version ${JSON.stringify(line.api_version)}`);
        if (final) return fault('TOOL_PROTOCOL', `"${line.type}" after the final line`);
        watch();
        if (line.type === 'result' || line.type === 'error') {
          final = line;
          clearTimeout(stallTimer);
        }
        try {
          hooks.onLine?.(line);
        } catch {
          // A consumer fault must not stop the stream.
        }
      },
    });

    const started = spawn(args, (chunk) => reader.push(chunk));
    tool = started;
    if (opts.limitMs) {
      limitTimer = setTimeout(() => {
        timedOut = true;
        started.kill();
      }, opts.limitMs);
    }
    const onAbort = () => {
      cancelRequested = true;
      started.stop('cancelled');
    };
    if (hooks.signal) {
      if (hooks.signal.aborted) onAbort();
      else hooks.signal.addEventListener('abort', onAbort, { once: true });
    }
    if (!opts.limitMs) watch();

    const outcome = await started.done;
    clearTimeout(limitTimer);
    clearTimeout(stallTimer);
    hooks.signal?.removeEventListener('abort', onAbort);
    reader.end();
    if (outcome.stopReason || outcome.exitCode !== 0) started.sweep();
    return { final, fault: problem, outcome, timedOut, cancelRequested };
  }

  /** The one outcome of a run: the final line, cancelled, or a failure with its code. */
  function conclude(run: Run, args: string[], limitMs: number | undefined): { kind: 'line'; line: Line; killed: boolean } | { kind: 'cancelled'; killed: boolean } | { kind: 'failed'; error: ToolError; killed: boolean } {
    const { outcome, final } = run;
    const killed = outcome.escalated;
    if (outcome.spawnError) return { kind: 'failed', error: failure('TOOL_NOT_FOUND', outcome.spawnError, null, args), killed };
    if (run.fault) return { kind: 'failed', error: failure(run.fault.fault, run.fault.message, outcome, args), killed };
    if (run.timedOut) return { kind: 'failed', error: failure('TOOL_STALLED', `no answer within ${limitMs ?? 0} ms`, outcome, args), killed };
    if (final?.type === 'result') {
      if (outcome.exitCode !== 0 && !outcome.escalated) return { kind: 'failed', error: failure('TOOL_CRASHED', `exit ${String(outcome.exitCode ?? outcome.exitSignal)} after a result`, outcome, args), killed };
      return { kind: 'line', line: final, killed };
    }
    if (final?.type === 'error') {
      const { code, message } = readError(final);
      if (code === 'cancelled') return { kind: 'cancelled', killed };
      return { kind: 'failed', error: { code, message, fault: null, details: { exitCode: outcome.exitCode, exitSignal: outcome.exitSignal } }, killed };
    }
    // No final line: a cancel we asked for that the tool could not report, or a crash.
    if (run.cancelRequested) return { kind: 'cancelled', killed };
    return { kind: 'failed', error: failure('TOOL_CRASHED', 'the tool ended without a final line', outcome, args), killed };
  }

  /** One call whose answer is one `result` line, read by `read`. A line that lacks what `read` needs is a protocol fault. */
  async function call<T>(args: string[], read: (line: Line) => T | null, opts: { limitMs?: number; hooks?: CallHooks } = {}): Promise<CallOutcome<T>> {
    const run = await exchange(args, opts);
    const done = conclude(run, args, opts.limitMs);
    if (done.kind === 'cancelled') return { status: 'cancelled', killed: done.killed };
    if (done.kind === 'failed') return { status: 'failed', error: done.error, killed: done.killed };
    const value = read(done.line);
    if (value === null) return { status: 'failed', error: failure('TOOL_PROTOCOL', 'the result lacks keys the shell needs', run.outcome, args), killed: done.killed };
    return { status: 'ok', value, killed: done.killed };
  }

  /** Plain stdout for `--version`: whatever it printed (at most one line's worth), and how it ended. */
  async function plain(args: string[], limitMs: number): Promise<{ text: string; outcome: Outcome; timedOut: boolean; overflow: boolean }> {
    const chunks: Buffer[] = [];
    let bytes = 0;
    const tool = spawn(args, (chunk) => {
      if (bytes < limits.maxLineBytes) chunks.push(chunk);
      bytes += chunk.length;
    });
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      tool.kill();
    }, limitMs);
    const outcome = await tool.done;
    clearTimeout(timer);
    return { text: Buffer.concat(chunks).toString('utf8'), outcome, timedOut, overflow: bytes > limits.maxLineBytes };
  }

  /**
   * SPEC 27.6: `--version --json` must say `song2vid 1.2.0`. SPEC 14.2 lists `--json` only for check, make and
   * `--update`, and the Mac command answers `--version --json` with a usage error, so when the first form gives no
   * version line at all the plain `--version` is asked. Either form must print exactly the line.
   */
  async function version(): Promise<VersionAnswer> {
    const args = versionArgs(true);
    let answer = await plain(args, limits.versionMs);
    const spoken = (text: string) => readVersion(text) !== null;
    if (!answer.outcome.spawnError && !answer.timedOut && !spoken(answer.text)) answer = await plain(versionArgs(false), limits.versionMs);
    const { outcome } = answer;
    const fail = (fault: Fault, message: string): VersionAnswer => ({ ok: false, error: { ...failure(fault, message, outcome, args), code: fault } });
    if (outcome.spawnError) return fail('TOOL_NOT_FOUND', outcome.spawnError);
    if (answer.timedOut) return fail('TOOL_STALLED', `no version within ${limits.versionMs} ms`);
    const said = answer.overflow ? null : readVersion(answer.text);
    if (said === null) return fail('TOOL_INCOMPATIBLE', answer.overflow ? 'a version answer over the line limit' : 'the answer to --version is not a version line');
    if (outcome.exitCode !== 0) return fail('TOOL_INCOMPATIBLE', `--version exited ${String(outcome.exitCode ?? outcome.exitSignal)}`);
    if (said !== VERSION_LINE) return fail('TOOL_INCOMPATIBLE', `the tool says "${said}", the app needs "${VERSION_LINE}"`);
    return { ok: true, version: said };
  }

  return {
    version,
    /** `encoders --json` (SPEC 24.2). */
    encoders: (): Promise<CallOutcome<EncoderReport>> => call(encodersArgs(), readEncoders, { limitMs: limits.encodersMs }),
    /** One-file `check` of a song (SPEC 24.8). A result that has no audio is the tool saying it is not one. */
    checkAudio: (file: string): Promise<CallOutcome<AudioFacts>> => call(checkArgs([file]), readAudio, { limitMs: limits.checkMs }),
    /** One-file `check` of an image: its size and the output-size table. */
    checkImage: (file: string): Promise<CallOutcome<ImageFacts>> => call(checkArgs([file]), readImage, { limitMs: limits.checkMs }),
    /** `preview` (SPEC 24.3): writes the PNG to `output`. Cancellable. */
    preview: (image: string, output: string, hooks: CallHooks = {}): Promise<CallOutcome<{ width: number; height: number }>> => call(previewArgs(image, output), readPreview, { hooks }),
    /** `make` (SPEC 14.4, 24): the job. */
    make: (args: MakeArgs, hooks: CallHooks = {}): Promise<CallOutcome<MadeFacts>> => call(makeArgs(args), readMade, { hooks }),
  };
}

export type Adapter = ReturnType<typeof createAdapter>;
