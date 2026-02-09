export function parseDashboardLayouts(raw) {
  if (typeof raw !== 'string' || !raw.trim()) {
    return {};
  }
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return {};
    }
    return parsed;
  } catch (_err) {
    return {};
  }
}

export function serializeDashboardLayouts(layouts) {
  const value = layouts && typeof layouts === 'object' ? layouts : {};
  return JSON.stringify(value);
}

export function withDashboardRowHeight(layout, signature, heightPx, minHeight) {
  if (!signature) {
    return layout && typeof layout === 'object' ? layout : {};
  }
  const floor = Number.isFinite(minHeight) ? minHeight : 0;
  const height = Math.max(floor, Math.round(Number(heightPx) || 0));
  const base = layout && typeof layout === 'object' ? layout : {};
  const rowHeights = base.rowHeights && typeof base.rowHeights === 'object'
    ? { ...base.rowHeights }
    : {};
  rowHeights[signature] = height;
  return {
    ...base,
    rowHeights
  };
}
