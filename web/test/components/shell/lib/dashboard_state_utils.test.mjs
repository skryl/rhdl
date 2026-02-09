import test from 'node:test';
import assert from 'node:assert/strict';

import {
  parseDashboardLayouts,
  serializeDashboardLayouts,
  withDashboardRowHeight
} from '../../../../app/components/shell/lib/dashboard_state_utils.mjs';

test('parseDashboardLayouts tolerates invalid input', () => {
  assert.deepEqual(parseDashboardLayouts(''), {});
  assert.deepEqual(parseDashboardLayouts('{bad'), {});
  assert.deepEqual(parseDashboardLayouts('[]'), {});
  assert.deepEqual(parseDashboardLayouts('{"a":1}'), { a: 1 });
});

test('serializeDashboardLayouts always returns json object text', () => {
  assert.equal(serializeDashboardLayouts({ a: 1 }), '{"a":1}');
  assert.equal(serializeDashboardLayouts(null), '{}');
});

test('withDashboardRowHeight writes rounded row heights with floor', () => {
  const next = withDashboardRowHeight({ order: ['x'] }, 'rowA', 167.9, 140);
  assert.equal(next.order[0], 'x');
  assert.equal(next.rowHeights.rowA, 168);

  const clamped = withDashboardRowHeight({}, 'rowB', 12, 140);
  assert.equal(clamped.rowHeights.rowB, 140);
});
