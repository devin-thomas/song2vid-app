// The job record: written before the tool starts, removed at the end of the job. A record found
// at the next launch names the folder a killed run was writing into (SPEC 27.6).
//
// Why it exists (build 2, test/host-kill.test.ts): when the app is killed, what happens to its
// tool differs per system. On Windows the tool dies at once with the app (libuv keeps its direct
// children in a kill-on-close job object), so it never removes its temporary file. On macOS and
// Linux the tool sees its stdin close, stops and cleans up by itself. The record covers the one
// case the tool cannot: its own hard kill.
//
// What may be removed (SPEC 26.3, 27.6): a regular file named `.song2vid-<32 hex>.tmp`, directly
// in the recorded folder. Never a folder, a link, a file with any other name, a file in another
// folder, or anything a record's other fields name.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export interface JobRecord {
  jobId: string;
  /** The folder the tool writes its temporary file in: the folder of the output. */
  folder: string;
  startedAt: string;
}

/**
 * @param dir          the folder for records (in the app's data folder)
 * @param stagingName  what the tool's temporary file is called; nothing else is ever removed
 */
export function createJobRecords(dir: string, stagingName: RegExp) {
  const fileOf = (jobId: string) => path.join(dir, `${jobId}.json`);

  function write(record: JobRecord): void {
    fs.mkdirSync(dir, { recursive: true });
    const file = fileOf(record.jobId);
    fs.writeFileSync(`${file}.tmp`, JSON.stringify(record));
    fs.renameSync(`${file}.tmp`, file);
  }

  function remove(jobId: string): void {
    fs.rmSync(fileOf(jobId), { force: true });
  }

  /** The temporary files in `folder` (names only), or none when the folder is not a folder this can read. */
  function leftovers(folder: unknown): string[] {
    if (typeof folder !== 'string' || !path.isAbsolute(folder)) return [];
    const where = path.resolve(folder);
    try {
      return fs
        .readdirSync(where)
        .filter((name) => stagingName.test(name))
        .filter((name) => fs.lstatSync(path.join(where, name)).isFile());
    } catch {
      return [];
    }
  }

  /** Remove the temporary files in `folder`, except the names in `keep` (files that were there before the job). Returns how many. */
  function removeLeftovers(folder: unknown, keep: ReadonlySet<string> = new Set()): number {
    let removed = 0;
    for (const name of leftovers(folder)) {
      if (keep.has(name)) continue;
      try {
        fs.rmSync(path.join(path.resolve(String(folder)), name), { force: true });
        removed += 1;
      } catch {
        // A file another program holds open stays until the next launch.
      }
    }
    return removed;
  }

  /** At launch: every record left behind names a folder whose temporary files go. `current` is a job id of this run, if any. */
  function reconcile(current: string | null = null): { records: number; removed: number } {
    const report = { records: 0, removed: 0 };
    let names: string[] = [];
    try {
      names = fs.readdirSync(dir);
    } catch {
      return report;
    }
    for (const name of names) {
      if (!name.endsWith('.json') || (current && name === `${current}.json`)) continue;
      const file = path.join(dir, name);
      report.records += 1;
      try {
        const record = JSON.parse(fs.readFileSync(file, 'utf8')) as Partial<Record<'folder', unknown>>;
        report.removed += removeLeftovers(record.folder);
      } catch {
        // An unreadable record names nothing to remove.
      }
      fs.rmSync(file, { force: true });
    }
    return report;
  }

  return { write, remove, leftovers, removeLeftovers, reconcile };
}

export type JobRecords = ReturnType<typeof createJobRecords>;

export const newJobId = (): string => `j_${crypto.randomBytes(9).toString('hex')}`;
