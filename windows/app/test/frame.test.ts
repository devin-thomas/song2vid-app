// The page's frame math is a port of the Mac app's OutputFrame. This holds it to the fixture the
// Swift and Rust suites read (fixtures/frame-math.json at the repository root), and checks the
// crop steps against the Mac app's own tests (MainWindowCropTests.swift).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { CENTER, cropText, drag, nudge, outputFrame, overflow } from '../src/state/frame.ts';
import type { Crop, Shape, Tier } from '../src/state/frame.ts';

interface Case {
  crop: { horizontal: number; vertical: number };
  image: { width: number; height: number };
  resolution: Tier;
  shape: Shape;
  error?: string;
  output?: { enlarged: boolean; placement: { x: number; y: number; width: number; height: number }; size: { width: number; height: number } };
}

const fixture = path.join(import.meta.dirname, '..', '..', '..', 'fixtures', 'frame-math.json');
const cases = JSON.parse(fs.readFileSync(fixture, 'utf8')) as Case[];

test('the page draws every case of the shared frame-math fixture as the Mac app does', () => {
  assert.ok(cases.length >= 200, `read ${cases.length} cases`);
  for (const c of cases) {
    const frame = outputFrame(c.image, c.shape, c.resolution, { h: c.crop.horizontal, v: c.crop.vertical });
    const name = `${c.shape} ${c.resolution} ${c.image.width}x${c.image.height}`;
    if (c.error) {
      assert.equal(frame, null, `${name} should be too small`);
      continue;
    }
    assert.ok(c.output && frame, name);
    assert.deepEqual(frame.size, c.output.size, `${name}: size`);
    assert.equal(frame.enlarged, c.output.enlarged, `${name}: enlarged`);
    for (const key of ['x', 'y', 'width', 'height'] as const) {
      assert.ok(Math.abs(frame.placement[key] - c.output.placement[key]) < 1e-6, `${name}: placement ${key} ${frame.placement[key]} vs ${c.output.placement[key]}`);
    }
  }
});

const room = (shape: Shape, width: number, height: number) => {
  const frame = outputFrame({ width, height }, shape, '1080p');
  assert.ok(frame);
  return overflow(frame, shape);
};

test('the arrow keys move the image by 5%, or 25% with Shift, and stop at the edges', () => {
  const wide = room('1:1', 2000, 1000);
  assert.ok(wide.h > 0 && wide.v === 0);
  // Left shows more of the image's right side, as on the Mac: the position rises.
  assert.deepEqual(nudge(CENTER, 'left', false, wide), { h: 0.55, v: 0.5 });
  assert.deepEqual(nudge(CENTER, 'right', false, wide), { h: 0.45, v: 0.5 });
  assert.deepEqual(nudge(CENTER, 'left', true, wide), { h: 0.75, v: 0.5 });
  let at: Crop = CENTER;
  for (let i = 0; i < 40; i++) at = nudge(at, 'left', false, wide);
  assert.equal(at.h, 1);
  for (let i = 0; i < 80; i++) at = nudge(at, 'right', false, wide);
  assert.equal(at.h, 0);
  // An axis with nothing to crop does nothing.
  assert.deepEqual(nudge(CENTER, 'up', false, wide), CENTER);
  assert.deepEqual(nudge(CENTER, 'down', true, wide), CENTER);
  const tall = room('1:1', 1000, 2000);
  assert.deepEqual(nudge(CENTER, 'up', false, tall), { h: 0.5, v: 0.55 });
  // Repeated steps land on exact values.
  let steps: Crop = CENTER;
  for (let i = 0; i < 3; i++) steps = nudge(steps, 'left', false, wide);
  assert.equal(steps.h, 0.65);
});

test('a drag moves the image with the pointer and not past an edge', () => {
  const wide = room('1:1', 2000, 1000);
  const half = drag(CENTER, wide.h / 4, 0, wide, CENTER);
  assert.equal(half.h, 0.25);
  assert.equal(drag(CENTER, wide.h * 3, 0, wide, CENTER).h, 0);
  assert.equal(drag(CENTER, -wide.h * 3, 0, wide, CENTER).h, 1);
  // The axis with nothing to crop keeps its value.
  assert.equal(drag({ h: 0.5, v: 0.5 }, 0, 400, wide, { h: 0.5, v: 0.2 }).v, 0.2);
});

test('the value text of the Crop position control', () => {
  assert.equal(cropText(CENTER), '50% across, 50% down');
  assert.equal(cropText({ h: 0.5, v: 0.3 }), '50% across, 30% down');
  assert.equal(cropText({ h: 0.054, v: 1 }), '5% across, 100% down');
});

test('Fit shapes and Original have nothing to crop', () => {
  assert.deepEqual(room('16:9', 2000, 1000), { h: 0, v: 0 });
  assert.deepEqual(room('original', 2000, 1000), { h: 0, v: 0 });
});
