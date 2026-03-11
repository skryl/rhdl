# RISC-V Metal Fast-Default ABI Slimming PRD

## Status
Completed (2026-03-04)

## Context
The RISC-V ArcToGPU Metal path currently exposes a large runtime IO surface that includes debug-oriented outputs and is controlled by multiple environment-based tuning toggles. Profiling shows the runtime is compute-bound in the Metal kernel path, and the requested direction is:

1. Fast path by default.
2. No separate execution profile.
3. Remove debug outputs and minimize runtime outputs.
4. Keep API compatibility for runner call sites.

## Goals
1. Make the default RISC-V Metal runtime ABI minimal, with debug outputs removed.
2. Keep full execution parity semantics (PTW/funct3/MMIO behavior retained).
3. Preserve `MetalRunner` public API (`read_pc`, `read_reg`, `current_inst`, `state`) without relying on debug outputs.
4. Remove RISC-V ArcToGPU profile/env toggles tied to alternate/non-default paths.
5. Capture benchmark results after each implementation phase (`5k`, `50k`, `500k`).

## Non-Goals
1. Apple2 or 8-bit ArcToGPU runtime ABI changes.
2. Upstream CIRCT integration.
3. New parallel kernel architecture changes beyond this scope.

## Phased Plan

### Phase 1: Runtime ABI Output Slimming
Red:
1. Add failing lowering tests that require RISC-V runtime output layout to exclude debug outputs.
2. Add failing metadata checks for explicit runtime input/output layout fields.

Green:
1. Add explicit runtime IO layout metadata fields for RISC-V.
2. Emit RISC-V Metal IO struct from runtime output layout (minimal outputs).
3. Keep top-module ABI validation for correctness-critical outputs.

Exit Criteria:
1. Generated runtime output layout excludes debug outputs.
2. Metal wrapper builds against runtime layout metadata.
3. Benchmarks captured for this phase.

### Phase 2: API Parity Without Debug Outputs
Red:
1. Add failing runner tests proving `read_pc`/`read_reg`/`current_inst` work without debug outputs.

Green:
1. Add metadata introspection fields (pc slot + regfile base/length).
2. Add C-wrapper read helpers (`sim_read_pc`, `sim_read_reg`, `sim_read_inst`).
3. Update `MetalRunner` to use helper symbols instead of debug poke/peek path.

Exit Criteria:
1. Runner API remains unchanged and tests pass.
2. Debug output dependency is removed from Metal read methods.
3. Benchmarks captured for this phase.

### Phase 3: Toggle Removal and Fast-Default Consolidation
Red:
1. Add failing tests that assert removed env toggles are no longer consumed.
2. Add failing tests for fixed fast-mode metadata markers.

Green:
1. Remove RISC-V profile env toggle plumbing for split/schedule/dirty/flatten tuning in this path.
2. Fix RISC-V profile to a single fast-default configuration.
3. Remove corresponding tracked env vars from Metal runner build signature.

Exit Criteria:
1. Removed env toggles have no effect.
2. Profile metadata reports fixed fast-default settings.
3. Benchmarks captured for this phase.

### Phase 4: Parity/Regression Validation and PRD Closeout
Red:
1. Add/refresh parity checks on representative RISC-V microprograms.

Green:
1. Run targeted RSpec suites for lowering + runner behavior.
2. Run benchmark sweep and compare phase-to-phase.
3. Update PRD status/checklist with concrete evidence.

Exit Criteria:
1. Targeted tests green.
2. Parity checks green for selected microprograms.
3. Benchmark table populated for every phase.

## Acceptance Criteria
1. RISC-V Metal runtime outputs are minimized and exclude debug outputs.
2. `MetalRunner` API compatibility is preserved.
3. Full parity semantics are retained in default fast path.
4. RISC-V env-based alternate profile toggles are removed.
5. Benchmarks are reported after each phase (`5k`, `50k`, `500k`).

## Risks and Mitigations
1. Risk: Removing debug outputs could break runner read methods.
   Mitigation: Add explicit introspection metadata + wrapper helpers and tests before removal.
2. Risk: Toggle removal could regress performance unexpectedly.
   Mitigation: Benchmark after each phase and compare.
3. Risk: Metadata/schema drift could break wrapper generation.
   Mitigation: Add explicit metadata field assertions in lowering specs.

## Benchmark Evidence Log
### Phase 1 (Runtime ABI Output Slimming)
- Command: `bundle exec ruby /tmp/riscv_phase_bench.rb` (cleaned JSON at `/tmp/riscv_phase1_bench_clean.json`)
- Throughput (cycles/sec, median of 3):
  - IR compile: `5k=158,649`, `50k=161,192`, `500k=162,256`
  - Metal: `5k=51,249`, `50k=51,870`, `500k=51,771`
  - Metal/IR ratio: `~0.323x`, `~0.322x`, `~0.319x`
- Dispatch/wait behavior: `dispatch_delta=1`, `wait_delta=1` at `500k`.
- Note: parity snapshot via `read_pc/read_reg` is expectedly broken at this point because debug-output-backed read API has not been migrated yet (Phase 2).

### Phase 2 (API Parity Without Debug Outputs)
- Command: `bundle exec ruby /tmp/riscv_phase_bench.rb` (cleaned JSON at `/tmp/riscv_phase2_bench_clean.json`)
- Throughput (cycles/sec, median of 3):
  - IR compile: `5k=162,744`, `50k=162,137`, `500k=162,989`
  - Metal: `5k=51,365`, `50k=51,926`, `500k=51,881`
  - Metal/IR ratio: `~0.316x`, `~0.320x`, `~0.318x`
- Dispatch/wait behavior: `dispatch_delta=1`, `wait_delta=1` at `500k`.
- Parity snapshot (`pc/x1/x2/mem`) restored: `5k=true`, `50k=true`, `500k=true`.

### Phase 3 (Toggle Removal and Fast-Default Consolidation)
- Command: `bundle exec ruby /tmp/riscv_phase_bench.rb` (raw output at `/tmp/riscv_phase3_bench_clean.json`, cleaned JSON at `/tmp/riscv_phase3_bench.json`)
- Throughput (cycles/sec, median of 3):
  - IR compile: `5k=162,248`, `50k=161,986`, `500k=160,998`
  - Metal: `5k=45,958`, `50k=46,554`, `500k=46,460`
  - Metal/IR ratio: `~0.283x`, `~0.287x`, `~0.289x`
- Dispatch/wait behavior: `dispatch_delta=1`, `wait_delta=1` at `5k`, `50k`, `500k`.
- Parity snapshot (`pc/x1/x2/mem`): `5k=true`, `50k=true`, `500k=true`.
- Notes:
  - Fast-default profile is now fixed in code (`flatten=96/6`, split helpers enabled, scheduled/dirty disabled).
  - Removed env toggles are no longer consumed by the profile path.

### Phase 4 (Parity/Regression Validation and PRD Closeout)
- Targeted validation command:
  - `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb:90`
  - Result: `63 examples, 0 failures`.
- Benchmark command: `bundle exec ruby /tmp/riscv_phase_bench.rb` (raw output at `/tmp/riscv_phase4_bench_raw.txt`, cleaned JSON at `/tmp/riscv_phase4_bench.json`)
- Throughput (cycles/sec, median of 3):
  - IR compile: `5k=162,253`, `50k=160,619`, `500k=161,280`
  - Metal: `5k=46,401`, `50k=46,617`, `500k=46,396`
  - Metal/IR ratio: `~0.286x`, `~0.290x`, `~0.288x`
- Dispatch/wait behavior: `dispatch_delta=1`, `wait_delta=1` at `5k`, `50k`, `500k`.
- Parity snapshot (`pc/x1/x2/mem`): `5k=true`, `50k=true`, `500k=true`.

## Implementation Checklist
- [x] Phase 1 red tests added.
- [x] Phase 1 green implementation completed.
- [x] Phase 1 benchmarks recorded.
- [x] Phase 2 red tests added.
- [x] Phase 2 green implementation completed.
- [x] Phase 2 benchmarks recorded.
- [x] Phase 3 red tests added.
- [x] Phase 3 green implementation completed.
- [x] Phase 3 benchmarks recorded.
- [x] Phase 4 parity/regression checks completed.
- [x] Phase 4 benchmarks recorded.
- [x] PRD status updated to Completed.
