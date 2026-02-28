import test from 'node:test';
import assert from 'node:assert/strict';
import { createAnimationState } from '../../../../app/components/explorer/renderers/animation';

test('createAnimationState returns object with tick and getWireAnimation', () => {
  const anim = createAnimationState();
  assert.equal(typeof anim.tick, 'function');
  assert.equal(typeof anim.getWireAnimation, 'function');
  assert.equal(typeof anim.markToggled, 'function');
});

test('getWireAnimation returns null when no animation active', () => {
  const anim = createAnimationState();
  assert.equal(anim.getWireAnimation('w1'), null);
});

test('markToggled starts animation, getWireAnimation returns pulseT 0.0', () => {
  const anim = createAnimationState();
  anim.markToggled('w1');
  const state = anim.getWireAnimation('w1');
  assert.ok(state, 'animation should be active');
  assert.equal(state.pulseT, 0.0);
});

test('tick advances pulseT', () => {
  const anim = createAnimationState();
  anim.markToggled('w1');

  anim.tick(100); // 100ms of 200ms total
  const state = anim.getWireAnimation('w1');
  assert.ok(state);
  assert.ok(state.pulseT > 0.0 && state.pulseT <= 1.0, `expected 0 < pulseT <= 1, got ${state.pulseT}`);
  assert.equal(state.pulseT, 0.5); // 100/200 = 0.5
});

test('animation completes after full duration', () => {
  const anim = createAnimationState();
  anim.markToggled('w1');

  anim.tick(200); // full 200ms
  const state = anim.getWireAnimation('w1');
  assert.equal(state, null, 'animation should be completed and removed');
});

test('tick with partial increments accumulates correctly', () => {
  const anim = createAnimationState();
  anim.markToggled('w1');

  anim.tick(50);
  assert.equal(anim.getWireAnimation('w1')!.pulseT, 0.25);

  anim.tick(50);
  assert.equal(anim.getWireAnimation('w1')!.pulseT, 0.5);

  anim.tick(100);
  assert.equal(anim.getWireAnimation('w1'), null); // completed
});

test('multiple wire animations are independent', () => {
  const anim = createAnimationState();
  anim.markToggled('w1');
  anim.tick(50);
  anim.markToggled('w2');

  anim.tick(50);
  assert.equal(anim.getWireAnimation('w1')!.pulseT, 0.5);
  assert.equal(anim.getWireAnimation('w2')!.pulseT, 0.25);
});

test('markToggled on already-animating wire restarts animation', () => {
  const anim = createAnimationState();
  anim.markToggled('w1');
  anim.tick(100);
  assert.equal(anim.getWireAnimation('w1')!.pulseT, 0.5);

  anim.markToggled('w1'); // restart
  assert.equal(anim.getWireAnimation('w1')!.pulseT, 0.0);
});

test('custom duration via constructor option', () => {
  const anim = createAnimationState({ pulseDurationMs: 400 });
  anim.markToggled('w1');
  anim.tick(200);
  assert.equal(anim.getWireAnimation('w1')!.pulseT, 0.5); // 200/400
  anim.tick(200);
  assert.equal(anim.getWireAnimation('w1'), null);
});
