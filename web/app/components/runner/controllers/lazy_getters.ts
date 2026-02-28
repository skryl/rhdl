import { parseIrMeta } from '../../../core/lib/ir_meta_utils';
import { createRunnerBundleLoader } from './bundle_controller';
import { createRunnerActionsController } from './actions_controller';

function requireFn(name: any, fn: any) {
  if (typeof fn !== 'function') {
    throw new Error(`createRunnerLazyGetters requires function: ${name}`);
  }
}

export function createRunnerLazyGetters({
  dom,
  state,
  setBackendState,
  ensureBackendInstance,
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
}: any = {}) {
  if (!dom || !state) {
    throw new Error('createRunnerLazyGetters requires dom/state');
  }
  requireFn('setBackendState', setBackendState);
  requireFn('ensureBackendInstance', ensureBackendInstance);
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

  let runnerBundleLoader: any = null;
  let runnerActionsController: any = null;

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
        setBackendState,
        ensureBackendInstance,
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
