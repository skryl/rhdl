# RISC-V Netlist-to-GPU Experiment PRD

## Status
Completed (2026-03-04)

## Context
We need a separate experiment path named `riscv_netlist` that netlistizes RISC-V combinational logic through CIRCT synth lowering and runs the result on the Metal GPU backend.

Current RISC-V Metal execution uses ArcToGPU lowering directly from Arc MLIR. This experiment adds a second path:

1. Arc MLIR emission.
2. Comb-to-synth (AIG-style) netlistization pass chain.
3. Synth-to-comb re-materialization.
4. ArcToGPU Metal codegen and execution.

## Goals
1. Add a dedicated ArcToGPU profile `:riscv_netlist` with synth netlistization in `prepare_source`.
2. Add a dedicated runner `RiscvNetlistRunner`.
3. Expose `:riscv_netlist` as a runnable RISC-V headless/CLI mode.
4. Validate parity against IR on a representative loop program.
5. Capture baseline throughput for `IR compile`, `Metal`, and `riscv_netlist`.

## Non-Goals
1. Replace existing `:metal` RISC-V path.
2. Re-architect Metal kernel threading/dispatch behavior.
3. Full Linux/xv6 validation on this first experiment pass.

## Phased Plan

### Phase 1: Lowering Profile
Red:
1. Add failing lowering tests for `profile: :riscv_netlist`.

Green:
1. Add `profiles/riscv_netlist.rb`.
2. Wire `:riscv_netlist` into `ArcToGpuLowering.profile_module_for`.
3. Add reusable `circt-opt` pipeline helper in lowering module.

Exit Criteria:
1. Lowering spec passes for `:riscv_netlist`.
2. Metadata includes `profile=riscv_netlist` and runtime introspection fields.

### Phase 2: Runner + Mode Wiring
Red:
1. Add/adjust runner/headless specs for new mode/runner.

Green:
1. Add `RiscvNetlistRunner` class.
2. Parameterize `MetalRunner` for profile/variant reuse.
3. Wire `HeadlessRunner` and CLI mode handling for `:riscv_netlist`.

Exit Criteria:
1. Runner and task specs pass.
2. `examples/riscv/bin/riscv --mode riscv_netlist` is accepted.

### Phase 3: Parity + Baseline Performance
Red:
1. Define parity gate: `pc/x1/x2/mem` snapshot equality versus IR at 5k/50k/500k cycles.

Green:
1. Run parity benchmark for `riscv_netlist`.
2. Run throughput baseline for IR, Metal, and `riscv_netlist`.
3. Record results in this PRD.

Exit Criteria:
1. Parity gate passes at all benchmark points.
2. Throughput table recorded.

## Acceptance Criteria
1. New mode `:riscv_netlist` is implemented and runnable.
2. Netlistization pass chain is active in the experiment profile.
3. Parity gate passes on benchmark program.
4. Baseline benchmark numbers are documented.

## Risks and Mitigations
1. Risk: CIRCT synth passes unavailable/unsupported on host toolchain.
   Mitigation: pipeline helper fails soft to prior source; tests detect profile behavior and runner still builds.
2. Risk: Mode wiring regressions in RISC-V runner selection.
   Mitigation: extend runner and task specs.
3. Risk: Large compile latency in tests.
   Mitigation: keep new tests interface-focused and skip when backend unavailable.

## Benchmark Evidence Log
### Phase 1: Lowering Profile
- Validation command:
  - `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb`
- Evidence:
  - `profile: :riscv_netlist` artifacts emitted.
  - Metadata includes `profile=riscv_netlist`, `metal.schedule_mode=netlist_aig_legacy`, and runtime introspection fields.

### Phase 2: Runner + Mode Wiring
- Validation commands:
  - `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb`
  - `bundle exec rspec spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb`
- Evidence:
  - `RiscvNetlistRunner` class available with expected runner interface.
  - `HeadlessRunner` accepts `mode: :riscv_netlist` without fallback.
  - CLI accepts `--mode riscv_netlist`.
  - Objective-C Metal wrapper class is now build-variant namespaced to allow loading both `metal` and `riscv_netlist` shared libraries in one process.

### Phase 3: Parity + Baseline Performance
- Benchmark command:
  - `bundle exec ruby /tmp/riscv_netlist_experiment_bench.rb`
  - Raw output: `/tmp/riscv_netlist_experiment_bench_raw.txt`
  - Clean JSON: `/tmp/riscv_netlist_experiment_bench.json`
- Throughput (cycles/sec, median of 3):
  - IR compile: `5k=164,403`, `50k=162,633`, `500k=161,794`
  - Metal: `5k=46,628`, `50k=46,657`, `500k=46,300`
  - riscv_netlist: `5k=46,444`, `50k=46,199`, `500k=46,527`
  - Metal/IR ratio: `~0.284x`, `~0.287x`, `~0.286x`
  - riscv_netlist/IR ratio: `~0.282x`, `~0.284x`, `~0.288x`
- Parity vs IR (`pc/x1/x2/mem`) at `5k`, `50k`, `500k`:
  - Metal: `true`, `true`, `true`
  - riscv_netlist: `true`, `true`, `true`
- Dispatch/wait deltas per benchmark run:
  - Metal: `dispatch=1`, `wait=1`
  - riscv_netlist: `dispatch=1`, `wait=1`

## Implementation Checklist
- [x] Phase 1 red tests added.
- [x] Phase 1 green implementation completed.
- [x] Phase 2 red tests added.
- [x] Phase 2 green implementation completed.
- [x] Phase 3 parity checks completed.
- [x] Phase 3 benchmarks recorded.
- [x] PRD status updated to Completed.
