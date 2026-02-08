function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createComponentSourceController requires function: ${name}`);
  }
}

export function createComponentSourceController({
  dom,
  state,
  currentRunnerPreset,
  normalizeComponentSourceBundle,
  normalizeComponentSchematicBundle,
  destroyComponentGraph
} = {}) {
  if (!dom || !state) {
    throw new Error('createComponentSourceController requires dom/state');
  }
  requireFn('currentRunnerPreset', currentRunnerPreset);
  requireFn('normalizeComponentSourceBundle', normalizeComponentSourceBundle);
  requireFn('normalizeComponentSchematicBundle', normalizeComponentSchematicBundle);
  requireFn('destroyComponentGraph', destroyComponentGraph);

  function setComponentSourceOverride(source = '', meta = null) {
    state.components.overrideSource = String(source || '');
    state.components.overrideMeta = meta || null;
  }

  function clearComponentSourceOverride() {
    setComponentSourceOverride('', null);
  }

  function clearComponentSourceBundle() {
    state.components.sourceBundle = null;
    state.components.sourceBundleByClass = new Map();
    state.components.sourceBundleByModule = new Map();
  }

  function setComponentSourceBundle(bundle) {
    const normalized = normalizeComponentSourceBundle(bundle);
    if (!normalized) {
      clearComponentSourceBundle();
      return;
    }
    state.components.sourceBundle = normalized;
    state.components.sourceBundleByClass = normalized.byClass || new Map();
    state.components.sourceBundleByModule = normalized.byModule || new Map();
  }

  function clearComponentSchematicBundle() {
    state.components.schematicBundle = null;
    state.components.schematicBundleByPath = new Map();
  }

  function setComponentSchematicBundle(bundle) {
    const normalized = normalizeComponentSchematicBundle(bundle);
    if (!normalized) {
      clearComponentSchematicBundle();
      return;
    }
    state.components.schematicBundle = normalized;
    state.components.schematicBundleByPath = normalized.byPath || new Map();
  }

  function resetComponentExplorerState() {
    state.components.model = null;
    state.components.selectedNodeId = null;
    state.components.parseError = '';
    state.components.sourceKey = '';
    state.components.graphFocusId = null;
    state.components.graphShowChildren = false;
    state.components.graphLastTap = null;
    state.components.graphHighlightedSignal = null;
    state.components.graphLiveValues = new Map();
    state.components.graphLayoutEngine = 'none';
    clearComponentSourceBundle();
    clearComponentSchematicBundle();
    destroyComponentGraph();
    if (dom.componentTree && typeof dom.componentTree.setFilter === 'function') {
      dom.componentTree.setFilter('', false);
    }
  }

  function currentComponentSourceText() {
    if (state.components.overrideSource) {
      return state.components.overrideSource;
    }
    return dom.irJson?.value || '';
  }

  function updateIrSourceVisibility() {
    const preset = currentRunnerPreset();
    const show = !!preset.usesManualIr;
    if (dom.irSourceSection) {
      dom.irSourceSection.hidden = !show;
    }
  }

  return {
    setComponentSourceOverride,
    clearComponentSourceOverride,
    resetComponentExplorerState,
    currentComponentSourceText,
    updateIrSourceVisibility,
    clearComponentSourceBundle,
    setComponentSourceBundle,
    clearComponentSchematicBundle,
    setComponentSchematicBundle
  };
}
