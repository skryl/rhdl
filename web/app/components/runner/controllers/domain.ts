export function createRunnerDomainController({
  getRunnerPreset,
  currentRunnerPreset,
  loadRunnerPreset,
  loadSample,
  loadRunnerIrBundle,
  updateIrSourceVisibility,
  getRunnerActionsController,
  ensureBackendInstance
}: Unsafe = {}) {
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
