export function createRunnerDomainController({
  getRunnerPreset,
  currentRunnerPreset,
  loadRunnerPreset,
  loadSample,
  loadRunnerIrBundle,
  updateIrSourceVisibility,
  getRunnerActionsController,
  ensureBackendInstance
}: any = {}) {
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
