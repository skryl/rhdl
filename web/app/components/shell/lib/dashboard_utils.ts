// @ts-nocheck
export function safeSlugToken(value: unknown) {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    || 'panel';
}

export function normalizeDashboardSpan(value: unknown, fallback = 'full') {
  if (value === 'half') {
    return 'half';
  }
  if (value === 'full') {
    return 'full';
  }
  return fallback === 'half' ? 'half' : 'full';
}

export function dashboardRowSignature(rowPanels: unknown) {
  return rowPanels
    .map((panel: unknown) => String(panel?.dataset?.layoutItemId || '').trim())
    .filter(Boolean)
    .join('|');
}

export function dashboardDropPosition(panel: unknown, event: unknown) {
  const rect = panel.getBoundingClientRect();
  const x = event.clientX - rect.left;
  const y = event.clientY - rect.top;
  const dx = x - rect.width * 0.5;
  const dy = y - rect.height * 0.5;
  const nx = rect.width > 0 ? dx / rect.width : 0;
  const ny = rect.height > 0 ? dy / rect.height : 0;
  if (Math.abs(nx) >= Math.abs(ny)) {
    return nx < 0 ? 'left' : 'right';
  }
  return ny < 0 ? 'above' : 'below';
}
