// The app's small saved preferences, its two links and the notices text, as plain Node: no
// Electron import, so test/app-data.test.ts runs it. main.ts wires it to the channels
// `app:preferences`, `app:open-link` and `app:notices` and to `Bootstrap.preferences`
// (src/bridge.ts, docs/BRIDGE.md).
//
// What is saved (SPEC 27.7): the Codec here; the theme and the window's size and place in
// window.json (main.ts); the last save folder in tool/destination.json (tool/service.ts).
// There is no settings window.
import fs from 'node:fs';
import path from 'node:path';
import type { Codec, Preferences } from '../src/bridge.ts';

export const DEFAULT_PREFERENCES: Preferences = { codec: 'h264' };

const file = (dataDir: string): string => path.join(dataDir, 'preferences.json');

/** What was saved. A missing, damaged or unknown value gives the default for that value. */
export function readPreferences(dataDir: string): Preferences {
  try {
    const saved: unknown = JSON.parse(fs.readFileSync(file(dataDir), 'utf8'));
    const codec = typeof saved === 'object' && saved !== null ? (saved as Record<string, unknown>)['codec'] : undefined;
    return { codec: codec === 'hevc' || codec === 'h264' ? (codec as Codec) : DEFAULT_PREFERENCES.codec };
  } catch {
    return { ...DEFAULT_PREFERENCES };
  }
}

/**
 * Remember what the person chose. The page is not trusted with the shape of the update: only a
 * known key with a known value is kept. Written the same moment, atomically, so a kill right
 * after the choice loses nothing. Returns what is saved now.
 */
export function writePreferences(dataDir: string, update: unknown): Preferences {
  const now = readPreferences(dataDir);
  const codec = typeof update === 'object' && update !== null ? (update as Record<string, unknown>)['codec'] : undefined;
  if (codec !== 'h264' && codec !== 'hevc') return now;
  const next: Preferences = { ...now, codec };
  try {
    fs.mkdirSync(dataDir, { recursive: true });
    fs.writeFileSync(`${file(dataDir)}.tmp`, JSON.stringify(next));
    fs.renameSync(`${file(dataDir)}.tmp`, file(dataDir));
  } catch {
    // The choice still applies for this run; it is a convenience to remember it.
  }
  return next;
}

/** The two places `openLink` can open, fixed here: the page names one, never an address. */
export const LINKS: Record<'repository' | 'download-page', string> = {
  repository: 'https://github.com/devin-thomas/song2vid-app',
  'download-page': 'https://song2vid.pages.dev/',
};

/** The address for a name the page sent, or null for anything else. */
export const linkFor = (which: unknown): string | null => (which === 'repository' || which === 'download-page' ? LINKS[which] : null);

/** THIRD-PARTY-NOTICES.txt: in the packaged app beside the bundled programs, in development in third-party/. */
export function readNotices({ packaged, resourcesPath, projectDir }: { packaged: boolean; resourcesPath: string; projectDir: string }): string {
  const place = packaged ? path.join(resourcesPath, 'THIRD-PARTY-NOTICES.txt') : path.join(projectDir, 'third-party', 'THIRD-PARTY-NOTICES.txt');
  try {
    return fs.readFileSync(place, 'utf8');
  } catch {
    return 'The notices file could not be read. Reinstall Song2Vid to restore it.';
  }
}
