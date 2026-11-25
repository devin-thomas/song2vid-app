// The output frame and where the image sits in it, as the preview draws them. A port of the Mac
// app's OutputFrame (Song2VidCore, SPEC section 5), kept equal to it by test/frame.test.ts, which
// reads the same fixture the Swift and Rust suites read (fixtures/frame-math.json). The tool
// decides the real output size (the `check` table); this exists so the preview can draw the
// placement, which the table does not carry. Plain TypeScript with no imports: the tests run it.

export type Shape = '16:9' | '9:16' | '1:1' | '4:3' | 'original';
export type Tier = '480p' | '1080p' | '2160p';

export interface Size {
  width: number;
  height: number;
}

export interface Placement {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** Where a Crop keeps the image, as fractions 0 to 1 (0.5 is centred). Independent of the Resolution. */
export interface Crop {
  h: number;
  v: number;
}

export const CENTER: Crop = { h: 0.5, v: 0.5 };

export interface Frame {
  size: Size;
  placement: Placement;
  /** The image is drawn larger than its own pixel size (the enlarge note). */
  enlarged: boolean;
}

export const SHAPES: readonly Shape[] = ['16:9', '9:16', '1:1', '4:3', 'original'];
export const TIERS: readonly Tier[] = ['480p', '1080p', '2160p'];

export const shortSide = (tier: Tier): number => (tier === '480p' ? 480 : tier === '1080p' ? 1080 : 2160);

/** Shapes whose image fills the frame, so a position can change what is kept. */
export const isCropShape = (shape: Shape): boolean => shape === '1:1' || shape === '4:3';

const clamp01 = (value: number): number => (Number.isNaN(value) ? 0.5 : Math.min(1, Math.max(0, value)));

/** `numerator / denominator` rounded up to the next even whole number. */
function evenCeil(numerator: number, denominator: number): number {
  const ceiling = Math.floor((numerator + denominator - 1) / denominator);
  return ceiling + (ceiling % 2);
}

function fitWithBars(image: Size, frame: Size): Frame {
  const scale = Math.min(frame.width / image.width, frame.height / image.height);
  const width = image.width * scale;
  const height = image.height * scale;
  return { size: frame, placement: { x: (frame.width - width) / 2, y: (frame.height - height) / 2, width, height }, enlarged: scale > 1 };
}

function crop(image: Size, frame: Size, at: Crop): Frame {
  const scale = Math.max(frame.width / image.width, frame.height / image.height);
  const width = image.width * scale;
  const height = image.height * scale;
  return { size: frame, placement: { x: -(width - frame.width) * clamp01(at.h), y: -(height - frame.height) * clamp01(at.v), width, height }, enlarged: scale > 1 };
}

/** SPEC 5, Original: the image's own size limited to 3840x2160 (2160x3840 for portrait) and made even. Whole-number arithmetic, so 0.99 cannot drift. */
function original(image: Size): Frame | null {
  if (image.width < 16 || image.height < 16) return null;
  const portrait = image.height > image.width;
  const limit: Size = portrait ? { width: 2160, height: 3840 } : { width: 3840, height: 2160 };
  let numerator = 1;
  let denominator = 1;
  if (limit.width * denominator < image.width * numerator) {
    numerator = limit.width;
    denominator = image.width;
  }
  if (limit.height * denominator < image.height * numerator) {
    numerator = limit.height;
    denominator = image.height;
  }
  let size: Size;
  let placement: Placement;
  if (numerator === denominator) {
    size = { ...image };
    placement = { x: 0, y: 0, width: image.width, height: image.height };
  } else if (numerator * 100 >= denominator * 99) {
    size = { width: Math.min(image.width, limit.width), height: Math.min(image.height, limit.height) };
    placement = { x: -Math.floor((image.width - size.width) / 2), y: -Math.floor((image.height - size.height) / 2), width: image.width, height: image.height };
  } else {
    const scaled: Size = { width: Math.floor((image.width * numerator) / denominator), height: Math.floor((image.height * numerator) / denominator) };
    size = scaled;
    placement = { x: 0, y: 0, width: scaled.width, height: scaled.height };
  }
  size = { width: size.width - (size.width % 2), height: size.height - (size.height % 2) };
  return { size, placement, enlarged: false };
}

/**
 * The frame for an image, Frame Shape and Resolution. `image` is the image's size after its orientation
 * tag. Null for Original with a side under 16 pixels (the tool says `image_too_small`).
 */
export function outputFrame(image: Size, shape: Shape, tier: Tier, at: Crop = CENTER): Frame | null {
  const short = shortSide(tier);
  switch (shape) {
    case '16:9':
      return fitWithBars(image, { width: evenCeil(short * 16, 9), height: short });
    case '9:16':
      return fitWithBars(image, { width: short, height: evenCeil(short * 16, 9) });
    case '1:1':
      return crop(image, { width: short, height: short }, at);
    case '4:3':
      return crop(image, { width: Math.floor((short * 4) / 3), height: short }, at);
    case 'original':
      return original(image);
  }
}

/** How far the image can move on each axis, in frame pixels. Zero where it has nothing to crop. */
export function overflow(frame: Frame, shape: Shape): { h: number; v: number } {
  if (!isCropShape(shape)) return { h: 0, v: 0 };
  return { h: Math.max(0, frame.placement.width - frame.size.width), v: Math.max(0, frame.placement.height - frame.size.height) };
}

const toMillionths = (value: number): number => Math.round(value * 1_000_000) / 1_000_000;

export type Direction = 'left' | 'right' | 'up' | 'down';

/** An arrow key: the image moves one step that way (Mac nudgeCrop). 5% of the range, 25% with Shift. */
export function nudge(at: Crop, direction: Direction, large: boolean, room: { h: number; v: number }): Crop {
  const step = large ? 0.25 : 0.05;
  let { h, v } = at;
  if (direction === 'left' && room.h > 0) h += step;
  else if (direction === 'right' && room.h > 0) h -= step;
  else if (direction === 'up' && room.v > 0) v += step;
  else if (direction === 'down' && room.v > 0) v -= step;
  else return at;
  return { h: toMillionths(clamp01(h)), v: toMillionths(clamp01(v)) };
}

/** A drag of the image by (dx, dy) frame pixels from where `start` had it. Past an edge it stops; an axis with nothing to crop does not move. */
export function drag(start: Crop, dx: number, dy: number, room: { h: number; v: number }, current: Crop): Crop {
  return {
    h: room.h > 0 ? toMillionths(clamp01(start.h - dx / room.h)) : current.h,
    v: room.v > 0 ? toMillionths(clamp01(start.v - dy / room.v)) : current.v,
  };
}

/** The value text of the Crop position control: "50% across, 30% down". */
export const cropText = (at: Crop): string => `${Math.round(at.h * 100)}% across, ${Math.round(at.v * 100)}% down`;
