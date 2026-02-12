export function createRuntimeContext(createParser = null) {
  const parser = typeof createParser === 'function' ? createParser() : null;
  return {
    instance: null,
    backendInstances: new Map(),
    sim: null,
    throughput: {
      cyclesPerSecond: 0,
      lastSampleTimeMs: null,
      lastSampleCycle: 0
    },
    waveformP5: null,
    parser,
    irMeta: null,
    uiTeardowns: []
  };
}
