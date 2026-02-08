import test from 'node:test';
import assert from 'node:assert/strict';

import { createSimRuntimeController } from '../../app/controllers/sim_runtime_controller.mjs';

function makeOkResponse({ clone = true } = {}) {
  const base = {
    ok: true,
    status: 200,
    async arrayBuffer() {
      return new ArrayBuffer(8);
    }
  };
  if (clone) {
    base.clone = () => base;
  }
  return base;
}

test('ensureBackendInstance caches loaded instance', async () => {
  let fetchCalls = 0;
  let instantiateCalls = 0;
  const instance = { id: 'compiler-instance' };
  const controller = createSimRuntimeController({
    state: { backend: 'compiler' },
    runtime: { backendInstances: new Map(), instance: null, sim: null, parser: null },
    getBackendDef: () => ({ wasmPath: '/compiler.wasm' }),
    fetchImpl: async () => {
      fetchCalls += 1;
      return makeOkResponse();
    },
    webAssemblyApi: {
      async instantiate(bytes) {
        void bytes;
        instantiateCalls += 1;
        return { instance };
      }
    }
  });

  const first = await controller.ensureBackendInstance('compiler');
  const second = await controller.ensureBackendInstance('compiler');

  assert.equal(first, instance);
  assert.equal(second, instance);
  assert.equal(fetchCalls, 1);
  assert.equal(instantiateCalls, 1);
});

test('loadWasmInstance prefers instantiateStreaming when available', async () => {
  let instantiateCalls = 0;
  let streamCalls = 0;
  const streamInstance = { id: 'stream' };
  const controller = createSimRuntimeController({
    state: { backend: 'compiler' },
    runtime: { backendInstances: new Map(), instance: null, sim: null, parser: null },
    getBackendDef: () => ({ wasmPath: '/compiler.wasm' }),
    fetchImpl: async () => makeOkResponse(),
    webAssemblyApi: {
      async instantiateStreaming(response) {
        void response;
        streamCalls += 1;
        return { instance: streamInstance };
      },
      async instantiate(bytes) {
        void bytes;
        instantiateCalls += 1;
        return { instance: { id: 'fallback' } };
      }
    }
  });

  const loaded = await controller.loadWasmInstance('compiler');
  assert.equal(loaded, streamInstance);
  assert.equal(streamCalls, 1);
  assert.equal(instantiateCalls, 0);
});

test('loadWasmInstance falls back when instantiateStreaming fails', async () => {
  let instantiateCalls = 0;
  let streamCalls = 0;
  const fallbackInstance = { id: 'fallback' };
  const controller = createSimRuntimeController({
    state: { backend: 'compiler' },
    runtime: { backendInstances: new Map(), instance: null, sim: null, parser: null },
    getBackendDef: () => ({ wasmPath: '/compiler.wasm' }),
    fetchImpl: async () => makeOkResponse(),
    webAssemblyApi: {
      async instantiateStreaming() {
        streamCalls += 1;
        throw new Error('stream fail');
      },
      async instantiate(bytes) {
        void bytes;
        instantiateCalls += 1;
        return { instance: fallbackInstance };
      }
    }
  });

  const loaded = await controller.loadWasmInstance('compiler');
  assert.equal(loaded, fallbackInstance);
  assert.equal(streamCalls, 1);
  assert.equal(instantiateCalls, 1);
});

test('loadWasmInstance throws on non-ok response', async () => {
  const controller = createSimRuntimeController({
    state: { backend: 'compiler' },
    runtime: { backendInstances: new Map(), instance: null, sim: null, parser: null },
    getBackendDef: () => ({ wasmPath: '/compiler.wasm' }),
    fetchImpl: async () => ({ ok: false, status: 404 }),
    webAssemblyApi: {
      async instantiate() {
        return { instance: null };
      }
    }
  });

  await assert.rejects(() => controller.loadWasmInstance('compiler'), /Failed to fetch \/compiler\.wasm: 404/);
});

test('initializeTrace invokes trace setup and drains chunk into parser', () => {
  const calls = [];
  const ingested = [];
  const runtime = {
    backendInstances: new Map(),
    instance: null,
    sim: {
      trace_clear() {
        calls.push('trace_clear');
      },
      trace_clear_signals() {
        calls.push('trace_clear_signals');
      },
      trace_all_signals() {
        calls.push('trace_all_signals');
      },
      trace_set_timescale(value) {
        calls.push(`trace_set_timescale:${value}`);
      },
      trace_set_module_name(value) {
        calls.push(`trace_set_module_name:${value}`);
      },
      trace_start() {
        calls.push('trace_start');
      },
      trace_capture() {
        calls.push('trace_capture');
      },
      trace_take_live_vcd() {
        calls.push('trace_take_live_vcd');
        return 'chunk-data';
      }
    },
    parser: {
      reset() {
        calls.push('parser_reset');
      },
      ingest(chunk) {
        ingested.push(chunk);
      }
    }
  };
  const controller = createSimRuntimeController({
    state: { backend: 'compiler' },
    runtime,
    getBackendDef: () => ({ wasmPath: '/compiler.wasm' }),
    fetchImpl: async () => makeOkResponse(),
    webAssemblyApi: {
      async instantiate(bytes) {
        void bytes;
        return { instance: { id: 1 } };
      }
    }
  });

  controller.initializeTrace();
  assert.deepEqual(ingested, ['chunk-data']);
  assert.deepEqual(calls, [
    'trace_clear',
    'trace_clear_signals',
    'trace_all_signals',
    'trace_set_timescale:1ns',
    'trace_set_module_name:rhdl_top',
    'trace_start',
    'trace_capture',
    'parser_reset',
    'trace_take_live_vcd'
  ]);
});
