import { useRef, useState } from 'react';
import type { KeyboardEvent, PointerEvent } from 'react';
import { canAdjustCrop, frameOf, nudgeCrop, roomOf, setCropEdge, setCropFromDrag, useApp } from '../state/app';
import { cropText, isCropShape } from '../state/frame';
import type { Crop, Direction } from '../state/frame';
import { dimensions, failureFor, knownFailureFirst } from '../state/words';
import { Spinner } from './ui';

/** The shape of the empty frame before an image is chosen, and of one that failed: by Frame Shape, 16:9 for Original. */
const EMPTY_RATIO: Record<string, number> = { '16:9': 16 / 9, '9:16': 9 / 16, '1:1': 1, '4:3': 4 / 3, original: 16 / 9 };

const ARROWS: Record<string, Direction> = { ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down' };

/**
 * The output frame drawn to scale, with the image placed exactly as the video will have it (SPEC 27.2,
 * item 6). Where the image fills the frame (1:1 and 4:3) the frame is the one control "Crop position":
 * a drag moves the image with the pointer, the arrow keys move it by 5% of the movable range (25% with
 * Shift), Home and End go to the ends, Page Up and Page Down are the large step. Its value text reads
 * "50% across, 30% down". The position lives in a store outside React, so the picture and the text
 * change in the same task as the input (premium bar rules 67, 75).
 */
export function Preview() {
  const image = useApp((s) => s.image);
  const preview = useApp((s) => s.preview);
  const shape = useApp((s) => s.shape);
  const crop = useApp((s) => s.crop);
  const state = useApp((s) => s);
  const frame = frameOf(state);
  const adjustable = canAdjustCrop(state);
  const room = roomOf(state);
  const [dragging, setDragging] = useState(false);
  const drag = useRef<{ x: number; y: number; start: Crop; pixelsPerPoint: number } | null>(null);

  const ready = preview?.status === 'ready' ? preview : null;
  let words: string | null = null;
  if (!image) words = 'Choose an image';
  else if (!frame) words = `${failureFor('image_too_small').first} ${failureFor('image_too_small').second}`;
  else if (preview?.status === 'failed') words = knownFailureFirst(preview.code) ?? "The preview couldn't be made.";
  const drawn = ready && frame ? frame : null;
  const empty = !drawn;
  const ratio = drawn ? drawn.size.width / drawn.size.height : (EMPTY_RATIO[shape] ?? 16 / 9);
  const crops = isCropShape(shape);

  function onPointerDown(event: PointerEvent<HTMLDivElement>) {
    if (!adjustable || !drawn || event.button !== 0) return;
    const box = event.currentTarget.getBoundingClientRect();
    drag.current = { x: event.clientX, y: event.clientY, start: crop, pixelsPerPoint: box.width / drawn.size.width };
    event.currentTarget.setPointerCapture(event.pointerId);
    event.currentTarget.focus({ preventScroll: true });
    setDragging(true);
  }

  function onPointerMove(event: PointerEvent<HTMLDivElement>) {
    const d = drag.current;
    if (!d) return;
    // The image follows the pointer: the pointer's distance in frame pixels moves it that far.
    setCropFromDrag(d.start, (event.clientX - d.x) / d.pixelsPerPoint, (event.clientY - d.y) / d.pixelsPerPoint);
  }

  function onPointerEnd(event: PointerEvent<HTMLDivElement>) {
    if (!drag.current) return;
    drag.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
    setDragging(false);
  }

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (!adjustable || event.ctrlKey || event.metaKey || event.altKey) return;
    // The axis that can move: across when the image is wider than the frame, down when it is taller.
    const across = room.h > 0;
    const arrow = ARROWS[event.key];
    if (arrow) nudgeCrop(arrow, event.shiftKey);
    else if (event.key === 'PageUp') nudgeCrop(across ? 'left' : 'up', true);
    else if (event.key === 'PageDown') nudgeCrop(across ? 'right' : 'down', true);
    else if (event.key === 'Home') setCropEdge(false);
    else if (event.key === 'End') setCropEdge(true);
    else return;
    event.preventDefault();
  }

  const primary = room.h > 0 ? crop.h : crop.v;
  const label = drawn ? `Preview of the video frame, ${dimensions(drawn.size.width, drawn.size.height)} pixels` : 'Preview of the video frame';
  const control = adjustable
    ? { role: 'slider', tabIndex: 0, 'aria-label': 'Crop position', 'aria-valuemin': 0, 'aria-valuemax': 100, 'aria-valuenow': Math.round(primary * 100), 'aria-valuetext': cropText(crop), 'aria-orientation': room.h > 0 ? ('horizontal' as const) : ('vertical' as const) }
    : { role: 'img', 'aria-label': label };

  return (
    <div className="stage" data-preview-stage="">
      <div
        className="frame"
        style={{ ['--ar' as string]: ratio }}
        data-crop={adjustable}
        data-dragging={dragging}
        data-empty={empty}
        data-crop-shape={crops}
        data-frame={drawn ? `${drawn.size.width}x${drawn.size.height}` : undefined}
        data-preview-state={preview?.status ?? 'none'}
        {...control}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerEnd}
        onPointerCancel={onPointerEnd}
        onKeyDown={onKeyDown}
      >
        {drawn && ready && (
          <img
            src={ready.src}
            alt=""
            draggable={false}
            style={{
              left: `${(drawn.placement.x / drawn.size.width) * 100}%`,
              top: `${(drawn.placement.y / drawn.size.height) * 100}%`,
              width: `${(drawn.placement.width / drawn.size.width) * 100}%`,
              height: `${(drawn.placement.height / drawn.size.height) * 100}%`,
            }}
          />
        )}
        {words && (
          <div className="frame-words" data-preview-words="">
            {words}
          </div>
        )}
        {image && !words && preview?.status === 'loading' && (
          <div className="frame-words">
            <Spinner />
          </div>
        )}
      </div>
    </div>
  );
}
