# Web RISC-V Compiler vs Arcilator Benchmark

**Status:** Completed  
**Date:** 2026-03-01

## Context

RHDL currently provides `bench:web:apple2` to compare web WASM backends (Rust AOT compiler vs arcilator). There is no equivalent web benchmark entry for RISC-V, so backend parity/performance in browser-style runtime conditions is not directly measurable from rake.

## Goals

1. Add a new `bench:web:riscv` rake task.
2. Benchmark RISC-V web WASM backends side-by-side: compiler vs arcilator.
3. Auto-build or locate required artifacts for both backends when possible.
4. Reuse existing benchmark summary formatting and performance ratio output.
5. Add/update specs to cover task wiring and task dispatch.

## Non-Goals

1. Full web UI integration for a RISC-V arcilator backend selection.
2. Replacing native RISC-V benchmark flows (`bench:riscv`).
3. Reworking existing Apple II web benchmark behavior.

## Phased Plan

### Phase 1: Task Wiring + Red Tests

**Red:** Specs do not recognize `bench:web:riscv` and no `BenchmarkTask` dispatch exists for `:web_riscv`.  
**Green:** Rake and task dispatch specs pass for the new type/task.

Exit criteria:
1. Rake interface spec checks `bench:web:riscv` task existence/invocation.
2. BenchmarkTask spec checks dispatch to `benchmark_web_riscv`.

### Phase 2: RISC-V Web Benchmark Implementation

**Red:** Running `bench:web:riscv` fails because no benchmark implementation/harness exists.  
**Green:** `bench:web:riscv` runs and reports compiler + arcilator results when artifacts/tools are available.

Exit criteria:
1. `BenchmarkTask#run` handles `:web_riscv`.
2. `benchmark_web_riscv` exists and reuses summary reporting.
3. New Node harness exists for RISC-V WASM benchmark execution.

### Phase 3: Artifact Build Support + Validation

**Red:** RISC-V arcilator WASM artifact is unavailable for web benchmark flow.  
**Green:** Build helper can generate a RISC-V arcilator WASM benchmark artifact (with graceful skip on missing tools), and benchmark uses it.

Exit criteria:
1. Build helper module for RISC-V arcilator WASM benchmark artifact exists.
2. Compiler artifact path/build is handled for RISC-V.
3. Targeted specs pass and `bench:web:riscv` command is validated locally.

## Acceptance Criteria

1. `bundle exec rake bench:web:riscv` is a valid rake task.
2. Benchmark output includes compiler and arcilator backend runs (or explicit skip messages).
3. Summary table and ratio output are produced in the same style as existing web benchmark output.
4. Updated specs cover new task wiring and dispatch.

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| CIRCT/LLVM toolchain differences break arcilator wasm build | Graceful skip with explicit missing tool/error output |
| RISC-V kernel boot characteristics vary by memory model | Use existing xv6 load/reset conventions from current runners and benchmark fixed cycle counts |
| Build complexity increases benchmark runtime | Build only when artifacts are missing; reuse existing artifacts when present |

## Implementation Checklist

- [x] Add rake task `bench:web:riscv`
- [x] Add `:web_riscv` dispatch in `BenchmarkTask#run`
- [x] Add `benchmark_web_riscv` and backend prep/build helpers
- [x] Add RISC-V web benchmark Node harness
- [x] Add RISC-V arcilator WASM build helper for benchmark flow
- [x] Update/extend specs for rake interface + benchmark dispatch
- [x] Run targeted specs and command validation
