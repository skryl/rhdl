import { fetchTextAsset } from '../../../core/lib/fetch_asset.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createRunnerActionsController requires function: ${name}`);
  }
}

export function createRunnerActionsController({
  dom,
  getRunnerPreset,
  setRunnerPresetState,
  updateIrSourceVisibility,
  loadRunnerIrBundle,
  initializeSimulator,
  applyRunnerDefaults,
  clearComponentSourceOverride,
  resetComponentExplorerState,
  log,
  isComponentTabActive,
  refreshComponentExplorer,
  clearComponentSourceBundle,
  clearComponentSchematicBundle,
  setComponentSourceBundle,
  setComponentSchematicBundle,
  setActiveTab,
  refreshStatus,
  fetchImpl = globalThis.fetch
} = {}) {
  if (!dom) {
    throw new Error('createRunnerActionsController requires dom');
  }
  requireFn('getRunnerPreset', getRunnerPreset);
  requireFn('setRunnerPresetState', setRunnerPresetState);
  requireFn('updateIrSourceVisibility', updateIrSourceVisibility);
  requireFn('loadRunnerIrBundle', loadRunnerIrBundle);
  requireFn('initializeSimulator', initializeSimulator);
  requireFn('applyRunnerDefaults', applyRunnerDefaults);
  requireFn('clearComponentSourceOverride', clearComponentSourceOverride);
  requireFn('resetComponentExplorerState', resetComponentExplorerState);
  requireFn('log', log);
  requireFn('isComponentTabActive', isComponentTabActive);
  requireFn('refreshComponentExplorer', refreshComponentExplorer);
  requireFn('clearComponentSourceBundle', clearComponentSourceBundle);
  requireFn('clearComponentSchematicBundle', clearComponentSchematicBundle);
  requireFn('setComponentSourceBundle', setComponentSourceBundle);
  requireFn('setComponentSchematicBundle', setComponentSchematicBundle);
  requireFn('setActiveTab', setActiveTab);
  requireFn('refreshStatus', refreshStatus);
  requireFn('fetchImpl', fetchImpl);

  async function loadSample(samplePathOverride = null) {
    const samplePath = samplePathOverride || dom.sampleSelect?.value || './assets/fixtures/cpu/ir/cpu_lib_hdl.json';
    const sampleLabel = dom.sampleSelect?.selectedOptions?.[0]?.textContent?.trim() || samplePath;
    try {
      dom.irJson.value = await fetchTextAsset(samplePath, `sample ${samplePath}`, fetchImpl);
      clearComponentSourceOverride();
      resetComponentExplorerState();
      log(`Loaded sample IR: ${sampleLabel}`);
      if (isComponentTabActive()) {
        refreshComponentExplorer();
      }
    } catch (err) {
      log(`Failed to load sample (${samplePath}): ${err.message || err}`);
    }
  }

  async function loadRunnerPreset(options = {}) {
    const {
      presetOverride = null,
      logLoad = true,
      setPreferredTab = true
    } = options;
    const preset = presetOverride || getRunnerPreset(dom.runnerSelect?.value);
    if (dom.runnerSelect) {
      dom.runnerSelect.value = preset.id;
    }
    setRunnerPresetState(preset.id);
    updateIrSourceVisibility();
    try {
      let bundle = null;
      if (preset.usesManualIr) {
        if (!String(dom.irJson?.value || '').trim()) {
          await loadSample(preset.samplePath || null);
        }
        clearComponentSourceOverride();
        bundle = {
          simJson: String(dom.irJson?.value || '').trim(),
          explorerJson: String(dom.irJson?.value || '').trim(),
          explorerMeta: null,
          sourceBundle: null,
          schematicBundle: null
        };
      } else {
        bundle = await loadRunnerIrBundle(preset, { logLoad: !!logLoad });
      }

      await initializeSimulator({
        preset,
        simJson: bundle.simJson,
        explorerSource: bundle.explorerJson,
        explorerMeta: bundle.explorerMeta,
        componentSourceBundle: bundle.sourceBundle || null,
        componentSchematicBundle: bundle.schematicBundle || null
      });
      if (setPreferredTab) {
        setActiveTab(preset.preferredTab || 'vcdTab');
      }
      await applyRunnerDefaults(preset);
    } catch (err) {
      log(`Failed to load runner ${preset.label}: ${err.message || err}`);
      return;
    }
    refreshStatus();
  }

  async function preloadStartPreset(startPreset) {
    if (!startPreset || startPreset.usesManualIr) {
      clearComponentSourceBundle();
      clearComponentSchematicBundle();
      await loadSample(startPreset?.samplePath || null);
      return;
    }
    const preloadBundle = await loadRunnerIrBundle(startPreset, { logLoad: false });
    setComponentSourceBundle(preloadBundle.sourceBundle || null);
    setComponentSchematicBundle(preloadBundle.schematicBundle || null);
  }

  return {
    loadSample,
    loadRunnerPreset,
    preloadStartPreset
  };
}
