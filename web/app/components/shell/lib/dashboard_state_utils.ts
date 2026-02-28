export function parseDashboardLayouts(raw: any) {
  if (typeof raw !== 'string' || !raw.trim()) {
    return {};
  }
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return {};
    }
    return parsed;
  } catch (_err: any) {
    return {};
  }
}

export function serializeDashboardLayouts(layouts: any) {
  const value = layouts && typeof layouts === 'object' ? layouts : {};
  return JSON.stringify(value);
}

export function withDashboardRowHeight(layout: any, signature: any, heightPx: any, minHeight: any) {
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
