// Every state the window can be in, as steps on a fixture of the stand-in bridge
// (src/bridge.fake.ts). One list for the audit (qa/audit.ts: axe, layout at four sizes, focus,
// language, forced colours) and the pictures (qa/shots.ts, qa/visual.ts), so a state added here is
// checked and photographed in both. A state names the fixture it opens on, extra address options
// (`image=small`), the steps that reach it, and whether it is one of the CORE states the
// secondary picture sets (every system's labels, forced colours, 200% zoom) are taken of.
//
// SPEC 27.5's error table is here in full: one state per code, and one for a code the page does
// not know. The Replace question, the drop highlight and a refused drop are states too.
import type { Page } from 'playwright-core';

/** "Control" on Windows and Linux, "Meta" on macOS: the key family the page was told it runs on. */
export type Mod = 'Control' | 'Meta';

export interface State {
  fixture: string;
  /** More of the address's fragment, such as `image=small`. */
  extra?: string;
  run: (page: Page, mod: Mod) => Promise<void>;
  /** Taken in the secondary picture sets as well as the main one. */
  core?: boolean;
  /** A picture only: the audit does not check it (the dimmed title of an inactive window is meant to be dim). */
  picture?: boolean;
}

// ---- steps ------------------------------------------------------------------------------

export const chooseAudio = async (page: Page, mod: Mod = 'Control'): Promise<void> => {
  await page.keyboard.press(`${mod}+o`);
  await page.waitForSelector('[data-file="audio"]');
};

export const chooseImage = async (page: Page, mod: Mod = 'Control'): Promise<void> => {
  await page.keyboard.press(`${mod}+Shift+o`);
  await page.waitForSelector('[data-file="image"]');
  // The picture of the image: drawn, or said to have failed.
  await page.waitForSelector('[data-preview-state="ready"], [data-preview-state="failed"]');
};

/** A song and an image, chosen as a person does: Ctrl+O and Ctrl+Shift+O. */
export async function fill(page: Page, mod: Mod = 'Control'): Promise<void> {
  await chooseAudio(page, mod);
  await chooseImage(page, mod);
}

export const pickShape = async (page: Page, shape: string): Promise<void> => {
  await page.locator(`[data-group="shape"] [data-value="${shape}"]`).click();
};

export const pickCodec = async (page: Page, codec: 'h264' | 'hevc'): Promise<void> => {
  await page.locator(`[data-group="codec"] [data-value="${codec}"]`).click();
};

export const make = async (page: Page, mod: Mod = 'Control'): Promise<void> => {
  await page.keyboard.press(`${mod}+Enter`);
};

export const waitStatus = (page: Page, kind: string, timeout = 5000): Promise<unknown> => page.waitForSelector(`[data-status-bar][data-job="${kind}"]`, { timeout });

export const openPalette = async (page: Page, mod: Mod = 'Control'): Promise<void> => {
  await page.keyboard.press(`${mod}+k`);
  await page.waitForSelector('.palette');
};

/** Files dropped on the window, as the page receives a real drop: the events a browser sends. */
export async function drop(page: Page, files: { name: string; type: string }[], { phase = 'drop' }: { phase?: 'over' | 'drop' } = {}): Promise<void> {
  await page.evaluate(
    ({ list, until }) => {
      const transfer = new DataTransfer();
      for (const f of list) transfer.items.add(new File(['x'], f.name, { type: f.type }));
      const target = document.querySelector('.app') as Element;
      const send = (type: string) => target.dispatchEvent(new DragEvent(type, { dataTransfer: transfer, bubbles: true, cancelable: true }));
      send('dragenter');
      send('dragover');
      if (until === 'drop') send('drop');
    },
    { list: files, until: phase },
  );
}

export const SONG = { name: 'New Song.mp3', type: 'audio/mpeg' };
export const PICTURE = { name: 'New Cover.png', type: 'image/png' };

/** The page's value text of the Crop position control. */
export const cropValue = (page: Page): Promise<string | null> => page.locator('[role="slider"][aria-label="Crop position"]').getAttribute('aria-valuetext');

/** Shapes: choose both files, then the Frame Shape. */
const shaped = (shape: string) => async (page: Page, mod: Mod) => {
  await fill(page, mod);
  await pickShape(page, shape);
};

const failing = (code: string): State => ({
  fixture: `make-fail-${code}`,
  run: async (page, mod) => {
    await fill(page, mod);
    await make(page, mod);
    await waitStatus(page, 'failure');
  },
});

/** The error table of SPEC 27.5, by tool code. */
export const ERROR_CODES = ['audio_not_found', 'image_not_found', 'audio_unreadable', 'image_unreadable', 'image_too_small', 'codec_unavailable', 'output_not_writable', 'disk_full', 'output_in_use', 'output_exists', 'export_failed'] as const;

export const STATES: Record<string, State> = {
  '01-empty': { fixture: 'default', core: true, run: async () => {} },
  '02-audio-only': { fixture: 'default', run: async (page, mod) => chooseAudio(page, mod) },
  '03-image-only': { fixture: 'default', run: async (page, mod) => chooseImage(page, mod) },
  '04-both': { fixture: 'default', core: true, run: async (page, mod) => fill(page, mod) },
  '05-shape-9x16': { fixture: 'default', run: shaped('9:16') },
  '06-shape-1x1': { fixture: 'default', core: true, run: shaped('1:1') },
  '07-shape-1x1-moved': {
    fixture: 'default',
    run: async (page, mod) => {
      await shaped('1:1')(page, mod);
      await page.locator('[role="slider"]').focus();
      for (let i = 0; i < 4; i++) await page.keyboard.press('ArrowLeft');
    },
  },
  '08-shape-4x3': { fixture: 'default', run: shaped('4:3') },
  '09-shape-original': { fixture: 'default', run: shaped('original') },
  '10-hevc-chosen': {
    fixture: 'default',
    run: async (page, mod) => {
      await fill(page, mod);
      await pickCodec(page, 'hevc');
    },
  },
  '11-hevc-disabled': { fixture: 'no-hevc', core: true, run: async (page, mod) => fill(page, mod) },
  '12-small-image-enlarged': { fixture: 'default', extra: 'image=small', run: async (page, mod) => fill(page, mod) },
  '13-original-too-small': { fixture: 'default', extra: 'image=tiny', run: shaped('original') },
  '14-long-names': { fixture: 'default', extra: 'image=huge', run: async (page, mod) => fill(page, mod) },
  '15-preview-loading': {
    fixture: 'default',
    extra: 'preview=slow',
    run: async (page, mod) => {
      await chooseAudio(page, mod);
      await page.keyboard.press(`${mod}+Shift+o`);
      await page.waitForSelector('[data-file="image"]');
      await page.waitForTimeout(450); // past the 150 ms before a wait is shown
    },
  },
  '16-preview-failed': { fixture: 'default', extra: 'preview=failed', run: async (page, mod) => fill(page, mod) },
  '17-making': {
    fixture: 'make-hold',
    core: true,
    run: async (page, mod) => {
      await fill(page, mod);
      await make(page, mod);
      await page.waitForSelector('[data-status-bar][data-job="running"] [role="progressbar"][aria-valuenow="40"]');
    },
  },
  '18-making-early': {
    fixture: 'make-hold-early',
    run: async (page, mod) => {
      await fill(page, mod);
      await make(page, mod);
      await waitStatus(page, 'running');
    },
  },
  '19-making-stalled': {
    fixture: 'make-stalled',
    run: async (page, mod) => {
      await fill(page, mod);
      await make(page, mod);
      await waitStatus(page, 'stalled');
    },
  },
  '20-cancelling': {
    fixture: 'make-ignore-cancel',
    run: async (page, mod) => {
      await fill(page, mod);
      await make(page, mod);
      await waitStatus(page, 'running');
      await page.keyboard.press('Escape');
      await waitStatus(page, 'cancelling');
    },
  },
  '21-cancelled': {
    fixture: 'make-slow-cancel',
    core: true,
    run: async (page, mod) => {
      await fill(page, mod);
      await make(page, mod);
      await waitStatus(page, 'running');
      await page.keyboard.press('Escape');
      await waitStatus(page, 'cancelled');
    },
  },
  '22-done': {
    fixture: 'make-done',
    core: true,
    run: async (page, mod) => {
      await fill(page, mod);
      await make(page, mod);
      await waitStatus(page, 'done');
    },
  },
  ...Object.fromEntries(ERROR_CODES.map((code, i): [string, State] => [`${23 + i}-error-${code.replaceAll('_', '-')}`, { ...failing(code), core: code === 'output_exists' }])),
  '34-error-unknown-code': failing('something_new'),
  '35-error-repeated': {
    fixture: 'make-fail-output_in_use',
    core: true,
    run: async (page, mod) => {
      await fill(page, mod);
      await make(page, mod);
      await waitStatus(page, 'failure');
      await page.locator('[data-status-bar] [data-action="try-again"]').click();
      await page.waitForFunction(() => /failed again/.test(document.querySelector('[data-status-text]')?.textContent ?? ''), null, { timeout: 5000 });
    },
  },
  '36-choose-audio-unreadable': {
    fixture: 'choose-fail-audio_unreadable',
    run: async (page, mod) => {
      await page.keyboard.press(`${mod}+o`);
      await waitStatus(page, 'failure');
    },
  },
  '37-choose-image-too-small': {
    fixture: 'choose-fail-image_too_small',
    run: async (page, mod) => {
      await page.keyboard.press(`${mod}+Shift+o`);
      await waitStatus(page, 'failure');
    },
  },
  '38-tool-missing': { fixture: 'tool-damaged', core: true, run: async () => {} },
  '39-tool-turns-missing': {
    fixture: 'tool-damaged-late',
    run: async (page, mod) => {
      await fill(page, mod);
      await page.waitForSelector('[data-blocked]', { timeout: 5000 });
    },
  },
  '40-palette': {
    fixture: 'default',
    core: true,
    run: async (page, mod) => {
      await fill(page, mod);
      await openPalette(page, mod);
    },
  },
  '41-palette-no-match': {
    fixture: 'default',
    run: async (page, mod) => {
      await openPalette(page, mod);
      await page.keyboard.type('zzq');
    },
  },
  '42-about': {
    fixture: 'default',
    core: true,
    run: async (page, mod) => {
      await openPalette(page, mod);
      await page.keyboard.type('about');
      await page.keyboard.press('Enter');
      await page.waitForSelector('[data-about]');
      await page.waitForFunction(() => /FFmpeg/.test(document.querySelector('[data-notices]')?.textContent ?? ''));
    },
  },
  '43-replace-question': {
    fixture: 'default',
    run: async (page, mod) => {
      await fill(page, mod);
      await drop(page, [SONG, PICTURE]);
      await page.waitForSelector('[data-replace]');
    },
  },
  '44-drop-highlight': {
    fixture: 'default',
    run: async (page, mod) => {
      await fill(page, mod);
      await drop(page, [SONG], { phase: 'over' });
      await page.waitForSelector('.drop-veil[data-active="true"]');
    },
  },
  '45-drop-refused': {
    fixture: 'default',
    run: async (page) => {
      await drop(page, [SONG, SONG]);
      await waitStatus(page, 'notice');
    },
  },
  '46-window-inactive': {
    fixture: 'default',
    picture: true,
    run: async (page, mod) => {
      await fill(page, mod);
      await page.evaluate(() => window.dispatchEvent(new Event('blur')));
    },
  },
};

/** The states the audit checks: every state but the pictures only. */
export const AUDITED: string[] = Object.entries(STATES).filter(([, state]) => !state.picture).map(([name]) => name);
