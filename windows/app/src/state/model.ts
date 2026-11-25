// What the window knows, as plain data (src/state/app.ts holds it and changes it; src/state/status.ts
// turns it into the status bar's words). Types and small pure rules only, so the tests run it.
import type { AudioInfo, Codec, EncoderName, EncoderReport, FileId, ImageInfo, MakeDone, Stage, ToolStatus } from '../bridge.ts';
import type { Crop, Shape, Tier } from './frame.ts';

export type { Crop, Shape, Tier };

/** The picture of the image as the video will see it (`song2vid preview`). */
export type PreviewState =
  | { imageId: FileId; status: 'loading' }
  | { imageId: FileId; status: 'ready'; src: string; width: number; height: number }
  | { imageId: FileId; status: 'failed'; code: string };

export type JobView =
  | { phase: 'idle' }
  /** Make Video was pressed; the save dialog is open, or the tool has been asked and has not answered yet. */
  | { phase: 'starting' }
  | {
      phase: 'running';
      /** Null until the shell says which job this is. */
      jobId: string | null;
      stage: Stage;
      percent: number | null;
      /** Shown only once encoding has run 1 s and passed 5% (SPEC 27.4). */
      remaining: { seconds: number; at: number } | null;
      encoder: EncoderName | null;
      stalled: boolean;
      /** Cancel was pressed: "Cancelling", until the tool exits. */
      cancelling: boolean;
    }
  | { phase: 'cancelled' }
  | { phase: 'done'; result: MakeDone };

/** A failure the status bar shows, with the words and the filled button its code asks for. */
export interface FailureView {
  code: string;
  /** Developer text, copied by Copy Details and never shown. */
  details: string;
  /** The same failure with the same inputs twice in a row (premium bar rule 69). */
  again: boolean;
}

/** The question a drop asks when it would replace something (SPEC 4a). */
export interface ReplaceQuestion {
  title: string;
  /** What is there now and what was dropped, one line each. */
  lines: { now: string; dropped: string }[];
  ifReplaced: Slots;
  ifKept: Slots;
}

export interface Slots {
  audio: AudioInfo | null;
  image: ImageInfo | null;
}

export interface AppState {
  tool: ToolStatus;
  encoders: EncoderReport | null;
  audio: AudioInfo | null;
  image: ImageInfo | null;
  shape: Shape;
  tier: Tier;
  codec: Codec;
  /** What was last chosen and saved, even when this computer cannot make it. */
  savedCodec: Codec;
  crop: Crop;
  preview: PreviewState | null;
  job: JobView;
  failure: FailureView | null;
  /** A message that stays for a few seconds ("Wait for the current video to finish."). */
  notice: string | null;
  replace: ReplaceQuestion | null;
  /** A valid drop is held over the window (the highlight). */
  dragging: boolean;
}

export const jobBusy = (job: JobView): boolean => job.phase === 'starting' || job.phase === 'running';

/** The codec the picker starts on: the remembered one, unless this computer cannot make it (SPEC 23). */
export function startingCodec(saved: Codec, encoders: EncoderReport | null): Codec {
  return saved === 'hevc' && encoders !== null && !encoders.hevc.available ? 'h264' : saved;
}
