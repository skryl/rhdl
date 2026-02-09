export function createRuntimeContext(createParser = null) {
  const parser = typeof createParser === 'function' ? createParser() : null;
  return {
    instance: null,
    backendInstances: new Map(),
    sim: null,
    waveformP5: null,
    parser,
    irMeta: null,
    uiTeardowns: []
  };
}
