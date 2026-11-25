// The shell's half of the tool part of src/bridge.ts: find the bundled tool, check it, answer the
// page's calls, run one job at a time and report to the page. The only module in electron/tool
// that touches Electron; the work itself is service.ts, plain Node, tested with the stand-in
// tool (test/). This file gives it the Windows dialogs, the window and the IPC channels, and
// asks the question when a job is running and the app is closed.
//
// Channels (electron/preload.ts is the other end): `file:choose-audio`, `file:choose-image`,
// `file:drop`, `file:release`, `file:preview`, `job:make`, `job:cancel`, `job:show-in-folder`
// (page to shell) and `job:update`, `tool:encoders`, `tool:status`, `file:opened` (shell to page). The
// channels for preferences, links and notices (`app:preferences`, `app:open-link`, `app:notices`)
// are not tool calls and are in main.ts (electron/app-data.ts).
import { app, dialog, shell } from 'electron';
import type { BrowserWindow, IpcMain, IpcMainEvent } from 'electron';
import type { JobUpdate, ToolStatus } from '../../src/bridge.ts';
import type { AppConfig, SystemName } from '../platform.ts';
import { STAGING_NAME } from './contract.ts';
import { AUDIO_EXTENSIONS, IMAGE_EXTENSIONS } from './files.ts';
import { locateTool } from './locate.ts';
import { answerOpen, answerSave, readQaPicks } from './qa-picks.ts';
import { createToolService } from './service.ts';
import type { ToolUi } from './service.ts';

export { STAGING_NAME };

export interface NativeOptions {
  config: Pick<AppConfig, 'tool'>;
  getWindow: () => BrowserWindow | null;
  system: SystemName;
  projectDir: string;
  /** Whether the launch being handled asked for no focus (`--no-activate`): then no dialog is opened, and a request for one is answered as dismissed. */
  quiet: () => boolean;
}

type Handle = (channel: string, work: (...args: unknown[]) => unknown) => void;

export function createNative({ config, getWindow, system, projectDir, quiet }: NativeOptions) {
  const binaries: string[] = config.tool.binaries ?? [];
  const helpers = binaries.filter((name) => name !== config.tool.name);
  // Development only: STANDIN_TOOL names the stand-in script, so the shell runs without a built tool.
  const standin = process.env['STANDIN_TOOL'];
  const override = !app.isPackaged && standin ? { script: standin, config: process.env['STANDIN_CONFIG'] } : null;
  const located = locateTool({ packaged: app.isPackaged, resourcesPath: process.resourcesPath, projectDir, toolName: config.tool.name, helpers, override });

  const sendToPage = (channel: string, payload: unknown) => {
    const win = getWindow();
    if (win && !win.isDestroyed()) win.webContents.send(channel, payload);
  };

  const parent = () => {
    const win = getWindow();
    return win && !win.isDestroyed() ? win : null;
  };

  /** The system's own dialogs. Under --no-activate none is opened (D-010): the answer is "the person closed it". */
  // Development only: answers for the dialogs, from the launch's flags (qa-picks.ts). A packaged app never reads them.
  const picks = readQaPicks(process.argv, app.isPackaged);
  const ui: ToolUi = {
    async pickFile(kind) {
      if (picks) return answerOpen(picks, kind);
      if (quiet()) return null;
      const options = {
        title: kind === 'audio' ? 'Choose Audio' : 'Choose Image',
        properties: ['openFile' as const],
        filters: [{ name: kind === 'audio' ? 'Audio' : 'Images', extensions: [...(kind === 'audio' ? AUDIO_EXTENSIONS : IMAGE_EXTENSIONS)] }],
      };
      const win = parent();
      const result = win ? await dialog.showOpenDialog(win, options) : await dialog.showOpenDialog(options);
      return result.canceled ? null : (result.filePaths[0] ?? null);
    },
    async pickSave(defaultPath) {
      if (picks) return answerSave(picks);
      if (quiet()) return null;
      const options = { title: 'Make Video', defaultPath, filters: [{ name: 'MP4 video', extensions: ['mp4'] }] };
      const win = parent();
      const result = win ? await dialog.showSaveDialog(win, options) : await dialog.showSaveDialog(options);
      return result.canceled ? null : (result.filePath ?? null);
    },
    showInFolder: (file) => shell.showItemInFolder(file),
  };

  const service = createToolService({
    located,
    dataDir: app.getPath('userData'),
    ui,
    videosDir: () => app.getPath('videos'),
    emit: {
      job: (update: JobUpdate) => sendToPage('job:update', update),
      encoders: (report) => sendToPage('tool:encoders', report),
      filesOpened: (result) => sendToPage('file:opened', result),
      toolStatus: (status) => sendToPage('tool:status', status),
    },
  });

  /** Check the tool, reconcile what a killed run left behind. Call once, when the app is ready. */
  const start = (): void => service.start();

  function registerIpc({ handle, ipcMain, trusted }: { handle: Handle; ipcMain: IpcMain; trusted: (event: IpcMainEvent) => boolean }): void {
    handle('file:choose-audio', () => service.chooseAudio());
    handle('file:choose-image', () => service.chooseImage());
    handle('file:drop', (paths) => service.dropFiles(paths));
    handle('file:preview', (imageId) => service.previewImage(imageId));
    handle('job:make', (request) => service.makeVideo(request));
    ipcMain.on('file:release', (event, ids: unknown) => {
      if (trusted(event)) service.releaseFiles(ids);
    });
    ipcMain.on('job:cancel', (event, jobId: unknown) => {
      if (trusted(event)) service.cancelJob(jobId);
    });
    ipcMain.on('job:show-in-folder', (event, outputId: unknown) => {
      if (trusted(event)) service.showInFolder(outputId);
    });
  }

  /** Closing or quitting with a job running (SPEC 27.4): ask, unless the request came from a launch that asked for no focus. */
  async function confirmQuitDuringJob(win: BrowserWindow | null, { quiet: noFocus }: { quiet: boolean }): Promise<boolean> {
    if (!service.jobRunning) return true;
    if (noFocus) return false;
    const question = {
      type: 'question' as const,
      buttons: ['Keep Making', 'Stop and Close'],
      defaultId: 0,
      cancelId: 0,
      message: 'Stop making the video?',
      detail: 'Closing stops it. Nothing is saved.',
    };
    const { response } = win && !win.isDestroyed() ? await dialog.showMessageBox(win, question) : await dialog.showMessageBox(question);
    if (response !== 1) return false;
    service.cancelJob(service.jobId);
    const deadline = Date.now() + 6000; // 3 s of grace for the tool, then the exit
    while (service.jobRunning && Date.now() < deadline) await new Promise((r) => setTimeout(r, 50));
    return true;
  }

  return {
    start,
    status: (): Promise<ToolStatus> => service.status(),
    /** The Encoder report for bootstrap: the last answer, fresh once this launch's check has finished. */
    encoders: () => service.encoders(),
    /** A file opened with the app, judged as a drop is (the second-launch hand-off wires this in S2V-030). */
    openFiles: (paths: string[]) => service.openFiles(paths),
    registerIpc,
    confirmQuitDuringJob,
    diagnostics: (): Record<string, unknown> => ({ system, ...service.diagnostics() }),
    get jobRunning(): boolean {
      return service.jobRunning;
    },
  };
}
