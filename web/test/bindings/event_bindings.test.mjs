import test from 'node:test';
import assert from 'node:assert/strict';
import { createEventLogger } from '../../app/bindings/event_bindings.mjs';

test('createEventLogger prepends timestamped log lines', () => {
  const node = { textContent: 'prior' };
  const log = createEventLogger(node);
  log('hello');

  assert.equal(node.textContent.endsWith('] hello\nprior'), true);
  assert.equal(node.textContent.startsWith('['), true);
});
