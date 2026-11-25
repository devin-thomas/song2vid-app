// Scripted workload run inside the page by --qa-bench. No OS input is sent.
// Phases: the crop moved by the keyboard (8 s), the Frame Shape and the Codec chosen in turn (4 s), the command palette opened and closed (2.4 s).
// It waits 30 s first so the harness can take its launch and idle readings.
// Song2Vid has no list and no text field, so the starter's list-scroll and typing phases do not
// apply (rules 25, 26, 27, 29, 41 are N/A). The crop and the pickers are what the window animates.
//
// The crop needs an image. A launch that carries --qa-pick-audio, --qa-pick-image and (for a
// make) --qa-pick-save has the shell answer the file dialogs (electron/tool/qa-picks.ts), and this
// script asks for the files with Ctrl+O and Ctrl+Shift+O as a person would. Without them there is no
// image: the crop phase is skipped and says so in `notes`.
//
// JavaScript on purpose: the file's text is the expression the page evaluates (electron/qa.ts
// reads it and passes it to executeJavaScript, and measure/run.py names this file), so it cannot
// be a module or need a build. Its types are checked with the page's (tsconfig.json, checkJs).
(async () => {
  /** @param {number} ms */
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  /** @returns {Promise<number>} */
  const frame = () => new Promise((r) => requestAnimationFrame(r));
  /** @param {string} name @param {number[]} gaps */
  const stats = (name, gaps) => {
    const s = gaps.slice().sort((a, b) => a - b);
    /** @param {number} p */
    const at = (p) => s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))] ?? 0;
    const period = s.length ? at(50) : 0;
    return { name, frames: s.length, p50: +at(50).toFixed(2), p99: +at(99).toFixed(2), max: +(s[s.length - 1] ?? 0).toFixed(2), late: s.filter((g) => g > 1.5 * period).length };
  };
  /** @param {string} name @param {number} ms @param {(t: number) => void} step */
  const timed = async (name, ms, step) => {
    /** @type {number[]} */
    const gaps = []; let last = performance.now(); const end = last + ms;
    while (performance.now() < end) { const t = await frame(); gaps.push(t - last); last = t; step(t); }
    return stats(name, gaps);
  };
  /** @param {string} key @param {Record<string, boolean>} [mods] @param {EventTarget} [target] */
  const press = (key, mods = {}, target = window) => target.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true, ...mods }));
  /** @param {string} selector @param {number} ms */
  const waitFor = async (selector, ms) => { const end = Date.now() + ms; while (Date.now() < end) { const el = document.querySelector(selector); if (el) return el; await sleep(100); } return null; };
  /** @type {string[]} */
  const notes = [];
  /** @type {ReturnType<typeof stats>[]} */
  const phases = [];
  await sleep(30000);
  const t0 = Date.now();

  // Ask for the files as a person does, when the launch can answer the dialogs.
  if (!document.querySelector('[data-file="audio"]')) press('o', { ctrlKey: true });
  await waitFor('[data-file="audio"]', 4000);
  if (!document.querySelector('[data-file="image"]')) press('O', { ctrlKey: true, shiftKey: true });
  await waitFor('[data-preview-state="ready"]', 6000);

  // 1. the crop: arrow keys on the slider, as a held key repeats (needs an image that crops in 1:1)
  const square = document.querySelector('[data-group="shape"] [data-value="1:1"]');
  if (square instanceof HTMLElement && document.querySelector('[data-file="image"]')) {
    square.click();
    await sleep(200);
    const slider = document.querySelector('[role="slider"][aria-label="Crop position"]');
    if (slider instanceof HTMLElement) {
      slider.focus();
      let dir = 1;
      let n = 0;
      phases.push(await timed('crop-nudge', 8000, () => {
        n += 1;
        if (n % 2) return; // a key every other frame
        press(dir > 0 ? 'ArrowLeft' : 'ArrowRight', {}, slider);
        if (n % 40 === 0) dir = -dir;
      }));
    } else notes.push('the image does not crop in 1:1: no crop phase');
  } else notes.push('no image was chosen (no --qa-pick-image): no crop phase');

  // 2. the Frame Shape and the Codec, chosen in turn with their arrow keys
  const pickers = ['shape', 'codec'].map((g) => `[data-group="${g}"]`);
  if (document.querySelector(pickers[0] ?? '')) {
    let i = 0;
    phases.push(await timed('pickers', 4000, () => {
      i += 1;
      if (i % 6) return;
      const active = document.querySelector(`${pickers[(i / 6) % pickers.length]} [aria-checked="true"]`);
      if (active instanceof HTMLElement) press('ArrowRight', {}, active);
    }));
  } else notes.push('no pickers');

  // 3. command palette open and close
  let pal = 0; let next = 0;
  phases.push(await timed('command-palette', 2400, (t) => {
    if (t < next) return;
    next = t + 600; pal += 1;
    const open = pal % 2 === 1;
    const target = open ? window : (document.activeElement ?? document);
    target.dispatchEvent(new KeyboardEvent('keydown', { key: open ? 'k' : 'Escape', code: open ? 'KeyK' : 'Escape', ctrlKey: open, bubbles: true }));
  }));
  (document.activeElement ?? document).dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', bubbles: true }));
  return { seconds: (Date.now() - t0) / 1000, phases, notes };
})()
