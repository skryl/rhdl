# RISC-V Web Verilator Backend PRD

## Status
Completed - 2026-03-01

## Context

The web benchmark workflow already supports RISC-V compiler and arcilator WASM backends. We need parity with Apple II by adding a dedicated RISC-V Verilator WASM backend and including it in `bench:web:riscv` output/comparison.

## Goals

- Add a RISC-V Verilator-to-WASM build task for web usage.
- Integrate the backend into `bench:web:riscv`.
- Ensure the web benchmark harness can instantiate Emscripten/WASI-style WASM imports.
- Keep `web:build` generating both Apple II and RISC-V Verilator web artifacts.

## Non-Goals

- Changing native (non-web) RISC-V runner behavior.
- Reworking benchmark summary formatting.
- Adding new CLI commands beyond existing rake task surfaces.

## Phased Plan

### Phase 1: Add RISC-V Verilator WASM Build Module
Red:
- Add focused spec coverage for required exports and missing-tool skip behavior.

Green:
- Implement `WebRiscvVerilatorBuild`:
  - Export RISC-V Verilog
  - Generate Verilator C++
  - Build wrapper + compat objects with `em++`
  - Link/install `riscv_verilator.wasm`

Exit Criteria:
- Builder returns `false` when required tools are missing.
- Wrapper source includes expected symbols and Verilator access points.

### Phase 2: Wire Backend Into Benchmark + Web Build
Red:
- Add/adjust specs validating web build orchestration and benchmark backend discovery.

Green:
- Update `prepare_web_riscv_wasm_backends` to include Verilator.
- Update `web_generate_task` Verilator build path to build Apple II + RISC-V artifacts.
- Update `bench:web:riscv` task description text.

Exit Criteria:
- Benchmark task discovers `riscv_verilator.wasm`.
- Web build orchestration calls both Verilator backend builders.

### Phase 3: Harness Compatibility + Runtime Validation
Red:
- Repro instantiation failure for modules requiring imports (WASI/env).

Green:
- Add WASI/env import stubs in `web/bench/riscv_wasm_bench.mjs`.
- Run targeted specs and benchmark command(s) to verify all three backends execute.

Exit Criteria:
- `bench:web:riscv` runs compiler, arcilator, and verilator backends successfully in one run (subject to tool availability).

## Acceptance Criteria

- `bundle exec rake bench:web:riscv[...]` reports Compiler, Arcilator, and Verilator results.
- `web:build` attempts both Apple II and RISC-V Verilator builds.
- RISC-V web benchmark harness successfully instantiates Emscripten/WASI-style WASM modules.
- Touched specs pass.

## Risks and Mitigations

- Verilator runtime path variability:
  - Mitigation: resolve `VERILATOR_ROOT` from env or `verilator -V`, with fallback path.
- Emscripten import requirements differ by backend:
  - Mitigation: dynamic import inspection and minimal WASI/env stubs.
- Large generated module memory footprint:
  - Mitigation: export memory with growth enabled and conservative initial memory size.

## Implementation Checklist

- [x] Phase 1: Add `utilities/web_riscv_verilator_build.rb` with export/build/link/install pipeline.
- [x] Phase 1: Add `web_riscv_verilator_build_spec.rb`.
- [x] Phase 2: Update `benchmark_task` RISC-V web backend preparation to include Verilator.
- [x] Phase 2: Update `web_generate_task` to build both Apple II and RISC-V Verilator artifacts.
- [x] Phase 2: Update rake/docs text mentioning RISC-V web Verilator backend.
- [x] Phase 3: Update `web/bench/riscv_wasm_bench.mjs` import handling for WASI/env modules.
- [x] Phase 3: Run targeted specs.
- [x] Phase 3: Run `bench:web:riscv` and capture results.
