export const BACKEND_DEFS = {
  interpreter: {
    id: 'interpreter',
    label: 'Interpreter',
    wasmPath: './assets/pkg/ir_interpreter.wasm',
    corePrefix: 'sim',
    allocPrefix: 'sim',
    createFn: 'sim_create',
    destroyFn: 'sim_destroy',
    freeErrorFn: 'sim_free_error'
  },
  jit: {
    id: 'jit',
    label: 'JIT',
    wasmPath: './assets/pkg/ir_jit.wasm',
    corePrefix: 'sim',
    allocPrefix: 'sim',
    createFn: 'sim_create',
    destroyFn: 'sim_destroy',
    freeErrorFn: 'sim_free_error'
  },
  compiler: {
    id: 'compiler',
    label: 'Compiler (AOT)',
    wasmPath: './assets/pkg/ir_compiler.wasm',
    corePrefix: 'sim',
    allocPrefix: 'sim',
    createFn: 'sim_create',
    destroyFn: 'sim_destroy',
    freeErrorFn: 'sim_free_error'
  }
};

export function getBackendDef(id) {
  if (id && BACKEND_DEFS[id]) {
    return BACKEND_DEFS[id];
  }
  return BACKEND_DEFS.interpreter;
}
