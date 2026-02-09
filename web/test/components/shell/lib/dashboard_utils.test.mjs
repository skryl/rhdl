import test from 'node:test';
import assert from 'node:assert/strict';

import {
  safeSlugToken,
  normalizeDashboardSpan,
  dashboardRowSignature,
  dashboardDropPosition
} from '../../../../app/components/shell/lib/dashboard_utils.mjs';

test('safeSlugToken normalizes free-form labels', () => {
  assert.equal(safeSlugToken('Runner Debug'), 'runner_debug');
  assert.equal(safeSlugToken('  ##  '), 'panel');
  assert.equal(safeSlugToken('CPU/ALU#1'), 'cpu_alu_1');
});

test('normalizeDashboardSpan resolves invalid values with fallback', () => {
  assert.equal(normalizeDashboardSpan('half', 'full'), 'half');
  assert.equal(normalizeDashboardSpan('full', 'half'), 'full');
  assert.equal(normalizeDashboardSpan('weird', 'half'), 'half');
  assert.equal(normalizeDashboardSpan('weird', 'full'), 'full');
});

test('dashboardRowSignature is stable and skips blanks', () => {
  const rows = [
    { dataset: { layoutItemId: 'one' } },
    { dataset: { layoutItemId: '' } },
    { dataset: { layoutItemId: 'two' } }
  ];
  assert.equal(dashboardRowSignature(rows), 'one|two');
});

test('dashboardDropPosition resolves cardinal drop zones', () => {
  const panel = {
    getBoundingClientRect() {
      return { left: 0, top: 0, width: 200, height: 100 };
    }
  };

  assert.equal(dashboardDropPosition(panel, { clientX: 10, clientY: 50 }), 'left');
  assert.equal(dashboardDropPosition(panel, { clientX: 190, clientY: 50 }), 'right');
  assert.equal(dashboardDropPosition(panel, { clientX: 100, clientY: 10 }), 'above');
  assert.equal(dashboardDropPosition(panel, { clientX: 100, clientY: 95 }), 'below');
});
