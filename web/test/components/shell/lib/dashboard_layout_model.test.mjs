import test from 'node:test';
import assert from 'node:assert/strict';

import {
  normalizeDashboardPanelSpans,
  dashboardRowsFromPanels,
  snapshotDashboardPanelLayout,
  applyDashboardDropSpanPolicy
} from '../../../../app/components/shell/lib/dashboard_layout_model.mjs';

function panel(id, span = 'full') {
  return {
    dataset: {
      layoutItemId: id,
      layoutSpan: span
    }
  };
}

const normalizeSpan = (value, fallback = 'full') => (value === 'half' ? 'half' : fallback);

test('normalizeDashboardPanelSpans fixes dangling half rows', () => {
  const panels = [panel('a', 'half'), panel('b', 'full'), panel('c', 'half')];
  normalizeDashboardPanelSpans(panels, normalizeSpan, 'full');
  assert.equal(panels[0].dataset.layoutSpan, 'full');
  assert.equal(panels[1].dataset.layoutSpan, 'full');
  assert.equal(panels[2].dataset.layoutSpan, 'full');
});

test('dashboardRowsFromPanels groups paired half panels', () => {
  const panels = [panel('a', 'half'), panel('b', 'half'), panel('c', 'full')];
  const rows = dashboardRowsFromPanels(panels, normalizeSpan, 'full');
  assert.deepEqual(rows.map((row) => row.map((entry) => entry.dataset.layoutItemId)), [['a', 'b'], ['c']]);
});

test('snapshotDashboardPanelLayout captures order + normalized spans', () => {
  const panels = [panel('a', 'full'), panel('b', 'half')];
  const snapshot = snapshotDashboardPanelLayout(
    panels,
    normalizeSpan,
    () => 'full'
  );
  assert.deepEqual(snapshot.order, ['a', 'b']);
  assert.deepEqual(snapshot.spans, { a: 'full', b: 'half' });
});

test('applyDashboardDropSpanPolicy sets spans by direction', () => {
  const dragged = panel('drag', 'full');
  const target = panel('target', 'full');
  applyDashboardDropSpanPolicy('left', dragged, target);
  assert.equal(dragged.dataset.layoutSpan, 'half');
  assert.equal(target.dataset.layoutSpan, 'half');

  applyDashboardDropSpanPolicy('below', dragged, target);
  assert.equal(dragged.dataset.layoutSpan, 'full');
  assert.equal(target.dataset.layoutSpan, 'full');
});
