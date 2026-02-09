export function createSimDomainController({
  setupP5,
  refreshStatus,
  initializeSimulator,
  initializeTrace,
  stepSimulation,
  runFrame,
  drainTrace,
  maskForWidth
} = {}) {
  return {
    setupP5,
    refreshStatus,
    initializeSimulator,
    initializeTrace,
    step: stepSimulation,
    runFrame,
    drainTrace,
    maskForWidth
  };
}
