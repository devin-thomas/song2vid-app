// What the page may ask of the desktop shell, for Song2Vid for Windows (SPEC 27.2 to 27.7).
// electron/preload.ts is the other half; the two must list the same functions
// (test/preload.test.ts). The stand-in in src/bridge.fake.ts implements it for a plain
// browser, so the headless audit and the screenshots reach every state without Electron or
// the tool. This file is one of the seam files written before any builder starts (the
// others are docs/BRIDGE.md, docs/JOURNEYS.md and shortcuts.json; the tool's contract is
// SPEC sections 14 and 24); neither side changes it alone, and a change is a recorded
// decision in docs/DECISIONS.md.
//
// The page never sees a file path, an executable or a flag. A file is named by an opaque
// id the shell keeps, filled only from the system's open dialog, a dropped file or a file
// opened with the app. The tool's own words arrive only as `details`, which the page
// copies on request and never shows.

/** The system, as the shell reports it. The page never guesses it from the user agent. */
export type Platform = 'windows' | 'macos' | 'linux';

/** An opaque name for a file the shell holds. It means nothing outside this window's session. */
export type FileId = string;

export type FrameShape = '16:9' | '9:16' | '1:1' | '4:3' | 'original';
/** The size tier of the short side (GLOSSARY: Resolution). Original has none. */
export type Resolution = '480p' | '1080p' | '2160p';
/** GLOSSARY: Codec. */
export type Codec = 'h264' | 'hevc';
/** SPEC 24.2: which Encoder made, or will make, the video. The page turns these into the human names ("NVIDIA encoder"). */
export type EncoderName = 'nvenc' | 'media_foundation' | 'software' | 'apple';
/** SPEC 14.5: the stages the tool reports, in order. */
export type Stage = 'checking' | 'preparing' | 'encoding' | 'finishing';

export interface ToolStatus {
  /** `damaged` covers a missing, unreadable or wrong-version tool: one blocking state (SPEC 27.5). */
  state: 'ready' | 'damaged' | 'checking';
  /** A shell code from docs/BRIDGE.md when the tool is not ready. */
  code: string | null;
  /** Developer text: copied by "Copy details", never shown. */
  details: string | null;
}

/** What `song2vid encoders --json` reports (SPEC 24.2), as it stands now. */
export interface EncoderReport {
  h264: { available: boolean; encoder: EncoderName | null };
  hevc: { available: boolean; encoder: EncoderName | null };
}

/** A failure. `code` is a tool error code (SPEC 14.6, 24.6) or a shell code; any code the page does not know gets the generic sentence. */
export interface Problem {
  code: string;
  /** Developer text: copied by "Copy details", never shown. */
  details: string;
}

export interface AudioInfo {
  id: FileId;
  /** The file name, with no folder. */
  name: string;
  durationSeconds: number;
}

/** One row of the tool's `check` table (SPEC 14.3): the output size, the placement and whether the image would be enlarged. */
export interface FrameRow {
  shape: FrameShape;
  /** null for Original. */
  resolution: Resolution | null;
  /** null when Original is "too small" (a side under 16 px). */
  width: number | null;
  height: number | null;
  /** null when the shape is unusable. */
  placement: 'fit' | 'crop' | null;
  enlarged: boolean;
}

export interface ImageInfo {
  id: FileId;
  name: string;
  /** Pixel size after the orientation tag. */
  width: number;
  height: number;
  frames: FrameRow[];
}

/** A file the open dialog was asked for: chosen, dismissed, or chosen but not usable. Nothing changes unless `chosen`. */
export type ChooseResult<T> = { status: 'chosen'; file: T } | { status: 'dismissed' } | { status: 'unusable'; problem: Problem };

/** SPEC 4a: what a drop is, judged by the shell before the page changes anything. */
export type DropResult =
  | {
      status: 'ok';
      /** The dropped song, checked as a chosen file is; null when none was dropped. */
      audio: AudioInfo | null;
      image: ImageInfo | null;
    }
  | {
      status: 'rejected';
      /** `more-audio`, `more-images`, `too-many`, `folder`, `unsupported`, or `unreadable` (a file that fails the section 7 check). */
      reason: 'more-audio' | 'more-images' | 'too-many' | 'folder' | 'unsupported' | 'unreadable';
    };

/** The image as the video will see it (SPEC 24.3), for the preview. `src` is an address the page's own policy allows. */
export type PreviewResult = { status: 'ready'; src: string; width: number; height: number } | { status: 'failed'; problem: Problem };

export interface MakeRequest {
  audioId: FileId;
  imageId: FileId;
  shape: FrameShape;
  /** null when the shape is Original. */
  resolution: Resolution | null;
  /** Fractions 0 to 1, only for 1:1 and 4:3; null otherwise. */
  crop: { h: number; v: number } | null;
  codec: Codec;
  /** `ask` opens the save dialog. `same` is Try Again: the destination chosen last time, with no dialog. */
  destination: 'ask' | 'same';
}

export type MakeStart =
  | { status: 'started'; jobId: string }
  /** The save dialog was dismissed: nothing started, nothing changes. */
  | { status: 'dismissed' }
  /** A video is already being made. */
  | { status: 'busy' };

/** What a finished video is (SPEC 27.4 step 3). The page shows the name, `where`, the Codec, the Encoder and the length. */
export interface MakeDone {
  /** For Show in File Explorer. */
  outputId: FileId;
  fileName: string;
  /** The saved folder's own name only ("Videos"), never a path. */
  where: string;
  width: number;
  height: number;
  durationSeconds: number;
  bytes: number;
  codec: Codec;
  encoder: EncoderName;
  /** True when the first Encoder failed before its first frame and the next one made the video (SPEC 23). */
  encoderFallback: boolean;
}

export type JobUpdate =
  | {
      jobId: string;
      state: 'running';
      stage: Stage;
      /** 0 to 100, or null until the tool knows it. */
      percent: number | null;
      /** Seconds since the job started, as the tool counts. The page shows time left once encoding has run 1 s and passed 5%. */
      elapsedSeconds: number;
      remainingSeconds: number | null;
      /** Known from the encoding stage on. */
      encoder: EncoderName | null;
      /** No line from the tool for 30 s: the page shows "Still working…" with Cancel. Nothing is killed for it. */
      stalled: boolean;
    }
  | { jobId: string; state: 'done'; result: MakeDone }
  | { jobId: string; state: 'cancelled' }
  | { jobId: string; state: 'failed'; problem: Problem };

/** What is remembered between runs and read before first paint (SPEC 27.7). The last save folder and the window's size and place are the shell's own and never reach the page. */
export interface Preferences {
  /** H.264 until the person chooses HEVC. It stays HEVC when this computer cannot make it; the page starts on H.264 then. */
  codec: Codec;
}

export interface Bootstrap {
  stored: Record<string, string>;
  platform: Platform;
  preferences: Preferences;
  about: { appVersion: string; dataDir: string } | null;
  tool: ToolStatus;
  /** The answer cached from the last run, so the Codec picker is ready at once; null when there is none. A fresh one arrives through onEncoders. */
  encoders: EncoderReport | null;
}

export interface DesktopBridge {
  bootstrap(): Promise<Bootstrap>;
  setTheme(theme: 'light' | 'dark'): void;
  saveState(key: string, json: string): void;
  setPreferences(update: Partial<Preferences>): void;

  chooseAudio(): Promise<ChooseResult<AudioInfo>>;
  chooseImage(): Promise<ChooseResult<ImageInfo>>;
  /** The files of a drop. The shell resolves their places itself; the page never gets them. */
  dropFiles(files: File[]): Promise<DropResult>;
  /** A file or files opened with the app (a second launch, or Open with): judged as a drop is. */
  onFilesOpened(listener: (result: DropResult) => void): () => void;
  /** Frees ids the page will not use: a dropped file the person kept the current one over. */
  releaseFiles(ids: FileId[]): void;
  previewImage(imageId: FileId): Promise<PreviewResult>;
  onEncoders(listener: (report: EncoderReport) => void): () => void;

  makeVideo(request: MakeRequest): Promise<MakeStart>;
  cancelJob(jobId: string): void;
  onJob(listener: (update: JobUpdate) => void): () => void;
  showInFolder(outputId: FileId): void;

  openLink(which: 'repository' | 'download-page'): void;
  notices(): Promise<string>;
  onMenuCommand(listener: (command: string) => void): () => void;
  setMenuState(enabled: Record<string, boolean>): void;
}

declare global {
  interface Window {
    desktop?: DesktopBridge;
  }
}
