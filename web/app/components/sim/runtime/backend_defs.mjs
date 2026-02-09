export const BACKEND_DEFS = {
  interpreter: {
    id: 'interpreter',
    label: 'Interpreter',
    wasmPath: './assets/pkg/ir_interpreter.wasm',
    corePrefix: 'ir_sim',
    allocPrefix: 'ir_sim',
    apple2Prefix: 'apple2_interp_sim',
    createFn: 'ir_sim_create',
    destroyFn: 'ir_sim_destroy',
    freeErrorFn: 'ir_sim_free_error',
    freeStringFn: 'ir_sim_free_string'
  },
  jit: {
    id: 'jit',
    label: 'JIT',
    wasmPath: './assets/pkg/ir_jit.wasm',
    corePrefix: 'jit_sim',
    allocPrefix: 'jit_sim',
    apple2Prefix: 'apple2_jit_sim',
    createFn: 'jit_sim_create',
    destroyFn: 'jit_sim_destroy',
    freeErrorFn: 'jit_sim_free_error',
    freeStringFn: 'jit_sim_free_string'
  },
  compiler: {
    id: 'compiler',
    label: 'Compiler (AOT)',
    wasmPath: './assets/pkg/ir_compiler.wasm',
    corePrefix: 'ir_sim',
    allocPrefix: 'ir_sim',
    apple2Prefix: 'apple2_ir_sim',
    createFn: 'ir_sim_create',
    destroyFn: 'ir_sim_destroy',
    freeErrorFn: 'ir_sim_free_error',
    freeStringFn: 'ir_sim_free_string'
  }
};

export function getBackendDef(id) {
  if (id && BACKEND_DEFS[id]) {
    return BACKEND_DEFS[id];
  }
  return BACKEND_DEFS.interpreter;
}
