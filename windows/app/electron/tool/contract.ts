// What the shell knows about the tool's command contract, in one place for the shell and the
// tests. The contract itself is the repository's SPEC.md, not this file: section 14 (check, make,
// the options, the --json lines, the exit statuses and error codes), section 24 (--codec,
// encoders, preview, --cancel-on-eof, the added keys and codes, one-file check) and section 26.3
// (the temporary file). docs/TOOL-CONTRACT.md points at the same sections. No Electron here and
// no process: the argument lists and the readers of each answer are pure, so a recorded line
// replays to the same value on every system.
//
// A reader returns null when a line lacks what the page needs. The adapter then ends the call
// as `export_failed` with the fault TOOL_PROTOCOL (SPEC 27.6); it never invents a value.
import path from 'node:path';
import type { Codec, EncoderName, EncoderReport, FrameRow, FrameShape, Resolution, Stage } from '../../src/bridge.ts';

/** SPEC 14.5: every line says so. A different value is a tool from another contract. */
export const API_VERSION = '1';
/** SPEC 24.7: what `--version` prints. Any other answer is the wrong version. */
export const VERSION_LINE = 'song2vid 1.2.0';
/** SPEC 26.3: the temporary file the tool writes beside its output. Nothing else is ever removed. */
export const STAGING_NAME = /^\.song2vid-[0-9a-fA-F]{32}\.tmp$/;
/** Every job's own flags (SPEC 27.6): machine lines, and cancel by closing stdin (SPEC 24.4). */
export const JOB_FLAGS: readonly string[] = ['--json', '--cancel-on-eof'];

export const STAGES: readonly Stage[] = ['checking', 'preparing', 'encoding', 'finishing'];
export const ENCODERS: readonly EncoderName[] = ['nvenc', 'media_foundation', 'software', 'apple'];
export const SHAPES: readonly FrameShape[] = ['16:9', '9:16', '1:1', '4:3', 'original'];
export const RESOLUTIONS: readonly Resolution[] = ['480p', '1080p', '2160p'];
export const CODECS: readonly Codec[] = ['h264', 'hevc'];

/** SPEC 14.6 and 24.6: each published error code and its exit status. The list only grows. */
export const EXIT_STATUS: Readonly<Record<string, number>> = {
  audio_not_found: 1,
  image_not_found: 1,
  usage: 2,
  audio_unreadable: 3,
  image_unreadable: 3,
  image_too_small: 3,
  codec_unavailable: 3,
  output_exists: 4,
  output_not_writable: 4,
  output_not_mp4: 4,
  output_in_use: 4,
  disk_full: 4,
  export_failed: 5,
  network: 5,
  cancelled: 130,
};

/** A line the tool wrote, as far as the shell reads it. Unknown keys and types are ignored (SPEC 24.5). */
export interface Line {
  api_version?: unknown;
  type: string;
  [key: string]: unknown;
}

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value);
const isNumber = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value);
const oneOf = <T extends string>(list: readonly T[], value: unknown): T | null => (typeof value === 'string' && (list as readonly string[]).includes(value) ? (value as T) : null);

// ---- arguments ----------------------------------------------------------------

/** What `make` is asked for. Every path is absolute: no name can read as an option, and the tool never looks in the current folder. */
export interface MakeArgs {
  audio: string;
  image: string;
  output: string;
  shape: FrameShape;
  /** null for Original, which takes none (SPEC 14.2). */
  resolution: Resolution | null;
  /** Fractions 0 to 1, only for 1:1 and 4:3. */
  crop: { h: number; v: number } | null;
  codec: Codec;
  overwrite: boolean;
}

function absolute(file: string): string {
  if (!path.isAbsolute(file)) throw new Error('the adapter passes absolute paths only');
  return file;
}

const fraction = (value: number): string => String(Number(value.toFixed(4)));

/** `make <audio> <image> ...` with the job's flags (SPEC 14.2, 24.1, 24.4). */
export function makeArgs(a: MakeArgs): string[] {
  const args = ['make', absolute(a.audio), absolute(a.image), '--out', absolute(a.output), '--shape', a.shape];
  if (a.resolution) args.push('--resolution', a.resolution);
  if (a.crop) args.push('--crop', `${fraction(a.crop.h)},${fraction(a.crop.v)}`);
  args.push('--codec', a.codec);
  if (a.overwrite) args.push('--overwrite');
  return [...args, ...JOB_FLAGS];
}

/** `check <file>` (SPEC 24.8) or `check <audio> <image>` (SPEC 14.3). No cancel flag: it reads nothing from stdin. */
export const checkArgs = (files: string[]): string[] => ['check', ...files.map(absolute), '--json'];

/** `preview <image> --out <file.png> --overwrite` (SPEC 24.3). The output is the app's own cache file, so replacing is always right. */
export const previewArgs = (image: string, output: string): string[] => ['preview', absolute(image), '--out', absolute(output), '--overwrite', ...JOB_FLAGS];

export const encodersArgs = (): string[] => ['encoders', '--json'];
/** SPEC 27.6 names `--version --json`. The Mac command refuses `--json` there, so the adapter falls back to this. */
export const versionArgs = (json: boolean): string[] => (json ? ['--version', '--json'] : ['--version']);

// ---- readers --------------------------------------------------------------------

/** What `--version` printed: the line `song2vid X.Y.Z`, nothing more. */
export function readVersion(stdout: string): string | null {
  const match = /^(song2vid \d+\.\d+\.\d+)\r?\n?$/.exec(stdout);
  return match ? (match[1] ?? null) : null;
}

export interface AudioFacts {
  name: string;
  durationSeconds: number;
}
export interface ImageFacts {
  name: string;
  width: number;
  height: number;
  frames: FrameRow[];
}

/** One row of the `check` table (SPEC 14.3). A frame the image cannot make has null size and placement. */
function readFrame(value: unknown): FrameRow | null {
  if (!isRecord(value)) return null;
  const shape = oneOf(SHAPES, value['shape']);
  const resolution = value['resolution'] === null ? null : oneOf(RESOLUTIONS, value['resolution']);
  if (!shape || (resolution === null && value['resolution'] !== null)) return null;
  const width = value['width'] === null ? null : value['width'];
  const height = value['height'] === null ? null : value['height'];
  if ((width !== null && !isNumber(width)) || (height !== null && !isNumber(height))) return null;
  const placement = value['placement'] === null ? null : oneOf(['fit', 'crop'] as const, value['placement']);
  if (placement === null && value['placement'] !== null) return null;
  return { shape, resolution, width, height, placement, enlarged: value['enlarged'] === true };
}

/** The audio of a `check` result (one file or two). Null when the line has no usable audio. */
export function readAudio(line: Line): AudioFacts | null {
  const audio = line['audio'];
  if (!isRecord(audio) || typeof audio['name'] !== 'string' || !isNumber(audio['duration_seconds']) || audio['duration_seconds'] < 0) return null;
  return { name: audio['name'], durationSeconds: audio['duration_seconds'] };
}

/** The image and its output-size table of a `check` result. Null when the line has no usable image. */
export function readImage(line: Line): ImageFacts | null {
  const image = line['image'];
  const rows = line['frames'];
  if (!isRecord(image) || typeof image['name'] !== 'string' || !isNumber(image['width']) || !isNumber(image['height']) || !Array.isArray(rows)) return null;
  const frames = rows.map(readFrame);
  if (frames.some((frame) => frame === null)) return null;
  return { name: image['name'], width: image['width'], height: image['height'], frames: frames as FrameRow[] };
}

/** The `encoders` result (SPEC 24.2). An Encoder name from a newer tool reads as "available, name unknown". */
export function readEncoders(line: Line): EncoderReport | null {
  const codecs = line['codecs'];
  if (!isRecord(codecs)) return null;
  const one = (value: unknown): { available: boolean; encoder: EncoderName | null } | null => {
    if (!isRecord(value) || typeof value['available'] !== 'boolean') return null;
    return { available: value['available'], encoder: value['available'] ? oneOf(ENCODERS, value['encoder']) : null };
  };
  const h264 = one(codecs['h264']);
  const hevc = one(codecs['hevc']);
  return h264 && hevc ? { h264, hevc } : null;
}

export interface MadeFacts {
  name: string;
  width: number;
  height: number;
  durationSeconds: number;
  bytes: number;
  codec: Codec | null;
  encoder: EncoderName | null;
  encoderFallback: boolean;
}

/** The `make` result (SPEC 14.5, 24.5). `codec` and `encoder` are null when the line lacks them; the caller says what fills them. */
export function readMade(line: Line): MadeFacts | null {
  const output = line['output'];
  if (!isRecord(output) || typeof output['name'] !== 'string' || !isNumber(output['width']) || !isNumber(output['height']) || !isNumber(output['duration_seconds']) || !isNumber(output['bytes'])) return null;
  return {
    name: output['name'],
    width: output['width'],
    height: output['height'],
    durationSeconds: output['duration_seconds'],
    bytes: output['bytes'],
    codec: oneOf(CODECS, line['codec']),
    encoder: oneOf(ENCODERS, line['encoder']),
    encoderFallback: line['encoder_fallback'] === true,
  };
}

/** The `preview` result (SPEC 24.3): the written picture's size. */
export function readPreview(line: Line): { width: number; height: number } | null {
  const output = line['output'];
  if (!isRecord(output) || !isNumber(output['width']) || !isNumber(output['height'])) return null;
  return { width: output['width'], height: output['height'] };
}

/** A `progress` line (SPEC 14.5, 24.5), read as far as the shell uses it. Unknown stages are ignored. */
export interface ProgressFacts {
  stage: Stage | null;
  percent: number | null;
  elapsedSeconds: number | null;
  remainingSeconds: number | null;
  encoder: EncoderName | null;
}

export function readProgress(line: Line): ProgressFacts {
  return {
    stage: oneOf(STAGES, line['stage']),
    percent: isNumber(line['percent']) ? line['percent'] : null,
    elapsedSeconds: isNumber(line['elapsed_seconds']) ? line['elapsed_seconds'] : null,
    remainingSeconds: isNumber(line['remaining_seconds']) ? line['remaining_seconds'] : null,
    encoder: oneOf(ENCODERS, line['encoder']),
  };
}

/** The code and message of an `error` line. A line with neither is still an error, with the code UNKNOWN. */
export function readError(line: Line): { code: string; message: string } {
  const error = line['error'];
  const code = isRecord(error) && typeof error['code'] === 'string' && error['code'] ? error['code'] : 'UNKNOWN';
  return { code, message: isRecord(error) && typeof error['message'] === 'string' ? error['message'] : '' };
}
