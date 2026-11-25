// What a drop does to the two slots (SPEC 4a), as the Mac app's DropHandler decides it: an empty
// slot is filled at once; a filled slot asks first (Replace, or Keep Current, the default). The
// shell has already judged the files and checked them; this only decides. Plain TypeScript.
import type { AudioInfo, FileId, ImageInfo } from '../bridge.ts';
import { clock, dimensions } from './words.ts';
import type { ReplaceQuestion, Slots } from './model.ts';

const audioSummary = (audio: AudioInfo): string => `${audio.name}, ${clock(audio.durationSeconds)}`;
const imageSummary = (image: ImageInfo): string => `${image.name}, ${dimensions(image.width, image.height)}`;

export type DropDecision = { kind: 'apply'; slots: Slots } | { kind: 'ask'; question: ReplaceQuestion };

/** What to do with a dropped song and image, given what is loaded now. */
export function decideDrop(current: Slots, dropped: Slots): DropDecision {
  const ifReplaced: Slots = { audio: dropped.audio ?? current.audio, image: dropped.image ?? current.image };
  const ifKept: Slots = { ...current };
  const nouns: string[] = [];
  const lines: ReplaceQuestion['lines'] = [];
  if (dropped.audio) {
    if (current.audio) {
      nouns.push('song');
      lines.push({ now: `Song now: ${audioSummary(current.audio)}`, dropped: `Dropped song: ${audioSummary(dropped.audio)}` });
    } else ifKept.audio = dropped.audio;
  }
  if (dropped.image) {
    if (current.image) {
      nouns.push('image');
      lines.push({ now: `Image now: ${imageSummary(current.image)}`, dropped: `Dropped image: ${imageSummary(dropped.image)}` });
    } else ifKept.image = dropped.image;
  }
  if (nouns.length === 0) return { kind: 'apply', slots: ifReplaced };
  return { kind: 'ask', question: { title: `Replace the current ${nouns.join(' and ')}?`, lines, ifReplaced, ifKept } };
}

/** The ids that are held by neither the slots in use nor the ones the page has put aside: free them (the shell keeps no id the page will not use). */
export function idsToRelease(candidates: readonly (AudioInfo | ImageInfo | null)[], keeping: Slots): FileId[] {
  const kept = new Set([keeping.audio?.id, keeping.image?.id].filter((id): id is FileId => id !== undefined));
  return [...new Set(candidates.flatMap((file) => (file && !kept.has(file.id) ? [file.id] : [])))];
}
