# Apple II Metal Runner And Benchmark Integration PRD

**Status:** Completed (2026-03-03)
**Date:** 2026-03-03

## Context

The Apple II benchmark currently compares IR and RTL-native backends (Interpreter/JIT/Compiler, Verilator, Arcilator), but it did not expose a dedicated Metal runner entry. We need a first-class `MetalRunner` and benchmark integration so Apple II can participate in the same Metal-path performance workflow as other GPU-oriented efforts.

Resolution summary (2026-03-03): Apple II now runs through the real Arc -> ArcToGPU -> Metal kernel path with packed 32-bit lowering for `i48` state, fixed multi-operand `comb.concat` lowering, successful Metal pipeline creation, and benchmark parity checkpoints against Arcilator.

## Goals

1. Add a dedicated Apple II `MetalRunner` with explicit Metal toolchain gating.
2. Expose Metal as a selectable Apple II runner mode.
3. Include Metal in `bench:native[apple2,...]` backend comparisons.
4. Keep runner interface parity with existing Apple II runners.
5. Require behavioral parity with existing Apple II execution paths (at minimum Arcilator) on benchmark workloads once Metal initialization succeeds.

## Non-Goals

1. Full Apple II ArcToGPU lowering implementation in this slice.
2. Web Metal backend support in this slice.
3. Reworking Apple II UI/terminal rendering behavior.

## Phased Plan

### Phase 1: MetalRunner Entry Point

**Red:** No dedicated Apple II Metal runner class.
**Green:** `RHDL::Examples::Apple2::MetalRunner` exists with explicit availability checks and Apple II runner-compatible API.

Exit criteria:
1. `MetalRunner.status` reports readiness/missing tools.
2. `MetalRunner` initializes only when required tools are available.
3. `simulator_type` identifies as `:hdl_metal`.

### Phase 2: Runner Mode Wiring

**Red:** Headless/CLI mode routing cannot select Metal.
**Green:** `:metal` is accepted in Apple II runner mode routing and help text.

Exit criteria:
1. `HeadlessRunner` supports `mode: :metal`.
2. Apple II binary help text includes `--mode metal`.
3. Existing mode behavior remains unchanged.

### Phase 3: Benchmark Integration

**Red:** Apple II native benchmark excludes Metal.
**Green:** `BenchmarkTask#benchmark_apple2` includes Metal in backend matrix and reports it in summary.

Exit criteria:
1. Metal backend is conditionally included via availability checks.
2. Benchmark can initialize and run Metal runner path.
3. Existing benchmark backends still run/skip correctly.

### Phase 4: ArcToGPU Runtime Parity

**Red:** Metal path initializes as no-op/fails pipeline creation; benchmark reports are misleading or divergent.
**Green:** Apple II Metal runner executes a real ArcToGPU kernel path with stable initialization and parity against Arcilator on benchmark checkpoints.

Exit criteria:
1. `sim_create` failure is surfaced as an explicit runner error (no silent null-context execution).
2. Apple II Metal kernel initializes on supported hosts.
3. `bench:native[apple2,...]` shows matching final PC for Arcilator vs Metal on fixed-cycle runs (for example 5000 cycles on Karateka memory image).
4. Follow-up parity checks cover at least one longer-run checkpoint beyond smoke initialization.

## Acceptance Criteria

1. `MetalRunner` can be selected in Apple II headless mode.
2. `bench:native[apple2,...]` includes Metal when available.
3. Targeted specs for new runner and integration changes pass.
4. README benchmark section mentions Apple II Metal inclusion.
5. Apple II Metal runner does not silently continue when Metal context creation fails.
6. Apple II Metal path reaches parity checkpoint(s) with Arcilator on benchmarked workloads.

## Risks And Mitigations

1. Risk: Metal toolchain availability differs by host.
   Mitigation: explicit readiness checks and clear missing-tool reporting.
2. Risk: MetalRunner path diverges from existing Apple II runner interface.
   Mitigation: reuse existing runner contracts and shared test coverage.
3. Risk: Benchmark behavior changes for existing backends.
   Mitigation: keep backend dispatch additive; do not alter existing semantics.

## Implementation Checklist

- [x] Phase 1: Add `examples/apple2/utilities/runners/metal_runner.rb`.
- [x] Phase 1: Add Metal runner status/availability checks.
- [x] Phase 2: Add `:metal` support in `HeadlessRunner`.
- [x] Phase 2: Update Apple II mode/help text for Metal.
- [x] Phase 3: Add Metal backend to `benchmark_apple2` matrix.
- [x] Phase 3: Run targeted Apple II runner + benchmark task specs.
- [x] Phase 3: Run a local Apple II benchmark invocation verifying Metal appears in output.
- [x] Phase 4: Fail fast when Metal context initialization returns null (`sim_create` guard).
- [x] Phase 4: Resolve Metal pipeline initialization for ArcToGPU Apple II kernels on host GPU.
- [x] Phase 4: Demonstrate Apple II parity checkpoint(s) between Metal and Arcilator.

## Validation Evidence

1. `bundle exec rake 'bench:native[apple2,500]'`:
   Metal final PC `0xB818`, Arcilator final PC `0xB818`.
2. `bundle exec rake 'bench:native[apple2,5000]'`:
   Metal final PC `0xB7F4`, Arcilator final PC `0xB7F4`.
3. Targeted specs passed:
   - `spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb`
   - `spec/examples/apple2/runners/metal_runner_spec.rb`
   - `spec/examples/apple2/utilities/tasks/run_task_spec.rb`
   - `spec/rhdl/cli/tasks/benchmark_task_spec.rb`

## Performance Follow-Up (2026-03-03)

Post-parity optimization pass completed on the Apple II ArcToGPU Metal path:

1. Enabled optimized Metal shader build (`-O3`) for Apple II Metal runner.
2. Added Apple II ArcToGPU kernel local-state execution (`thread` local state copy-in/copy-out) to avoid repeated global state traffic.
3. Reduced per-iteration global IO writes in Apple II kernel to a single final writeback per dispatched budget.
4. Preserved 4-eval sub-cycle semantics after validating that removing the final settled eval broke parity (incorrect PC progression).
5. Added optional Apple II Arc MLIR cleanup (`circt-opt --canonicalize --cse --symbol-dce`) before Metal emission.

Measured outcomes:

1. `bundle exec rake 'bench:native[apple2,500]'`:
   - Metal run time improved from ~`17.7s` to `0.342s`
   - Final PC parity preserved: Metal `0xB818`, Arcilator `0xB818`
2. `bundle exec rake 'bench:native[apple2,5000]'`:
   - Metal run time improved from ~`175.7s` to `3.433s`
   - Final PC parity preserved: Metal `0xB7F4`, Arcilator `0xB7F4`
3. `bundle exec rake 'bench:native[cpu8bit,500000]'`:
   - ArcilatorGPU run time `2.148s` vs Compiler `7.650s` (~`3.56x` faster)

## Generator Optimization Follow-Up (2026-03-03, Pass 2)

Implemented follow-up ArcToGPU generator work for maintainability and hot-loop behavior:

1. Split ArcToGPU lowering profile behavior by target into separate files:
   - `lib/rhdl/codegen/firrtl/arc_to_gpu_lowering/profiles/cpu8bit.rb`
   - `lib/rhdl/codegen/firrtl/arc_to_gpu_lowering/profiles/apple2.rb`
2. Added liveness-driven comb emission in top eval generation so dead combinational ops are pruned before Metal emission.
3. Added aggressive inlining hints (`static inline __attribute__((always_inline))`) on generated helper/eval functions.
4. Added selective state snapshotting for `comb_pre` (only state refs required by live graph/state update dependencies are snapshotted).
5. Reworked Apple II kernel hot loop to avoid loop-time external IO reads/writes:
   - local cached input fields (`clk_14m`, `ram_do`, etc.)
   - local loop counters/flags (`cycles_ran`, `speaker_toggles`, `text_dirty`, `prev_speaker`)
   - single external writeback at dispatch end
6. Added Apple II loop-step internal struct path (`ram_addr`, `ram_we`, `d`, `speaker`) and deferred full debug-output materialization to dispatch end.

Validation after pass 2:

1. `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb` passed.
2. `bundle exec rspec spec/examples/apple2/runners/metal_runner_spec.rb` passed.
3. `bundle exec rspec spec/examples/8bit/utilities/runners/arcilator_gpu_runner_spec.rb` passed.
4. `bundle exec rspec spec/examples/8bit/hdl/cpu/arcilator_gpu_complex_parity_spec.rb` passed.
5. `bundle exec rake 'bench:native[cpu8bit,500000]'`:
   - Compiler run `6.740s`, ArcilatorGPU run `1.453s` (~`4.64x` faster).
6. `bundle exec rake 'bench:native[apple2,500]'`:
   - Metal run `0.342s`, final PC parity preserved (`0xB818` vs Arcilator `0xB818`).
7. `bundle exec rake 'bench:native[apple2,5000]'`:
   - Metal run `3.378s`, final PC parity preserved (`0xB7F4` vs Arcilator `0xB7F4`).

## Performance Follow-Up (2026-03-03, Pass 3)

Additional lowering/runtime optimizations were implemented and measured:

1. Added a dedicated Apple II fast loop eval function variant that computes only hot-loop outputs
   (`ram_addr`, `ram_we`, `d`, `speaker`) while preserving full-output eval for dispatch-end materialization.
2. Added direct ROM mirroring into the unified 64K RAM view for Metal host runtime and simplified kernel RAM read path
   to reduce loop-time ROM/RAM branch logic.

Measured outcome:

1. `bundle exec rake 'bench:native[apple2,5000]'` after pass 3:
   - Compiler run `0.015s`
   - Metal run `3.483s`
   - Final PC parity preserved (`0xB7F4` vs Arcilator `0xB7F4`)

Result: no material speedup relative to pass 2. Apple II Metal remains significantly slower than IR compiler on this host/workload.

Interpretation:

1. Remaining bottleneck is likely architectural (single-thread sequential state machine execution with dense eval graph),
   not simple loop-time IO/branch overhead.
2. Reaching compiler-beating performance will require a larger redesign (for example, aggressive call-graph flattening /
   state-specialized kernel generation and/or multi-instance batch-parallel execution strategy) beyond local pass tuning.
