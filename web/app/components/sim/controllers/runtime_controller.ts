function requireFn(name: Unsafe, fn: Unsafe) {
  if (typeof fn !== 'function') {
    throw new Error(`createSimRuntimeController requires function: ${name}`);
  }
}

export function createSimRuntimeController({
  state,
  runtime,
  getBackendDef,
  currentRunnerPreset = null,
  fetchImpl = globalThis.fetch,
  webAssemblyApi = globalThis.WebAssembly
}: Unsafe = {}) {
  if (!state || !runtime) {
    throw new Error('createSimRuntimeController requires state and runtime');
  }
  requireFn('getBackendDef', getBackendDef);
  requireFn('fetchImpl', fetchImpl);
  if (!webAssemblyApi || typeof webAssemblyApi.instantiate !== 'function') {
    throw new Error('createSimRuntimeController requires webAssemblyApi.instantiate');
  }

  function resolveBackendDef(backend = state.backend) {
    const def = getBackendDef(backend);
    if (typeof currentRunnerPreset !== 'function') {
      return def;
    }

    const preset = currentRunnerPreset();
    let overridePath = '';

    if (backend === 'compiler') {
      overridePath = String(preset?.compilerWasmPath || '').trim();
    } else if (backend === 'arcilator') {
      overridePath = String(preset?.arcilatorWasmPath || '').trim();
    }

    if (!overridePath) {
      return def;
    }

    return {
      ...def,
      wasmPath: overridePath
    };
  }

  async function loadWasmInstance(backend = state.backend) {
    const def = resolveBackendDef(backend);
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
    const def = resolveBackendDef(backend);
    const instanceKey = `${backend}::${def.wasmPath}`;
    if (runtime.backendInstances.has(instanceKey)) {
      runtime.instance = runtime.backendInstances.get(instanceKey);
      return runtime.instance;
    }
    const instance = await loadWasmInstance(backend);
    runtime.backendInstances.set(instanceKey, instance);
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

  function initializeTrace(options: Unsafe = {}) {
    if (!runtime.sim) {
      return;
    }
    const enabled = options?.enabled === true;

    runtime.sim.trace_clear();
    runtime.sim.trace_clear_signals();
    runtime.sim.trace_all_signals();
    runtime.sim.trace_set_timescale('1ns');
    runtime.sim.trace_set_module_name('rhdl_top');
    if (enabled) {
      runtime.sim.trace_start();
      runtime.sim.trace_capture();
    } else {
      runtime.sim.trace_stop();
    }
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
