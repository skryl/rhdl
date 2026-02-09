function normalizeSpan(normalizeDashboardSpan, value, fallback = 'full') {
  return normalizeDashboardSpan(value, fallback);
}

export function normalizeDashboardPanelSpans(panels, normalizeDashboardSpan, fallback = 'full') {
  let pendingHalf = null;
  for (const panel of panels) {
    const span = normalizeSpan(normalizeDashboardSpan, panel?.dataset?.layoutSpan, fallback);
    panel.dataset.layoutSpan = span;
    if (span === 'full') {
      if (pendingHalf) {
        pendingHalf.dataset.layoutSpan = 'full';
        pendingHalf = null;
      }
      continue;
    }
    if (!pendingHalf) {
      pendingHalf = panel;
      continue;
    }
    pendingHalf = null;
  }
  if (pendingHalf) {
    pendingHalf.dataset.layoutSpan = 'full';
  }
}

export function dashboardRowsFromPanels(panels, normalizeDashboardSpan, fallback = 'full') {
  const rows = [];
  let idx = 0;
  while (idx < panels.length) {
    const first = panels[idx];
    const firstSpan = normalizeSpan(normalizeDashboardSpan, first?.dataset?.layoutSpan, fallback);
    if (firstSpan === 'half') {
      const second = panels[idx + 1];
      if (second && normalizeSpan(normalizeDashboardSpan, second.dataset.layoutSpan, fallback) === 'half') {
        rows.push([first, second]);
        idx += 2;
        continue;
      }
      first.dataset.layoutSpan = 'full';
      rows.push([first]);
      idx += 1;
      continue;
    }
    rows.push([first]);
    idx += 1;
  }
  return rows;
}

export function snapshotDashboardPanelLayout(panels, normalizeDashboardSpan, defaultSpan = () => 'full') {
  const order = [];
  const spans = {};
  for (const panel of panels) {
    const itemId = String(panel?.dataset?.layoutItemId || '').trim();
    if (!itemId) {
      continue;
    }
    order.push(itemId);
    spans[itemId] = normalizeSpan(normalizeDashboardSpan, panel?.dataset?.layoutSpan, defaultSpan(panel));
  }
  return { order, spans };
}

export function applyDashboardDropSpanPolicy(position, draggedPanel, targetPanel) {
  if (!draggedPanel || !targetPanel) {
    return;
  }
  if (position === 'left' || position === 'right') {
    draggedPanel.dataset.layoutSpan = 'half';
    targetPanel.dataset.layoutSpan = 'half';
    return;
  }
  draggedPanel.dataset.layoutSpan = 'full';
  targetPanel.dataset.layoutSpan = 'full';
}
