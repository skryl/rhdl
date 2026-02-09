import test from 'node:test';
import assert from 'node:assert/strict';

import { createListenerGroup } from '../../../app/core/bindings/listener_group.mjs';

test('listener group registers listeners and disposes them', () => {
  const group = createListenerGroup();
  const target = new EventTarget();
  let fired = 0;

  group.on(target, 'ping', () => {
    fired += 1;
  });

  target.dispatchEvent(new Event('ping'));
  assert.equal(fired, 1);
  assert.equal(group.size(), 1);

  group.dispose();
  target.dispatchEvent(new Event('ping'));
  assert.equal(fired, 1);
  assert.equal(group.size(), 0);
});

test('listener group ignores invalid targets safely', () => {
  const group = createListenerGroup();
  group.on(null, 'x', () => {});
  group.on({}, 'x', () => {});
  assert.equal(group.size(), 0);
});
