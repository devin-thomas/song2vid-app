import { Tooltip } from '@base-ui/react/tooltip';
import { useEffect, useRef, useState } from 'react';
import type { DragEvent } from 'react';
import config from '../app.config.json';
import pkg from '../package.json';
import type { Bootstrap, DesktopBridge, Platform } from './bridge';
import { Choice } from './components/Choice';
import { FileName } from './components/FileName';
import { ScrollArea } from './components/ScrollArea';
import { CommandPalette, type Command } from './components/CommandPalette';
import { AboutDialog, ReplaceDialog } from './components/Dialogs';
import { Preview } from './components/Preview';
import { StatusBar } from './components/StatusBar';
import { TitleBar } from './components/TitleBar';
import { Kbd } from './components/ui';
import {
  cancel,
  canMake,
  chooseAudio,
  chooseImage,
  copyDetails,
  dropFiles,
  frameOf,
  makeVideo,
  openDownloadPage,
  originalSize,
  resetCrop,
  roomOf,
  say,
  setCodec,
  setDragging,
  setShape,
  setTier,
  showInFolder,
  useApp,
} from './state/app';
import { SHAPES, TIERS, isCropShape } from './state/frame';
import type { Shape, Tier } from './state/frame';
import { jobBusy } from './state/model';
import { SHORTCUTS, ariaKeys, keysOf, matches, type CommandId } from './state/shortcuts';
import { ACTION_LABELS, BLOCKED, CODEC_NAMES, HEVC_UNAVAILABLE, NOTHING_DROPPED, clock, dimensions, dragLooksValid, enlargeNote, hevcAvailable, slotProblemWords } from './state/words';

// Song2Vid's one window (SPEC 27.2): Audio, Image, Frame Shape, Resolution, Codec, the preview with
// its crop, the enlarge note, and Make Video, over a status bar that says what is happening and what
// happened. The command registry below is the single list of commands: the palette shows it, the key
// handler and the shell's menu run it by id, each with its shortcut from shortcuts.json.

type Theme = 'light' | 'dark';

function useTheme(desktop: DesktopBridge): [Theme, () => void] {
  const [theme, setTheme] = useState<Theme>(() => (document.documentElement.dataset.theme === 'light' ? 'light' : 'dark'));
  // Keep the window's own colours (background, window-button glyphs) in step with the page.
  useEffect(() => {
    desktop.setTheme(theme);
  }, [desktop, theme]);
  function toggle() {
    const next: Theme = theme === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = next;
    try {
      localStorage.setItem('app.theme', next);
    } catch {
      // The choice still applies for this session.
    }
    setTheme(next);
  }
  return [theme, toggle];
}

const SHAPE_LABELS: Record<Shape, string> = { '16:9': '16:9', '9:16': '9:16', '1:1': '1:1', '4:3': '4:3', original: 'Original' };

export function App({ boot, desktop, platform }: { boot: Bootstrap; desktop: DesktopBridge; platform: Platform }) {
  const state = useApp((s) => s);
  const { audio, image, shape, tier, codec, job, encoders, failure } = state;
  const [theme, toggleTheme] = useTheme(desktop);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [aboutOpen, setAboutOpen] = useState(false);

  const busy = jobBusy(job);
  const blocked = state.tool.state === 'damaged';
  const frame = frameOf(state);
  const makeReady = canMake(state);
  const crops = isCropShape(shape);
  const room = roomOf(state);
  const canReset = crops && !busy && (room.h > 0 || room.v > 0);
  const hevcOk = hevcAvailable(encoders);

  // The command list is the single registry: the palette shows it, the key handler and the shell's
  // menu run it by id. A command a person repeats carries a shortcut from shortcuts.json.
  const cmd = (id: CommandId, rest: Omit<Command, 'id' | 'shortcut'>): Command => ({ id, shortcut: SHORTCUTS[id] ?? undefined, ...rest });
  const commands: Command[] = [
    cmd('choose-audio', { group: 'File', label: 'Choose Audio…', keywords: 'song music open file', disabled: busy || blocked || state.replace !== null, run: () => void chooseAudio().then(focusChoose('choose-audio')) }),
    cmd('choose-image', { group: 'File', label: 'Choose Image…', keywords: 'picture photo cover open file', disabled: busy || blocked || state.replace !== null, run: () => void chooseImage().then(focusChoose('choose-image')) }),
    cmd('make-video', { group: 'File', label: 'Make Video', keywords: 'save export create mp4', disabled: !makeReady, run: () => void makeVideo('ask') }),
    cmd('cancel', { group: 'File', label: 'Cancel', keywords: 'stop video', disabled: !(job.phase === 'running' && !job.cancelling) && job.phase !== 'starting', run: cancel }),
    cmd('show-in-folder', { group: 'File', label: 'Show in File Explorer', keywords: 'folder open saved video', disabled: job.phase !== 'done', run: showInFolder }),
    cmd('copy-details', { group: 'File', label: 'Copy Details', keywords: 'error problem failure clipboard', disabled: state.failure === null && !blocked, run: () => void copyDetails() }),
    cmd('reset-crop', { group: 'View', label: 'Reset Crop to Center', keywords: 'crop position move image', disabled: !canReset, run: resetCrop }),
    cmd('toggle-theme', { group: 'View', label: theme === 'dark' ? 'Use the light theme' : 'Use the dark theme', keywords: 'appearance dark light', run: toggleTheme }),
    cmd('about', { group: 'App', label: `About ${config.productName}`, keywords: 'version licence notices', run: () => setAboutOpen(true) }),
  ];

  const latest = useRef({ commands, paletteOpen, modal: false });
  const modal = aboutOpen || state.replace !== null;
  useEffect(() => {
    latest.current = { commands, paletteOpen, modal };
  });

  // The shell's menu dims exactly the commands whose shortcut would do nothing now.
  const menuState = JSON.stringify(Object.fromEntries(commands.map((c) => [c.id, !c.disabled])));
  useEffect(() => {
    desktop.setMenuState(JSON.parse(menuState));
  }, [desktop, menuState]);

  useEffect(() => {
    function runCommand(command: Command | undefined) {
      if (!command || command.disabled) return;
      command.run();
      if (command.focus) document.getElementById(command.focus)?.focus();
    }
    function onKeyDown(event: KeyboardEvent) {
      const { commands: list, paletteOpen: palette, modal: dialog } = latest.current;
      if (dialog) return; // a dialog takes its own keys
      if (matches(event, SHORTCUTS['command-palette'])) {
        event.preventDefault();
        setPaletteOpen(!palette);
        return;
      }
      if (palette || event.defaultPrevented) return;
      const command = list.find((c) => c.shortcut && matches(event, c.shortcut));
      if (!command) return;
      // Esc cancels only while a video is made; with nothing to cancel it is left to whatever else wants it.
      if (command.disabled) return;
      event.preventDefault();
      runCommand(command);
    }
    // A command from the shell: the menu bar, the Dock menu, a script through the control channel.
    const off = desktop.onMenuCommand((id) => {
      if (id === 'command-palette') setPaletteOpen(true);
      else runCommand(latest.current.commands.find((c) => c.id === id));
    });
    // A request from the desktop shell (--show-about through the control channel).
    const showAbout = () => setAboutOpen(true);
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('app-show-about', showAbout);
    return () => {
      off();
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('app-show-about', showAbout);
    };
  }, [desktop]);

  // Start where a person starts: on Choose Audio.
  useEffect(() => {
    if (document.activeElement === document.body) document.getElementById('choose-audio')?.focus();
  }, []);

  // Controls that were disabled while a video was made lose focus. When the job ends, focus goes to
  // the step that can succeed (the status bar's button), or back to Make Video (SPEC 27.4).
  const ended = job.phase === 'done' || job.phase === 'cancelled' || state.failure !== null;
  const wasEnded = useRef(false);
  useEffect(() => {
    if (ended && !wasEnded.current && document.activeElement === document.body) {
      (document.querySelector<HTMLElement>('[data-status-bar] [data-filled]') ?? document.getElementById('make-video'))?.focus();
    }
    wasEnded.current = ended;
  }, [ended]);

  // ---- drops (SPEC 4a): the whole window accepts files, wherever they land.
  const depth = useRef(0);
  const hasFiles = (event: DragEvent) => event.dataTransfer.types.includes('Files');
  function onDragEnter(event: DragEvent) {
    if (!hasFiles(event)) return;
    depth.current += 1;
  }
  function onDragOver(event: DragEvent) {
    if (!hasFiles(event)) return;
    event.preventDefault();
    const items = Array.from(event.dataTransfer.items, (item) => ({ kind: item.kind, type: item.type }));
    const valid = dragLooksValid(items);
    // A drop that cannot be used gets no highlight and no drop; while a video is made it is accepted so it can be refused in words.
    event.dataTransfer.dropEffect = valid ? 'copy' : 'none';
    setDragging(valid && !busy);
  }
  function onDragLeave(event: DragEvent) {
    if (!hasFiles(event)) return;
    depth.current = Math.max(0, depth.current - 1);
    if (depth.current === 0) setDragging(false);
  }
  function onDrop(event: DragEvent) {
    event.preventDefault();
    depth.current = 0;
    setDragging(false);
    const files = Array.from(event.dataTransfer.files);
    if (files.length) void dropFiles(files);
    else say(NOTHING_DROPPED);
  }

  const version = boot.about?.appVersion ?? pkg.version;
  const original = shape === 'original';
  const output = original ? originalSize(state) : null;
  // The note is about an image that can be made; one that is missing, unreadable or too small has the bar's words instead.
  const showEnlarge = Boolean(frame?.enlarged && image && failure?.of !== 'image');
  const makeKeys = keysOf(SHORTCUTS['make-video']);
  const enlargeWidth = frame?.size.width ?? 0;
  const enlargeHeight = frame?.size.height ?? 0;

  return (
    <Tooltip.Provider delay={500} closeDelay={0} timeout={400}>
      <div className="app" data-running={busy ? '' : undefined} onDragEnter={onDragEnter} onDragOver={onDragOver} onDragLeave={onDragLeave} onDrop={onDrop}>
        <TitleBar theme={theme} platform={platform} onToggleTheme={toggleTheme} onOpenPalette={() => setPaletteOpen(true)} />
        <div className="workspace">
          <main className="card" data-card="">
            {blocked ? (
              <ScrollArea className="blocked" data-blocked="" role="alert">
                <div className="blocked-inner">
                  <p className="text-subhead font-semibold">{BLOCKED.first}</p>
                  <p className="text-fg-2">{BLOCKED.second}</p>
                  <div className="blocked-actions">
                    <button type="button" className="btn btn-primary btn-lg" data-filled="" onClick={openDownloadPage}>
                      {ACTION_LABELS[BLOCKED.action]}
                    </button>
                    <button type="button" className="btn btn-secondary btn-lg" onClick={() => void copyDetails()}>
                      {ACTION_LABELS['copy-details']}
                    </button>
                  </div>
                </div>
              </ScrollArea>
            ) : (
              <>
                <ScrollArea className="card-body" data-card-body="">
                  <div className="row">
                    <span className="row-label">Audio</span>
                    <div className="file-line">
                      <button id="choose-audio" type="button" className="btn btn-secondary" disabled={busy} aria-keyshortcuts={ariaKeys(SHORTCUTS['choose-audio'])} onClick={() => void chooseAudio().then(focusChoose('choose-audio'))}>
                        Choose Audio…
                      </button>
                      {audio && (
                        <div className="file-info">
                          <FileName name={audio.name} kind="audio" problem={failure?.of === 'audio'} />
                          <span className="file-fact" data-problem={failure?.of === 'audio' ? '' : undefined}>
                            {failure?.of === 'audio' ? slotProblemWords(failure.code) : clock(audio.durationSeconds)}
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                  <div className="row">
                    <span className="row-label">Image</span>
                    <div className="file-line">
                      <button id="choose-image" type="button" className="btn btn-secondary" disabled={busy} aria-keyshortcuts={ariaKeys(SHORTCUTS['choose-image'])} onClick={() => void chooseImage().then(focusChoose('choose-image'))}>
                        Choose Image…
                      </button>
                      {image && (
                        <div className="file-info">
                          <FileName name={image.name} kind="image" problem={failure?.of === 'image'} />
                          <span className="file-fact" data-problem={failure?.of === 'image' ? '' : undefined}>
                            {failure?.of === 'image' ? slotProblemWords(failure.code) : dimensions(image.width, image.height)}
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                  <div className="row">
                    <span className="row-label">Frame Shape</span>
                    <Choice<Shape> label="Frame Shape" group="shape" value={shape} onChange={setShape} disabled={busy} options={SHAPES.map((value) => ({ value, label: SHAPE_LABELS[value] }))} />
                  </div>
                  <div className="row">
                    <span className="row-label">Resolution</span>
                    {original ? (
                      <p className="output-line" data-output="">
                        Output: {output ? dimensions(output.width, output.height) : 'image too small'}
                      </p>
                    ) : (
                      <Choice<Tier> label="Resolution" group="resolution" value={tier} onChange={setTier} disabled={busy} options={TIERS.map((value) => ({ value, label: value }))} />
                    )}
                  </div>
                  <div className="row">
                    <span className="row-label">Codec</span>
                    <div>
                      <Choice<'h264' | 'hevc'>
                        label="Codec"
                        group="codec"
                        value={codec}
                        onChange={setCodec}
                        disabled={busy}
                        options={[
                          { value: 'h264', label: CODEC_NAMES.h264 },
                          { value: 'hevc', label: CODEC_NAMES.hevc, disabled: !hevcOk },
                        ]}
                      />
                      {!hevcOk && (
                        <p className="choice-note text-small" data-hevc-note="">
                          {HEVC_UNAVAILABLE}
                        </p>
                      )}
                    </div>
                  </div>
                  <div className="preview" data-preview="">
                    <Preview />
                    <div className="preview-foot">
                      <p className="preview-note" data-enlarge-note="" aria-live="polite">
                        {showEnlarge ? enlargeNote(enlargeWidth, enlargeHeight) : ''}
                      </p>
                      <button type="button" className="btn btn-secondary btn-sm" id="reset-crop" disabled={!canReset} aria-keyshortcuts={ariaKeys(SHORTCUTS['reset-crop'])} onClick={resetCrop}>
                        Reset to Center
                      </button>
                    </div>
                  </div>
                </ScrollArea>
                <div className="card-foot">
                  <button id="make-video" type="button" className="btn btn-primary btn-lg w-full" data-primary-action="" disabled={!makeReady} aria-keyshortcuts={ariaKeys(SHORTCUTS['make-video'])} onClick={() => void makeVideo('ask')}>
                    <span>Make Video</span>
                    <span className="only-wide flex gap-0.5" aria-hidden="true">
                      {makeKeys.map((key) => (
                        <Kbd key={key}>{key}</Kbd>
                      ))}
                    </span>
                  </button>
                </div>
              </>
            )}
            <div className="drop-veil" data-active={state.dragging} aria-hidden="true">
              <span className="drop-veil-words">Drop a song or an image</span>
            </div>
          </main>
        </div>

        <StatusBar />

        <CommandPalette open={paletteOpen} onOpenChange={setPaletteOpen} commands={commands} />
        <ReplaceDialog />
        <AboutDialog open={aboutOpen} onOpenChange={setAboutOpen} desktop={desktop} version={version} />
      </div>
    </Tooltip.Provider>
  );
}

/** After a file dialog closes, focus is on the control that opened it, however the dialog was opened (SPEC 27.2, journeys). */
function focusChoose(id: 'choose-audio' | 'choose-image') {
  return () => document.getElementById(id)?.focus();
}
