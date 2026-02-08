import test from 'node:test';
import assert from 'node:assert/strict';

import { bindDashboardPanelEvents } from '../../app/bindings/dashboard_bindings.mjs';

function makeTarget() {
  return new EventTarget();
}

test('bindDashboardPanelEvents wires and tears down drag/drop handlers', () => {
  const calls = [];
  const header = makeTarget();
  const panel = makeTarget();

  const teardown = bindDashboardPanelEvents({
    header,
    panel,
    onDragStart: () => calls.push('dragstart'),
    onDragEnd: () => calls.push('dragend'),
    onDragOver: () => calls.push('dragover'),
    onDrop: () => calls.push('drop')
  });

  header.dispatchEvent(new Event('dragstart'));
  header.dispatchEvent(new Event('dragend'));
  panel.dispatchEvent(new Event('dragover'));
  panel.dispatchEvent(new Event('drop'));

  assert.deepEqual(calls, ['dragstart', 'dragend', 'dragover', 'drop']);

  teardown();
  header.dispatchEvent(new Event('dragstart'));
  panel.dispatchEvent(new Event('drop'));
  assert.deepEqual(calls, ['dragstart', 'dragend', 'dragover', 'drop']);
});
