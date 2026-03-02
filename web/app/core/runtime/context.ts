import type { RuntimeContext, RuntimeParserFactory } from '../../types/runtime';

export function createRuntimeContext(createParser: RuntimeParserFactory = null): RuntimeContext {
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
