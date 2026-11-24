// Turns the launch checks (`--version`, `encoders`: SPEC 27.6) into what the page is told
// (`ToolStatus` and `EncoderReport` in src/bridge.ts). Also keeps the last good answers on disk,
// keyed by the binaries' size and modified time, so a launch can show a ready state and a Codec
// picker while its own check runs. The answer is refreshed in the background on every launch,
// because a driver can change.
import fs from 'node:fs';
import path from 'node:path';
import type { EncoderReport, ToolStatus } from '../../src/bridge.ts';
import type { ToolError, VersionAnswer } from './adapter.ts';
import type { Located } from './locate.ts';

export function toolStatus(answer: VersionAnswer): ToolStatus {
  if (!answer.ok) return damaged(answer.error);
  return { state: 'ready', code: null, details: answer.version };
}

/** One blocking state for a missing, unreadable or wrong-version tool (SPEC 27.5). `details` is developer text. */
export function damaged(error: Pick<ToolError, 'code' | 'message' | 'details'>): ToolStatus {
  const extra = Object.keys(error.details).length ? JSON.stringify(error.details) : '';
  return { state: 'damaged', code: error.code, details: [error.code, error.message, extra].filter(Boolean).join('\n') };
}

/** What a launch learned about the tool. */
export interface Report {
  version: string;
  encoders: EncoderReport | null;
}

function stamp(file: string | null): string | null {
  if (!file) return null;
  try {
    const s = fs.statSync(file);
    return `${file}|${s.size}|${Math.round(s.mtimeMs)}`;
  } catch {
    return `${file}|missing`;
  }
}

/** What the cached answer depends on: the tool binary and every helper beside it. */
export function cacheKey(located: Located): string | null {
  if (!located.ok) return null;
  return [stamp(located.binary), ...Object.values(located.helpers).map((h) => stamp(h.file))].join('\n');
}

const isEncoder = (value: unknown): boolean => typeof value === 'object' && value !== null && typeof (value as { available?: unknown }).available === 'boolean';

/** The last good answers, kept in the data folder. Shown while this launch's own check runs. */
export function createReportCache(dataDir: string) {
  const file = path.join(dataDir, 'tool', 'report.json');
  return {
    read(located: Located): Report | null {
      const key = cacheKey(located);
      if (!key) return null;
      try {
        const saved = JSON.parse(fs.readFileSync(file, 'utf8')) as { key?: unknown; report?: { version?: unknown; encoders?: { h264?: unknown; hevc?: unknown } | null } };
        const report = saved.report;
        if (saved.key !== key || typeof report?.version !== 'string') return null;
        const encoders = report.encoders && isEncoder(report.encoders.h264) && isEncoder(report.encoders.hevc) ? (report.encoders as EncoderReport) : null;
        return { version: report.version, encoders };
      } catch {
        return null;
      }
    },
    write(located: Located, report: Report | null): void {
      const key = cacheKey(located);
      try {
        if (!key || !report) {
          fs.rmSync(file, { force: true });
          return;
        }
        fs.mkdirSync(path.dirname(file), { recursive: true });
        fs.writeFileSync(`${file}.tmp`, JSON.stringify({ key, report, at: new Date().toISOString() }));
        fs.renameSync(`${file}.tmp`, file);
      } catch {
        // The cache is a convenience.
      }
    },
  };
}
