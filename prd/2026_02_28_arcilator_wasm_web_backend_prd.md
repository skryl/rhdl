# Arcilator WASM Backend for Apple II Web Simulator

**Status:** In Progress
**Date:** 2026-02-28

## Context

RHDL's web simulator currently uses IR-based WASM backends (interpreter, JIT, AOT compiler) to simulate hardware in the browser. The Apple II also has a native arcilator backend (`ArcilatorRunner`) that compiles through the CIRCT toolchain (RHDL → FIRRTL → firtool → arcilator → LLVM IR → native .so).

This PRD adds an arcilator-to-WASM compilation path so the Apple II can be simulated in the browser using an arcilator-compiled WASM module. The arcilator backend bypasses the IR layer entirely — the circuit evaluation function is compiled directly from MLIR to WASM, which should yield higher simulation throughput than the IR compiler backend.

## Goals

1. Build pipeline: RHDL → FIRRTL → firtool → arcilator → LLVM IR → clang/wasm-ld → `.wasm`.
2. C wrapper implementing the `WasmIrSimulator` API + Apple II runner extensions.
3. Integration into `rake web:build` with graceful skip when CIRCT tools are unavailable.
4. New `arcilator` backend in `backend_defs.mjs` selectable in the web UI.

## Non-Goals

- Supporting arcilator WASM for other systems (MOS6502, GameBoy, RISC-V) in this phase.
- VCD tracing support in the arcilator WASM module (stub only).
- Replacing the IR compiler backend — this is an additional option.

## Phased Plan

### Phase 1: Build Infrastructure

**Red:** `rake web:build` does not produce `apple2_arcilator.wasm`.
**Green:** Build task generates C wrapper from arcilator state JSON, compiles to WASM, copies to `web/assets/pkg/`.

Steps:
1. Create `lib/rhdl/cli/tasks/web_arcilator_build.rb` with build logic.
2. Generate FIRRTL, run firtool + arcilator, parse state JSON.
3. Generate C wrapper with correct state offsets and WasmIrSimulator API.
4. Compile with `clang --target=wasm32` + `wasm-ld` to standalone WASM.
5. Integrate into `web_generate_task.rb` `build_wasm_backends` flow.

Exit criteria: Build completes and produces a valid `.wasm` file.

### Phase 2: Web Integration

**Red:** Web simulator has no arcilator backend option.
**Green:** `backend_defs.mjs` includes arcilator; Apple2 config allows selecting it.

Steps:
1. Add `arcilator` entry to `backend_defs.mjs`.
2. Update Apple2 runner config with arcilator backend availability note.
3. Verify `WasmIrSimulator` can load and use the arcilator WASM module.

Exit criteria: Web simulator can load the arcilator backend and run Apple II simulation.

### Phase 3: Tests

**Red:** No test coverage for arcilator WASM build.
**Green:** Specs verify build task behavior with graceful tool-missing handling.

Exit criteria: Tests pass for build logic; tests skip gracefully when CIRCT tools absent.

## Acceptance Criteria

1. `rake web:build` produces `apple2_arcilator.wasm` when firtool/arcilator/clang are available.
2. Build gracefully skips with a warning when CIRCT tools are missing.
3. `backend_defs.mjs` includes the arcilator backend.
4. The WASM module implements the core `WasmIrSimulator` API + Apple II runner extensions.
5. Tests exist for the build task.

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Arcilator LLVM IR not compatible with wasm32 target | Strip/modify target triple before compilation; arcilator IR is largely target-independent |
| CIRCT tools not available in CI/build environments | Graceful skip with warning; WASM artifact is optional |
| C wrapper memory model differences (32-bit WASM pointers) | Use uint32_t for addresses; arcilator state buffer fits in WASM linear memory |

## Implementation Checklist

- [ ] Create `lib/rhdl/cli/tasks/web_arcilator_build.rb`
- [ ] Create C wrapper template generator
- [ ] Integrate into `web_generate_task.rb`
- [ ] Add `arcilator` backend to `backend_defs.mjs`
- [ ] Add build spec
- [ ] Update WASM build stamp requirements
