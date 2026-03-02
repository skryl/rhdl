#!/usr/bin/env bun
// Headless RISC-V WASM benchmark harness.
//
// Supports:
// 1) Rust AOT compiler backend (WasmIrSimulator ABI, requires IR JSON arg)
// 2) Arcilator backend (lightweight sim_* ABI, no IR JSON)
//
// Usage:
//   bun run web/bench/riscv_wasm_bench.ts <wasm_path> <kernel_path> <fs_path> <cycles> [ir_json_path]

import { readFileSync } from 'node:fs';
import { performance } from 'node:perf_hooks';

const RUNNER_MEM_OP_LOAD = 0;
const RUNNER_MEM_SPACE_MAIN = 0;
const RUNNER_MEM_SPACE_ROM = 1;
const RUNNER_MEM_SPACE_DISK = 7;

const RUNNER_CONTROL_SET_RESET_VECTOR = 0;
const RUNNER_PROBE_KIND = 0;

const SIM_EXEC_RESET = 5;
const SIM_EXEC_SIGNAL_COUNT = 7;

const MEM_TYPE_INST = 0;
const MEM_TYPE_DATA = 1;
const RISCV_RESET_PC = 0x80000000 >>> 0;
const DEFAULT_MEM_SIZE = 16 * 1024 * 1024;

function n(v) {
  return typeof v === 'bigint' ? Number(v) : (v ?? 0);
}

function alloc(e, size) {
  return n(e.sim_wasm_alloc(Math.max(1, size)));
}

function dealloc(e, ptr, size) {
  if (ptr) e.sim_wasm_dealloc(ptr, Math.max(1, size));
}

function writeBytes(e, data, ptr) {
  new Uint8Array(e.memory.buffer).set(data, ptr);
}

function createWasiImports(getMemory) {
  function writeU32(ptr, value) {
    const memory = getMemory();
    if (!memory || !ptr) return;
    new DataView(memory.buffer).setUint32(n(ptr), value >>> 0, true);
  }

  function writeU64(ptr, value) {
    const memory = getMemory();
    if (!memory || !ptr) return;
    new DataView(memory.buffer).setBigUint64(n(ptr), BigInt(value), true);
  }

  return {
    proc_exit(code) {
      throw new Error(`WASI proc_exit(${n(code)}) called`);
    },
    clock_time_get(_clockId, _precision, outPtr) {
      writeU64(outPtr, BigInt(Date.now()) * 1_000_000n);
      return 0;
    },
    fd_write(_fd, _iovs, _iovsLen, nwrittenPtr) {
      writeU32(nwrittenPtr, 0);
      return 0;
    },
    fd_read(_fd, _iovs, _iovsLen, nreadPtr) {
      writeU32(nreadPtr, 0);
      return 0;
    },
    fd_close(_fd) {
      return 0;
    },
    fd_seek(_fd, _offset, _whence, newOffsetPtr) {
      writeU64(newOffsetPtr, 0n);
      return 0;
    }
  };
}

async function instantiateWasm(wasmBytes) {
  const module = await WebAssembly.compile(wasmBytes);
  const imports = WebAssembly.Module.imports(module);
  const hasWasi = imports.some((entry) => entry.module === 'wasi_snapshot_preview1');
  const hasEnv = imports.some((entry) => entry.module === 'env');

  let instance = null;
  const importObject = {};
  if (hasWasi) {
    importObject.wasi_snapshot_preview1 = createWasiImports(() => instance?.exports?.memory || null);
  }
  if (hasEnv) {
    importObject.env = {
      emscripten_notify_memory_growth(_index) {
        return;
      }
    };
  }

  instance = await WebAssembly.instantiate(module, importObject);
  return instance;
}

function readCString(mem, ptr) {
  let end = ptr;
  while (end < mem.length && mem[end] !== 0) end += 1;
  return new TextDecoder().decode(mem.subarray(ptr, end));
}

function patchPhystopForFastBoot(bytes) {
  // Match HeadlessRunner#patch_phystop_for_fast_boot!
  // LUI imm20 0x88000 -> 0x80200
  for (let offset = 0; offset + 3 < bytes.length; offset += 4) {
    const word = (
      (bytes[offset])
      | (bytes[offset + 1] << 8)
      | (bytes[offset + 2] << 16)
      | (bytes[offset + 3] << 24)
    ) >>> 0;

    if ((word & 0x7f) !== 0x37) continue;

    const imm20 = (word >>> 12) & 0xfffff;
    if (imm20 !== 0x88000) continue;

    const rd = (word >>> 7) & 0x1f;
    const newWord = ((((0x80200 << 12) >>> 0) | (rd << 7) | 0x37) >>> 0);
    bytes[offset] = newWord & 0xff;
    bytes[offset + 1] = (newWord >>> 8) & 0xff;
    bytes[offset + 2] = (newWord >>> 16) & 0xff;
    bytes[offset + 3] = (newWord >>> 24) & 0xff;
  }
}

function readPcByNameCompiler(e, ctx, name) {
  const enc = new TextEncoder();
  const nameBytes = enc.encode(name);
  const namePtr = alloc(e, nameBytes.length + 1);
  const valPtr = alloc(e, 4);
  try {
    const mem = new Uint8Array(e.memory.buffer);
    mem.set(nameBytes, namePtr);
    mem[namePtr + nameBytes.length] = 0;
    const has = n(e.sim_signal(ctx, 2, namePtr, 0, 0, valPtr)); // SIM_SIGNAL_PEEK
    if (!has) return 0;
    return new Uint32Array(e.memory.buffer, valPtr, 1)[0] >>> 0;
  } finally {
    dealloc(e, namePtr, nameBytes.length + 1);
    dealloc(e, valPtr, 4);
  }
}

function readPcByNameArcilator(e, ctx, name) {
  const enc = new TextEncoder();
  const nameBytes = enc.encode(name);
  const namePtr = alloc(e, nameBytes.length + 1);
  try {
    const mem = new Uint8Array(e.memory.buffer);
    mem.set(nameBytes, namePtr);
    mem[namePtr + nameBytes.length] = 0;
    return (n(e.sim_peek(ctx, namePtr)) >>> 0);
  } finally {
    dealloc(e, namePtr, nameBytes.length + 1);
  }
}

async function runCompilerBackend(e, kernelData, fsData, cycles, irJson) {
  const enc = new TextEncoder();
  const jsonBytes = enc.encode(irJson || '');
  const jsonPtr = alloc(e, jsonBytes.length || 1);
  if (jsonBytes.length > 0) writeBytes(e, jsonBytes, jsonPtr);

  const errPtr = alloc(e, 4);
  new Uint32Array(e.memory.buffer, errPtr, 1)[0] = 0;

  const tInit = performance.now();
  const ctx = n(e.sim_create(jsonPtr, jsonBytes.length, 1, errPtr));
  if (!ctx) {
    const errWord = new Uint32Array(e.memory.buffer, errPtr, 1)[0];
    let msg = 'sim_create failed';
    if (errWord) {
      msg = readCString(new Uint8Array(e.memory.buffer), errWord) || msg;
      if (e.sim_free_error) e.sim_free_error(errWord);
    }
    throw new Error(msg);
  }
  dealloc(e, jsonPtr, jsonBytes.length || 1);
  dealloc(e, errPtr, 4);

  const patchedKernel = new Uint8Array(kernelData);
  patchPhystopForFastBoot(patchedKernel);

  const kernelPtr = alloc(e, patchedKernel.length);
  writeBytes(e, patchedKernel, kernelPtr);
  e.runner_mem(ctx, RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_ROM, RISCV_RESET_PC, kernelPtr, patchedKernel.length, 0);
  dealloc(e, kernelPtr, patchedKernel.length);

  const fsPtr = alloc(e, fsData.length);
  writeBytes(e, fsData, fsPtr);
  e.runner_mem(ctx, RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_DISK, 0, fsPtr, fsData.length, 0);
  dealloc(e, fsPtr, fsData.length);

  if (e.runner_control) {
    e.runner_control(ctx, RUNNER_CONTROL_SET_RESET_VECTOR, RISCV_RESET_PC, 0);
  }

  const outPtr = alloc(e, 8);
  e.sim_exec(ctx, SIM_EXEC_RESET, 0, 0, outPtr, 0);

  const resultSize = 20;
  const resultPtr = alloc(e, resultSize);
  e.runner_run(ctx, 100, 0, 0, 0, resultPtr);
  const initMs = performance.now() - tInit;

  e.sim_exec(ctx, SIM_EXEC_SIGNAL_COUNT, 0, 0, outPtr, 0);
  const signalCount = new Uint32Array(e.memory.buffer, outPtr, 1)[0] >>> 0;

  const tRun = performance.now();
  e.runner_run(ctx, cycles, 0, 0, 0, resultPtr);
  const runMs = performance.now() - tRun;

  const runResult = new Int32Array(e.memory.buffer, resultPtr, 5);
  const cyclesRun = runResult[2] >>> 0;
  const finalPc = readPcByNameCompiler(e, ctx, 'debug_pc');
  const runnerKind = e.runner_probe ? (n(e.runner_probe(ctx, RUNNER_PROBE_KIND, 0)) >>> 0) : 0;

  dealloc(e, outPtr, 8);
  dealloc(e, resultPtr, resultSize);
  e.sim_destroy(ctx);

  return {
    ok: true,
    cycles: cyclesRun || cycles,
    run_ms: runMs,
    init_ms: initMs,
    final_pc: finalPc,
    signal_count: signalCount,
    runner_kind: runnerKind
  };
}

async function runArcilatorBackend(e, kernelData, fsData, cycles) {
  const tInit = performance.now();
  const ctx = n(e.sim_create(DEFAULT_MEM_SIZE));
  if (!ctx) throw new Error('sim_create failed');

  const patchedKernel = new Uint8Array(kernelData);
  patchPhystopForFastBoot(patchedKernel);

  const kernelPtr = alloc(e, patchedKernel.length);
  writeBytes(e, patchedKernel, kernelPtr);
  e.sim_load_mem(ctx, MEM_TYPE_INST, kernelPtr, patchedKernel.length, RISCV_RESET_PC);
  e.sim_load_mem(ctx, MEM_TYPE_DATA, kernelPtr, patchedKernel.length, RISCV_RESET_PC);
  dealloc(e, kernelPtr, patchedKernel.length);

  const fsPtr = alloc(e, fsData.length);
  writeBytes(e, fsData, fsPtr);
  e.sim_disk_load(ctx, fsPtr, fsData.length, 0);
  dealloc(e, fsPtr, fsData.length);

  if (e.sim_write_pc) e.sim_write_pc(ctx, RISCV_RESET_PC);
  if (e.sim_reset) e.sim_reset(ctx);
  if (e.sim_run_cycles) e.sim_run_cycles(ctx, 100);

  const initMs = performance.now() - tInit;

  const tRun = performance.now();
  e.sim_run_cycles(ctx, cycles);
  const runMs = performance.now() - tRun;

  const finalPc = readPcByNameArcilator(e, ctx, 'debug_pc');
  e.sim_destroy(ctx);

  return {
    ok: true,
    cycles,
    run_ms: runMs,
    init_ms: initMs,
    final_pc: finalPc,
    signal_count: 0,
    runner_kind: 5
  };
}

const [wasmPath, kernelPath, fsPath, cyclesStr, irJsonPath] = process.argv.slice(2);
if (!wasmPath || !kernelPath || !fsPath || !cyclesStr) {
  process.stderr.write(
    'Usage: bun run riscv_wasm_bench.ts <wasm> <kernel> <fs> <cycles> [ir_json]\n'
  );
  process.exit(1);
}

const cycles = parseInt(cyclesStr, 10);
if (!Number.isFinite(cycles) || cycles <= 0) {
  process.stderr.write('ERROR: cycles must be a positive integer\n');
  process.exit(1);
}

const wasmBytes = readFileSync(wasmPath);
const kernelData = new Uint8Array(readFileSync(kernelPath));
const fsData = new Uint8Array(readFileSync(fsPath));
const irJson = irJsonPath ? readFileSync(irJsonPath, 'utf-8') : '';

const tLoad = performance.now();
const instance = await instantiateWasm(wasmBytes);
const loadMs = performance.now() - tLoad;
const e = instance.exports;

const result = (irJsonPath && typeof e.sim_get_caps === 'function')
  ? await runCompilerBackend(e, kernelData, fsData, cycles, irJson)
  : await runArcilatorBackend(e, kernelData, fsData, cycles);

result.wasm_path = wasmPath;
result.wasm_size = wasmBytes.length;
result.load_ms = loadMs;
result.cycles_per_sec = result.cycles / (result.run_ms / 1000);

process.stdout.write(JSON.stringify(result) + '\n');
