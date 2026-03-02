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

  function resolveAssetCandidates(path: string) {
    const trimmed = String(path || '').trim();
    if (!trimmed) {
      return [];
    }

    const urls = [trimmed];
    const seen = new Set(urls);
    const addCandidate = (candidate: unknown) => {
      const url = String(candidate || '').trim();
      if (!url || seen.has(url)) {
        return;
      }
      seen.add(url);
      urls.push(url);
    };

    const addFromBase = (base: unknown) => {
      try {
        addCandidate(new URL(trimmed, String(base)).toString());
      } catch (_error) {
        // ignore invalid bases.
      }
    };

    if (typeof document === 'object' && document?.baseURI) {
      addFromBase(document.baseURI);
    }
    if (typeof location === 'object' && location?.href) {
      addFromBase(location.href);
    }
    addFromBase(import.meta.url);

    if (trimmed.startsWith('./')) {
      addCandidate(trimmed.slice(2));
      addCandidate(`/${trimmed.slice(2)}`);
    }

    return urls;
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
    const candidateUrls = resolveAssetCandidates(def.wasmPath);
    let lastResponse: Response | null = null;
    const failures: string[] = [];
    const isUsableResponse = (response: Response) => response.ok || response.status === 0;

    for (const url of candidateUrls) {
      try {
        const response = await fetchImpl(url);
        if (isUsableResponse(response)) {
          try {
            if (typeof webAssemblyApi.instantiateStreaming === 'function') {
              try {
                const streamResponse = typeof response.clone === 'function' ? response.clone() : response;
                const result = await webAssemblyApi.instantiateStreaming(streamResponse, {});
                return result.instance;
              } catch (_err) {
                // Fall back to instantiate(bytes) for this successful fetch.
              }
            }

            const bytes = await response.arrayBuffer();
            const result = await webAssemblyApi.instantiate(bytes, {});
            return result.instance;
          } catch (err: unknown) {
            failures.push(`${url} -> ${err instanceof Error ? err.message : String(err)}`);
            lastResponse = response;
          }
        }

        const detail = response.status === 0
          ? `${response.type}/${response.url || url}`
          : `${response.status}`;
        failures.push(`${url} -> ${detail}`);
        lastResponse = response;
      } catch (err: unknown) {
        failures.push(`${url} -> ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    const lastRequestUrl = lastResponse?.url || candidateUrls[candidateUrls.length - 1] || def.wasmPath;
    throw new Error(`Failed to fetch ${lastRequestUrl}: ${failures.join(', ') || 'No usable fetch URL'}`);

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
