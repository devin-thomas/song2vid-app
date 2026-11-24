import { Dialog } from '@base-ui/react/dialog';
import { useEffect, useRef, useState } from 'react';
import config from '../../app.config.json';
import type { DesktopBridge } from '../bridge';
import { answerReplace, openRepository, useApp } from '../state/app';

/** Where focus was when a dialog opened, so closing it returns there (SPEC 27.3). Dialogs opened by a drop have no trigger. */
function useFocusBefore(open: boolean) {
  const before = useRef<HTMLElement | null>(null);
  const was = useRef(false);
  if (open && !was.current) {
    const active = document.activeElement;
    before.current = active instanceof HTMLElement && active !== document.body ? active : null;
  }
  was.current = open;
  return () => {
    const back = before.current;
    return back && back.isConnected ? back : (document.getElementById('choose-audio') ?? true);
  };
}

/** SPEC 4a: "Replace the current song?" Keep Current is the default and Esc chooses it. */
export function ReplaceDialog() {
  const question = useApp((s) => s.replace);
  const keep = useRef<HTMLButtonElement>(null);
  const finalFocus = useFocusBefore(question !== null);
  return (
    <Dialog.Root open={question !== null} onOpenChange={(open) => !open && answerReplace(false)}>
      <Dialog.Portal>
        <Dialog.Backdrop className="scrim dialog-scrim" />
        <Dialog.Popup className="dialog" initialFocus={keep} finalFocus={finalFocus} data-replace="">
          <Dialog.Title className="text-subhead font-semibold">{question?.title}</Dialog.Title>
          <Dialog.Description render={<div />} className="mt-3 grid gap-3 text-fg-2">
            {question?.lines.map((line) => (
              <div key={line.now} className="grid gap-0.5">
                <p className="selectable wrap-anywhere">{line.now}</p>
                <p className="selectable wrap-anywhere">{line.dropped}</p>
              </div>
            ))}
          </Dialog.Description>
          <div className="mt-5 flex justify-end gap-2">
            <button type="button" className="btn btn-secondary" onClick={() => answerReplace(true)}>
              Replace
            </button>
            <button ref={keep} type="button" className="btn btn-primary" onClick={() => answerReplace(false)}>
              Keep Current
            </button>
          </div>
        </Dialog.Popup>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

/**
 * About: the name and version, the licence, the repository, and the third-party notices (SPEC 27.8).
 * The notices text names the programs Song2Vid uses, which the banned-terms gate would catch anywhere
 * else: it alone carries `data-notices`, and the audit leaves out that one element and nothing around it.
 */
export function AboutDialog({ open, onOpenChange, desktop, version }: { open: boolean; onOpenChange: (open: boolean) => void; desktop: DesktopBridge; version: string }) {
  const [notices, setNotices] = useState<string | null>(null);
  const finalFocus = useFocusBefore(open);
  useEffect(() => {
    if (!open || notices !== null) return;
    let live = true;
    void desktop.notices().then((text) => live && setNotices(text));
    return () => {
      live = false;
    };
  }, [open, notices, desktop]);
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Backdrop className="scrim dialog-scrim" />
        <Dialog.Popup className="dialog" finalFocus={finalFocus} data-about="">
          <Dialog.Title className="text-subhead font-semibold">About {config.productName}</Dialog.Title>
          <Dialog.Description className="mt-2 text-fg-2">{config.description}</Dialog.Description>
          <dl className="facts mt-4">
            <div className="px-3 py-2">
              <dt className="text-small text-fg-3">Version</dt>
              <dd className="selectable mt-0.5">
                {config.productName} {version}
              </dd>
            </div>
            <div className="px-3 py-2">
              <dt className="text-small text-fg-3">Licence</dt>
              <dd className="mt-0.5">MIT License</dd>
            </div>
            <div className="px-3 py-2">
              <dt className="text-small text-fg-3">Repository</dt>
              <dd className="mt-0.5">
                <button type="button" className="link-button" onClick={openRepository}>
                  View the repository on GitHub
                </button>
              </dd>
            </div>
          </dl>
          <p className="mt-4 text-small text-fg-3" id="notices-title">
            Third-party notices
          </p>
          <div className="notices scroll-cue mt-1" tabIndex={0} role="region" aria-labelledby="notices-title" data-notices="">
            {notices ?? 'Loading…'}
          </div>
          <div className="mt-5 flex justify-end">
            <Dialog.Close className="btn btn-secondary">Close</Dialog.Close>
          </div>
        </Dialog.Popup>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
