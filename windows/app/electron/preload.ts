// The only surface the page can reach. Context isolation and the sandbox are
// on; the page gets these functions and nothing else from Electron. The list is
// exactly `DesktopBridge` in src/bridge.ts: `satisfies` below checks the types, and
// test/preload.test.ts compares the names. Each function is one narrow call;
// ipcRenderer itself is never exposed. The page never sees a file path: files are
// named by opaque ids the main process keeps (a dropped file's location is resolved
// here with webUtils.getPathForFile and sent straight to the main process).
//
// A sandboxed preload must be one CommonJS file that requires nothing but electron, so
// scripts/build-electron.ts bundles this into dist/electron/preload.cjs.
import { contextBridge, ipcRenderer, webUtils } from 'electron';
import type { IpcRendererEvent } from 'electron';
import type { DesktopBridge } from '../src/bridge.ts';

/** Subscribes `listener` to one channel from the shell; returns the unsubscribe function. */
function subscribe<T>(channel: string, listener: (payload: T) => void): () => void {
  if (typeof listener !== 'function') return () => {};
  const forward = (_event: IpcRendererEvent, payload: T) => listener(payload);
  ipcRenderer.on(channel, forward);
  return () => {
    ipcRenderer.removeListener(channel, forward);
  };
}

type Result<K extends keyof DesktopBridge> = Awaited<ReturnType<DesktopBridge[K]>>;

contextBridge.exposeInMainWorld('desktop', {
  /** Saved state, the system, the remembered Codec, the app version and data folder, the tool's status and the cached Encoder report. */
  bootstrap: () => ipcRenderer.invoke('app:bootstrap') as Promise<Result<'bootstrap'>>,
  setTheme: (theme) => ipcRenderer.send('app:theme', theme),
  /** Saved at once by the main process, so unsaved work survives the app being killed. */
  saveState: (key, json) => ipcRenderer.send('app:save-state', key, json),
  setPreferences: (update) => ipcRenderer.send('app:preferences', update),

  /** The Windows open dialog, then the section 7 check; resolves with an opaque id, never a path. */
  chooseAudio: () => ipcRenderer.invoke('file:choose-audio') as Promise<Result<'chooseAudio'>>,
  chooseImage: () => ipcRenderer.invoke('file:choose-image') as Promise<Result<'chooseImage'>>,
  /** The one place a dropped file's location is read: here, and sent straight to the main process. */
  dropFiles: (files) => ipcRenderer.invoke('file:drop', Array.from(files, (file) => webUtils.getPathForFile(file))) as Promise<Result<'dropFiles'>>,
  onFilesOpened: (listener) => subscribe('file:opened', listener),
  releaseFiles: (ids) => ipcRenderer.send('file:release', ids),
  previewImage: (imageId) => ipcRenderer.invoke('file:preview', imageId) as Promise<Result<'previewImage'>>,
  onEncoders: (listener) => subscribe('tool:encoders', listener),

  /** Open the save dialog (or reuse the last destination) and start the job; resolves as soon as it is recorded. */
  makeVideo: (request) => ipcRenderer.invoke('job:make', request) as Promise<Result<'makeVideo'>>,
  cancelJob: (jobId) => ipcRenderer.send('job:cancel', jobId),
  onJob: (listener) => subscribe('job:update', listener),
  showInFolder: (outputId) => ipcRenderer.send('job:show-in-folder', outputId),

  openLink: (which) => ipcRenderer.send('app:open-link', which),
  notices: () => ipcRenderer.invoke('app:notices') as Promise<Result<'notices'>>,
  /** A command chosen in the menu bar, the Dock menu or sent by a script through the control channel: one command id. */
  onMenuCommand: (listener) => subscribe('app:menu-command', listener),
  /** Which commands can run now, so the shell can dim the matching menu items: one object of id to boolean. */
  setMenuState: (enabled) => ipcRenderer.send('app:menu-state', enabled),
} satisfies DesktopBridge);
