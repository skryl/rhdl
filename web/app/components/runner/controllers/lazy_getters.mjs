import { parseIrMeta } from '../../../core/lib/ir_meta_utils.mjs';
import { createRunnerBundleLoader } from './bundle_controller.mjs';
import { createRunnerActionsController } from './actions_controller.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createRunnerLazyGetters requires function: ${name}`);
  }
}

export function createRunnerLazyGetters({
  dom,
  state,
  setRunnerPresetState,
  fetchImpl,
  log,
  getRunnerPreset,
  updateIrSourceVisibility,
  loadRunnerIrBundle,
  initializeSimulator,
  applyRunnerDefaults,
  clearComponentSourceOverride,
  resetComponentExplorerState,
  isComponentTabActive,
  refreshComponentExplorer,
  clearComponentSourceBundle,
  clearComponentSchematicBundle,
  setComponentSourceBundle,
  setComponentSchematicBundle,
  setActiveTab,
  refreshStatus
} = {}) {
  if (!dom || !state) {
    throw new Error('createRunnerLazyGetters requires dom/state');
  }
  requireFn('setRunnerPresetState', setRunnerPresetState);
  requireFn('fetchImpl', fetchImpl);
  requireFn('log', log);
  requireFn('getRunnerPreset', getRunnerPreset);
  requireFn('updateIrSourceVisibility', updateIrSourceVisibility);
  requireFn('loadRunnerIrBundle', loadRunnerIrBundle);
  requireFn('initializeSimulator', initializeSimulator);
  requireFn('applyRunnerDefaults', applyRunnerDefaults);
  requireFn('clearComponentSourceOverride', clearComponentSourceOverride);
  requireFn('resetComponentExplorerState', resetComponentExplorerState);
  requireFn('isComponentTabActive', isComponentTabActive);
  requireFn('refreshComponentExplorer', refreshComponentExplorer);
  requireFn('clearComponentSourceBundle', clearComponentSourceBundle);
  requireFn('clearComponentSchematicBundle', clearComponentSchematicBundle);
  requireFn('setComponentSourceBundle', setComponentSourceBundle);
  requireFn('setComponentSchematicBundle', setComponentSchematicBundle);
  requireFn('setActiveTab', setActiveTab);
  requireFn('refreshStatus', refreshStatus);

  let runnerBundleLoader = null;
  let runnerActionsController = null;

  function getRunnerBundleLoader() {
    if (!runnerBundleLoader) {
      runnerBundleLoader = createRunnerBundleLoader({
        dom,
        parseIrMeta,
        resetComponentExplorerState,
        log,
        fetchImpl
      });
    }
    return runnerBundleLoader;
  }

  function getRunnerActionsController() {
    if (!runnerActionsController) {
      runnerActionsController = createRunnerActionsController({
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
        fetchImpl
      });
    }
    return runnerActionsController;
  }

  return {
    getRunnerBundleLoader,
    getRunnerActionsController
  };
}
