export function resolveComponentRefreshPlan(activeTab: unknown) {
  const tab = String(activeTab || '');
  if (tab === 'componentTab') {
    return {
      renderTree: true,
      renderInspector: true,
      renderGraph: false
    };
  }
  if (tab === 'componentGraphTab') {
    return {
      renderTree: false,
      renderInspector: false,
      renderGraph: true
    };
  }
  return {
    renderTree: false,
    renderInspector: false,
    renderGraph: false
  };
}
