// @ts-nocheck
export function parseDashboardLayouts(raw: unknown) {
  if (typeof raw !== 'string' || !raw.trim()) {
    return {};
  }
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return {};
    }
    return parsed;
  } catch (_err: unknown) {
    return {};
  }
}

export function serializeDashboardLayouts(layouts: unknown) {
  const value = layouts && typeof layouts === 'object' ? layouts : {};
  return JSON.stringify(value);
}

export function withDashboardRowHeight(layout: unknown, signature: unknown, heightPx: unknown, minHeight: unknown) {
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
