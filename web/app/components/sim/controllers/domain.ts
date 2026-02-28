export function createSimDomainController({
  setupP5,
  refreshStatus,
  initializeSimulator,
  initializeTrace,
  stepSimulation,
  runFrame,
  resetThroughputSampling,
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
    resetThroughputSampling,
    drainTrace,
    maskForWidth
  };
}
