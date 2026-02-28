// Live signal activity updater for RenderList.
// Operates on RenderList element properties directly.

export function updateRenderActivity({
  renderList,
  signalLiveValueByName,
  toBigInt,
  highlightedSignal,
  previousValues
} = {}) {
  if (!renderList || typeof signalLiveValueByName !== 'function' || typeof toBigInt !== 'function') {
    return previousValues || new Map();
  }

  const nextValues = new Map();
  const highlight = highlightedSignal;

  // Update nets and pins
  const nodeElements = [...renderList.nets, ...renderList.pins];
  for (const el of nodeElements) {
    const valueKey = el.valueKey || '';
    const liveName = el.liveName || '';
    const signalName = el.signalName || '';
    if (!valueKey) continue;

    const value = liveName ? signalLiveValueByName(liveName) : null;
    const valueText = value == null ? '' : toBigInt(value).toString();
    const previous = previousValues ? previousValues.get(valueKey) : undefined;
    const toggled = previous !== undefined && previous !== valueText;
    const active = valueText !== '' && valueText !== '0';
    const selected = !!highlight && (
      (!!highlight.liveName && liveName === highlight.liveName) ||
      (!!highlight.signalName && signalName === highlight.signalName)
    );

    el.active = active;
    el.toggled = toggled;
    el.selected = selected;
    nextValues.set(valueKey, valueText);
  }

  // Update wires
  for (const wire of renderList.wires) {
    const valueKey = wire.valueKey || '';
    const signalName = wire.signalName || '';
    const liveName = wire.liveName || '';
    const valueText = valueKey ? (nextValues.get(valueKey) || '') : '';
    const previous = valueKey ? (previousValues ? previousValues.get(valueKey) : undefined) : undefined;
    const toggled = valueKey && previous !== undefined && previous !== valueText;
    const active = valueText !== '' && valueText !== '0';

    const highlighted = !!highlight && (
      (!!highlight.liveName && liveName === highlight.liveName) ||
      (!!highlight.signalName && signalName === highlight.signalName)
    );

    wire.active = active;
    wire.toggled = !!toggled;
    wire.selected = highlighted;
  }

  return nextValues;
}
