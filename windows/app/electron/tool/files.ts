// The files the page has been given, by opaque id (SPEC 27.2). The page holds the id and never
// the path; the id means nothing outside this window's session. An id is made only from what the
// person gave the app: the open dialog, a dropped file or a file opened with the app. Plain
// Node, so the tests drive it without Electron.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import type { FileId } from '../../src/bridge.ts';

export type FileKind = 'audio' | 'image' | 'output';

/** SPEC 7: what the open dialog offers and what a drop sorts by. */
export const AUDIO_EXTENSIONS: readonly string[] = ['mp3', 'm4a', 'aac', 'wav', 'aiff', 'aif', 'flac', 'caf'];
export const IMAGE_EXTENSIONS: readonly string[] = ['jpg', 'jpeg', 'png', 'heic', 'tif', 'tiff', 'webp', 'gif', 'bmp'];

/** The type of a file by its name alone, without reading it (SPEC 4a: sorted "by what it is, without reading its contents"). */
export function kindOfName(file: string): 'audio' | 'image' | null {
  const ext = path.extname(file).slice(1).toLowerCase();
  if (AUDIO_EXTENSIONS.includes(ext)) return 'audio';
  if (IMAGE_EXTENSIONS.includes(ext)) return 'image';
  return null;
}

export function createFileRegistry() {
  const files = new Map<FileId, { kind: FileKind; file: string }>();
  return {
    add(kind: FileKind, file: string): FileId {
      const id = `f_${crypto.randomBytes(9).toString('hex')}`;
      files.set(id, { kind, file });
      return id;
    },
    /** The path for an id of this kind, or null (an id that was released, never made, or of another kind). */
    get(id: unknown, kind: FileKind): string | null {
      const entry = typeof id === 'string' ? files.get(id) : undefined;
      return entry && entry.kind === kind ? entry.file : null;
    },
    release(ids: unknown): FileId[] {
      const released: FileId[] = [];
      if (!Array.isArray(ids)) return released;
      for (const id of ids) {
        if (typeof id === 'string' && files.delete(id)) released.push(id);
      }
      return released;
    },
    get size(): number {
      return files.size;
    },
  };
}

export type FileRegistry = ReturnType<typeof createFileRegistry>;

/** SPEC 4a, judged from the items' types alone (the order the Mac app judges them in). */
export type DropJudgement = { ok: true; audio: string | null; image: string | null } | { ok: false; reason: 'more-audio' | 'more-images' | 'too-many' | 'folder' | 'unsupported' };

export function judgeDrop(paths: unknown): DropJudgement {
  const list = Array.isArray(paths) ? paths.filter((p): p is string => typeof p === 'string') : [];
  if (list.length === 0 || list.length !== (Array.isArray(paths) ? paths.length : 0) || list.some((p) => !path.isAbsolute(p))) return { ok: false, reason: 'unsupported' };
  const isFolder = (p: string): boolean => {
    try {
      return fs.statSync(p).isDirectory();
    } catch {
      return false;
    }
  };
  if (list.some(isFolder)) return { ok: false, reason: 'folder' };
  if (list.length > 2) return { ok: false, reason: 'too-many' };
  const kinds = list.map(kindOfName);
  if (kinds.includes(null)) return { ok: false, reason: 'unsupported' };
  const audio = list.filter((_, i) => kinds[i] === 'audio');
  const image = list.filter((_, i) => kinds[i] === 'image');
  if (audio.length > 1) return { ok: false, reason: 'more-audio' };
  if (image.length > 1) return { ok: false, reason: 'more-images' };
  return { ok: true, audio: audio[0] ?? null, image: image[0] ?? null };
}
