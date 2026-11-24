// A development-only way to answer the app's own dialogs, so a run with no one to click (the
// headless runs, `--no-activate`, which never opens a dialog: D-010) can still choose files and
// a save place. A launch carries
//
//   --qa-pick-audio=<file>   the song the open dialog "chooses"
//   --qa-pick-image=<file>   the image the open dialog "chooses"
//   --qa-pick-save=<file>    the file the save dialog "chooses" (an existing file counts as the person confirming a replacement)
//
// Nothing opens, so nothing takes focus. The flags are read only when the app is not packaged
// (a shipped build never looks at its command line for them), and only a file that exists is
// given back, so a dialog never answers with a path the person did not have. The answers still go
// through the same service: ids, the one-file check, the save rules. Plain Node, tested in
// test/qa-picks.test.ts.
import fs from 'node:fs';

export interface QaPicks {
  audio: string | null;
  image: string | null;
  save: string | null;
}

const flag = (argv: readonly string[], name: string): string | null => {
  const hit = argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) || null : null;
};

/** The answers a development launch carries, or null when it carries none or the app is packaged. */
export function readQaPicks(argv: readonly string[], packaged: boolean): QaPicks | null {
  if (packaged) return null;
  const picks: QaPicks = { audio: flag(argv, 'qa-pick-audio'), image: flag(argv, 'qa-pick-image'), save: flag(argv, 'qa-pick-save') };
  return picks.audio || picks.image || picks.save ? picks : null;
}

/** What the open dialog answers: the named file when it exists, else "closed". */
export function answerOpen(picks: QaPicks | null, kind: 'audio' | 'image'): string | null {
  const file = picks?.[kind] ?? null;
  return file && fs.existsSync(file) ? file : null;
}

/** What the save dialog answers: the named file (it need not exist), else "closed". */
export const answerSave = (picks: QaPicks | null): string | null => picks?.save ?? null;
