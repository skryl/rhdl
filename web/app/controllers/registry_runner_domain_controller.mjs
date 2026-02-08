export function createRunnerDomainController({
  getRunnerPreset,
  currentRunnerPreset,
  loadRunnerPreset,
  loadSample,
  loadRunnerIrBundle,
  updateIrSourceVisibility,
  getRunnerActionsController,
  ensureBackendInstance
} = {}) {
  return {
    getPreset: getRunnerPreset,
    currentPreset: currentRunnerPreset,
    loadPreset: loadRunnerPreset,
    loadSample,
    loadBundle: loadRunnerIrBundle,
    updateIrSourceVisibility,
    ensureBackendInstance,
    getActionsController: getRunnerActionsController
  };
}
