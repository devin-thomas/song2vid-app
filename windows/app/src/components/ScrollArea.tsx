import { ChevronDown } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import type { HTMLAttributes, Ref } from 'react';

/**
 * The part of the card that scrolls when the window is too small for everything (the 200% zoom case, a window at its
 * minimum). While more is below, a strip under it says so ("More below"); at the end it goes. The cue is a real element,
 * not a fade or an overlay scrollbar: those vanish in a screenshot, on a system whose scrollbars hide, and for a person
 * who never scrolls (the critic's finding of S2V-031: whole rows were out of sight with no sign of them).
 * `qa/audit.ts` (gate `reach`) holds this to every control the area holds.
 */
export function ScrollArea({ children, className, ref, ...rest }: HTMLAttributes<HTMLDivElement> & { ref?: Ref<HTMLDivElement> }) {
  const own = useRef<HTMLDivElement | null>(null);
  const area = own;
  const [more, setMore] = useState(false);

  useEffect(() => {
    const el = area.current;
    if (!el) return;
    const update = () => setMore(el.scrollHeight - el.clientHeight - el.scrollTop > 2);
    update();
    el.addEventListener('scroll', update, { passive: true });
    // The content changes size with the window, the zoom and the state (a note appears, a row turns into a message).
    const observer = new ResizeObserver(update);
    observer.observe(el);
    for (const child of Array.from(el.children)) observer.observe(child);
    const mutations = new MutationObserver(update);
    mutations.observe(el, { childList: true, subtree: true, characterData: true });
    return () => {
      el.removeEventListener('scroll', update);
      observer.disconnect();
      mutations.disconnect();
    };
  }, []);

  return (
    <>
      <div
        {...rest}
        className={`scroll-area ${className ?? ''}`}
        ref={(el) => {
          own.current = el;
          if (typeof ref === 'function') ref(el);
          else if (ref) ref.current = el;
        }}
        data-more={more ? '' : undefined}
      >
        {children}
      </div>
      <div className="scroll-more" data-scroll-cue="" data-shown={more ? '' : undefined} hidden={!more} aria-hidden="true">
        <ChevronDown size={14} strokeWidth={2} aria-hidden="true" />
        More below
      </div>
    </>
  );
}
