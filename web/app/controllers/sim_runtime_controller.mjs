function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createSimRuntimeController requires function: ${name}`);
  }
}

export function createSimRuntimeController({
  state,
  runtime,
  getBackendDef,
  fetchImpl = globalThis.fetch,
  webAssemblyApi = globalThis.WebAssembly
} = {}) {
  if (!state || !runtime) {
    throw new Error('createSimRuntimeController requires state and runtime');
  }
  requireFn('getBackendDef', getBackendDef);
  requireFn('fetchImpl', fetchImpl);
  if (!webAssemblyApi || typeof webAssemblyApi.instantiate !== 'function') {
    throw new Error('createSimRuntimeController requires webAssemblyApi.instantiate');
  }

  async function loadWasmInstance(backend = state.backend) {
    const def = getBackendDef(backend);
    const url = def.wasmPath;
    const response = await fetchImpl(url);

    if (!response.ok) {
      throw new Error(`Failed to fetch ${url}: ${response.status}`);
    }

    if (typeof webAssemblyApi.instantiateStreaming === 'function') {
      try {
        const streamResponse = typeof response.clone === 'function' ? response.clone() : response;
        const result = await webAssemblyApi.instantiateStreaming(streamResponse, {});
        return result.instance;
      } catch (_err) {
        // Fall back to instantiate(bytes).
      }
    }

    const bytes = await response.arrayBuffer();
    const result = await webAssemblyApi.instantiate(bytes, {});
    return result.instance;
  }

  async function ensureBackendInstance(backend = state.backend) {
    if (!(runtime.backendInstances instanceof Map)) {
      runtime.backendInstances = new Map();
    }
    if (runtime.backendInstances.has(backend)) {
      runtime.instance = runtime.backendInstances.get(backend);
      return runtime.instance;
    }
    const instance = await loadWasmInstance(backend);
    runtime.backendInstances.set(backend, instance);
    runtime.instance = instance;
    return instance;
  }

  function drainTrace() {
    if (!runtime.sim) {
      return;
    }
    const chunk = runtime.sim.trace_take_live_vcd();
    if (chunk && runtime.parser && typeof runtime.parser.ingest === 'function') {
      runtime.parser.ingest(chunk);
    }
  }

  function initializeTrace() {
    if (!runtime.sim) {
      return;
    }

    runtime.sim.trace_clear();
    runtime.sim.trace_clear_signals();
    runtime.sim.trace_all_signals();
    runtime.sim.trace_set_timescale('1ns');
    runtime.sim.trace_set_module_name('rhdl_top');
    runtime.sim.trace_start();
    runtime.sim.trace_capture();
    if (runtime.parser && typeof runtime.parser.reset === 'function') {
      runtime.parser.reset();
    }
    drainTrace();
  }

  return {
    loadWasmInstance,
    ensureBackendInstance,
    drainTrace,
    initializeTrace
  };
}
