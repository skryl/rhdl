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
}: any = {}) {
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
