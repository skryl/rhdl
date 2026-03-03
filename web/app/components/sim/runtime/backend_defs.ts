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
  },
  arcilator: {
    id: 'arcilator',
    label: 'Arcilator (CIRCT)',
    wasmPath: './assets/pkg/apple2_arcilator.wasm',
    corePrefix: 'sim',
    allocPrefix: 'sim',
    createFn: 'sim_create',
    destroyFn: 'sim_destroy',
    freeErrorFn: 'sim_free_error'
  },
  verilator: {
    id: 'verilator',
    label: 'Verilator',
    wasmPath: './assets/pkg/apple2_verilator.wasm',
    corePrefix: 'sim',
    allocPrefix: 'sim',
    createFn: 'sim_create',
    destroyFn: 'sim_destroy',
    freeErrorFn: 'sim_free_error'
  }
};

export function getBackendDef(id: Unsafe) {
  if (id && (BACKEND_DEFS as Record<string, Unsafe>)[id]) {
    return (BACKEND_DEFS as Record<string, Unsafe>)[id];
  }
  return BACKEND_DEFS.interpreter;
}
