#!/usr/bin/env node
// Headless Apple II WASM benchmark harness.
//
// Loads a WASM module (arcilator or ir_compiler), initialises the Apple II
// runner, loads ROM + RAM, resets, then runs a batch of cycles and reports
// wall-clock timing as JSON on stdout.
//
// Usage:
//   node web/bench/apple2_wasm_bench.mjs <wasm_path> <rom_path> <ram_path> <cycles> [ir_json_path]
//
// The optional ir_json_path is required for the ir_compiler backend
// (which needs the IR JSON passed to sim_create).  Arcilator ignores it.

import { readFileSync } from 'node:fs';
import { performance } from 'node:perf_hooks';

// --------------- constants mirroring the C ABI ---------------

const RUNNER_MEM_OP_LOAD = 0;

const RUNNER_MEM_SPACE_MAIN = 0;
const RUNNER_MEM_SPACE_ROM  = 1;

const RUNNER_PROBE_KIND = 0;

const SIM_EXEC_RESET        = 5;
const SIM_EXEC_SIGNAL_COUNT = 7;

// --------------- helpers ---------------

// Coerce WASM return value to JS Number (handles BigInt from i64 returns)
function n(v) { return typeof v === 'bigint' ? Number(v) : (v ?? 0); }

function alloc(e, size) {
  return n(e.sim_wasm_alloc(Math.max(1, size)));
}

function dealloc(e, ptr, size) {
  if (ptr) e.sim_wasm_dealloc(ptr, Math.max(1, size));
}

function writeBytes(e, data, ptr) {
  new Uint8Array(e.memory.buffer).set(data, ptr);
}

// --------------- main ---------------

const [wasmPath, romPath, ramPath, cyclesStr, irJsonPath] = process.argv.slice(2);
if (!wasmPath || !romPath || !ramPath || !cyclesStr) {
  process.stderr.write(
    'Usage: node apple2_wasm_bench.mjs <wasm> <rom> <ram> <cycles> [ir_json]\n'
  );
  process.exit(1);
}

const cycles = parseInt(cyclesStr, 10);

const wasmBytes  = readFileSync(wasmPath);
const romData    = readFileSync(romPath);
const ramData    = readFileSync(ramPath);
const irJson     = irJsonPath ? readFileSync(irJsonPath, 'utf-8') : '';

const t0 = performance.now();
const { instance } = await WebAssembly.instantiate(wasmBytes, {});
const e = instance.exports;
const loadMs = performance.now() - t0;

// Prepare IR JSON in WASM memory (compiler needs it; arcilator ignores it)
const enc = new TextEncoder();
const jsonBytes = enc.encode(irJson);
const jsonPtr   = alloc(e, jsonBytes.length || 1);
if (jsonBytes.length > 0) writeBytes(e, jsonBytes, jsonPtr);

const errPtr = alloc(e, 4);
new Uint32Array(e.memory.buffer, errPtr, 1)[0] = 0;

// Create sim context.  sub_cycles = 14 for Apple II.
const t1 = performance.now();
const ctx = n(e.sim_create(jsonPtr, jsonBytes.length, 14, errPtr));
if (!ctx) {
  const errWord = new Uint32Array(e.memory.buffer, errPtr, 1)[0];
  let msg = 'sim_create failed';
  if (errWord) {
    const u8 = new Uint8Array(e.memory.buffer);
    let end = errWord;
    while (end < u8.length && u8[end] !== 0) end++;
    msg = new TextDecoder().decode(u8.subarray(errWord, end));
    if (e.sim_free_error) e.sim_free_error(errWord);
  }
  process.stderr.write(`ERROR: ${msg}\n`);
  process.exit(1);
}
dealloc(e, jsonPtr, jsonBytes.length || 1);
dealloc(e, errPtr, 4);

const initMs = performance.now() - t1;

// Verify runner kind
const kind = e.runner_probe ? n(e.runner_probe(ctx, RUNNER_PROBE_KIND, 0)) : 0;

// Load ROM (with patched reset vector → $B82A)
const rom = new Uint8Array(romData);
rom[0x2FFC] = 0x2A;  // low byte
rom[0x2FFD] = 0xB8;  // high byte
const romPtr = alloc(e, rom.length);
writeBytes(e, rom, romPtr);
e.runner_mem(ctx, RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_ROM, 0, romPtr, rom.length, 0);
dealloc(e, romPtr, rom.length);

// Load RAM (first 48 KB)
const ramLen = Math.min(ramData.length, 48 * 1024);
const ramPtr = alloc(e, ramLen);
writeBytes(e, ramData.subarray(0, ramLen), ramPtr);
e.runner_mem(ctx, RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_MAIN, 0, ramPtr, ramLen, 0);
dealloc(e, ramPtr, ramLen);

// Reset
const outPtr = alloc(e, 8);
e.sim_exec(ctx, SIM_EXEC_RESET, 0, 0, outPtr, 0);

// Warmup
const resultSize = 20;
const resultPtr  = alloc(e, resultSize);
e.runner_run(ctx, 3, 0, 0, 0, resultPtr);

// Signal count
e.sim_exec(ctx, SIM_EXEC_SIGNAL_COUNT, 0, 0, outPtr, 0);
const signalCount = new Uint32Array(e.memory.buffer, outPtr, 1)[0];

// Benchmark
const tRun = performance.now();
e.runner_run(ctx, cycles, 0, 0, 0, resultPtr);
const runMs = performance.now() - tRun;

const runResult = new Int32Array(e.memory.buffer, resultPtr, 5);
const cyclesRun     = runResult[2];
const speakerToggle = runResult[3];

// Read PC via sim_signal PEEK on pc_debug
let pc = 0;
{
  const nameStr = 'pc_debug';
  const nameBytes = enc.encode(nameStr);
  const namePtr   = alloc(e, nameBytes.length + 1);
  const u8 = new Uint8Array(e.memory.buffer);
  u8.set(nameBytes, namePtr);
  u8[namePtr + nameBytes.length] = 0;
  const valPtr = alloc(e, 4);
  const hasPC  = n(e.sim_signal(ctx, 2, namePtr, 0, 0, valPtr)); // PEEK
  if (hasPC) pc = new Uint32Array(e.memory.buffer, valPtr, 1)[0];
  dealloc(e, namePtr, nameBytes.length + 1);
  dealloc(e, valPtr, 4);
}

dealloc(e, outPtr, 8);
dealloc(e, resultPtr, resultSize);

e.sim_destroy(ctx);

// Output JSON result
const result = {
  ok: true,
  wasm_path: wasmPath,
  wasm_size: wasmBytes.length,
  cycles: cyclesRun || cycles,
  run_ms: runMs,
  init_ms: initMs,
  load_ms: loadMs,
  cycles_per_sec: (cyclesRun || cycles) / (runMs / 1000),
  final_pc: pc,
  signal_count: signalCount,
  runner_kind: kind,
  speaker_toggles: speakerToggle
};

process.stdout.write(JSON.stringify(result) + '\n');
