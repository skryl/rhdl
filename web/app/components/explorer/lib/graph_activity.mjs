export function updateGraphActivity({
  cy,
  state,
  signalLiveValueByName,
  toBigInt
} = {}) {
  if (!cy || !state || typeof signalLiveValueByName !== 'function' || typeof toBigInt !== 'function') {
    return;
  }

  const nextValues = new Map();
  const highlight = state.components.graphHighlightedSignal;

  cy.batch(() => {
    cy.nodes('.schem-net, .schem-pin').forEach((node) => {
      const valueKey = String(node.data('valueKey') || '');
      const liveName = String(node.data('liveName') || '');
      const signalName = String(node.data('signalName') || '');
      if (!valueKey) {
        return;
      }
      const value = liveName ? signalLiveValueByName(liveName) : null;
      const valueText = value == null ? '' : toBigInt(value).toString();
      const previous = state.components.graphLiveValues.get(valueKey);
      const toggled = previous !== undefined && previous !== valueText;
      const active = valueText !== '' && valueText !== '0';
      const selected = !!highlight && (
        (!!highlight.liveName && liveName === highlight.liveName)
        || (!!highlight.signalName && signalName === highlight.signalName)
      );

      if (node.hasClass('schem-net')) {
        node.toggleClass('net-active', active);
        node.toggleClass('net-toggled', toggled);
        node.toggleClass('net-selected', selected);
      }
      if (node.hasClass('schem-pin')) {
        node.toggleClass('pin-active', active);
        node.toggleClass('pin-toggled', toggled);
        node.toggleClass('pin-selected', selected);
      }
      nextValues.set(valueKey, valueText);
    });

    cy.edges('.schem-wire').forEach((edge) => {
      const valueKey = String(edge.data('valueKey') || '');
      const signalName = String(edge.data('signalName') || '');
      const liveName = String(edge.data('liveName') || '');
      const valueText = valueKey ? (nextValues.get(valueKey) || '') : '';
      const previous = valueKey ? state.components.graphLiveValues.get(valueKey) : undefined;
      const toggled = valueKey && previous !== undefined && previous !== valueText;
      const active = valueText !== '' && valueText !== '0';

      const highlighted = !!highlight && (
        (!!highlight.liveName && liveName === highlight.liveName)
        || (!!highlight.signalName && signalName === highlight.signalName)
      );

      edge.toggleClass('wire-active', active);
      edge.toggleClass('wire-toggled', !!toggled);
      edge.toggleClass('wire-selected', highlighted);
    });
  });

  state.components.graphLiveValues = nextValues;
}
