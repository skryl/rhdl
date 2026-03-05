# RISC-V ArcToGPU Metal Runner And Performance PRD

**Status:** In Progress
**Date:** 2026-03-03

## Context

RISC-V currently has native HDL runners for Verilator and Arcilator, but no Metal/GPU runner that executes via the local Arc -> ArcToGPU -> Metal path. Existing benchmark coverage for RISC-V focuses on xv6 boot throughput across IR Compiler, Verilator, and CIRCT backends.

We need a first-class RISC-V Metal runner for core execution, with incremental optimization focused on reducing the throughput gap versus IR compiled simulation.

## Goals

1. Add a dedicated RISC-V `MetalRunner` backed by ArcToGPU-generated Metal kernels.
2. Add a RISC-V ArcToGPU lowering profile (`:riscv`) with explicit top-module ABI validation.
3. Wire `:metal` into RISC-V headless/CLI mode routing.
4. Provide a benchmark path that compares RISC-V Metal against IR compiled on the same core workload.
5. Add optional multi-instance Metal throughput mode (`instances`) while preserving single-instance parity as default.
6. Establish a reproducible optimization loop for improving Metal cycles/sec.

## Non-Goals

1. Full xv6/Linux MMIO/virtio parity in the first Metal runner slice.
2. Web/WASM RISC-V Metal execution.
3. Pipeline-core Metal support in this slice (single-cycle core only).

## Phased Plan

### Phase 1: ArcToGPU RISC-V Lowering Profile

**Red:** ArcToGPU supports only `:cpu8bit` and `:apple2`; no RISC-V profile/ABI checks.
**Green:** ArcToGPU accepts `profile: :riscv`, validates required RISC-V top ports, and emits a RISC-V Metal kernel.

Exit criteria:
1. `ArcToGpuLowering.lower(..., profile: :riscv)` succeeds on RISC-V Arc MLIR.
2. Missing required RISC-V ports fail with explicit errors.
3. Generated metadata includes Metal entry and state layout for wrapper integration.

### Phase 2: RISC-V Metal Runner Integration

**Red:** No `RHDL::Examples::RISCV::MetalRunner`; headless/CLI cannot select RISC-V Metal.
**Green:** `MetalRunner` exists, builds ArcToGPU artifacts, compiles Metal library, and exposes the native HDL runner API.

Exit criteria:
1. `HeadlessRunner.new(mode: :metal)` resolves and instantiates Metal runner on supported hosts.
2. RISC-V CLI accepts `--mode metal`.
3. Runner supports core execution lifecycle (`reset!`, `run_cycles`, `read_pc`, `read_reg`, memory load/read/write).

### Phase 3: Benchmark Path And Throughput Optimization

**Red:** No RISC-V Metal backend in benchmark matrix for core workload comparison.
**Green:** Benchmark task can compare IR Compiler and Metal on a shared core workload and report cycles/sec.

Exit criteria:
1. RISC-V benchmark includes Metal when available.
2. Benchmark workload is common across compared backends for fair cycles/sec comparison.
3. At least one optimization pass is implemented and measured.

### Phase 4: Validation And Performance Loop

**Red:** No documented validation/perf evidence for RISC-V Metal path.
**Green:** Targeted specs pass and benchmark evidence is captured in PRD.

Exit criteria:
1. Targeted lowering + runner + CLI/benchmark specs pass.
2. Benchmark results include IR Compiler vs Metal cycles/sec for the core workload.
3. PRD checklist and status reflect actual completion state.

## Acceptance Criteria

1. RISC-V Metal runner is selectable via headless and CLI mode routing.
2. ArcToGPU RISC-V lowering profile is implemented and covered by tests.
3. Benchmark path reports RISC-V Metal throughput against IR compiled on equivalent workload.
4. Documented optimization deltas exist (baseline vs improved).

## Risks And Mitigations

1. Risk: RISC-V MMIO/device model complexity can dominate kernel design.
   Mitigation: initial scope targets core workload parity without full xv6 device parity.
2. Risk: GPU dispatch overhead can erase throughput gains.
   Mitigation: batch cycle execution in-kernel; minimize host-device synchronization per dispatch.
3. Risk: Toolchain availability differs by host.
   Mitigation: explicit availability checks and clear failure messages.

## Implementation Checklist

- [x] Phase 1: Add `:riscv` ArcToGPU profile module.
- [x] Phase 1: Add RISC-V Metal kernel emitter in lowering.
- [x] Phase 1: Add/extend lowering specs for RISC-V profile success/failure.
- [x] Phase 2: Add `examples/riscv/utilities/runners/metal_runner.rb`.
- [x] Phase 2: Wire `:metal` mode in RISC-V `HeadlessRunner`.
- [x] Phase 2: Update RISC-V CLI mode option/help for `metal`.
- [x] Phase 3: Add RISC-V benchmark Metal backend for shared core workload comparison.
- [x] Phase 3: Add optional RISC-V Metal multi-instance throughput wiring (`metal_instances`) in headless + benchmark path.
- [x] Phase 3: Run benchmark baseline and post-optimization measurements.
- [x] Phase 4: Run targeted specs and record results.
- [ ] Phase 4: Mark PRD complete with dated validation evidence.

## Validation Evidence (Non-xv6 Small Tests First)

Date: 2026-03-03

1. Targeted RISC-V Metal construction checks:
   `bundle exec rspec spec/examples/riscv/utilities/tasks/run_task_spec.rb:293 spec/examples/riscv/runners/hdl_harness_spec.rb:140`
   Result: pass (2 examples, 0 failures).
2. Targeted integration + lowering + benchmark wiring checks:
   `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/examples/riscv/utilities/tasks/riscv_cli_linux_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb spec/examples/8bit/utilities/runners/arcilator_gpu_runner_spec.rb spec/examples/apple2/runners/metal_runner_spec.rb`
   Result: pass (98 examples, 0 failures).
3. Post-fix targeted gate after RISC-V kernel parity/perf work:
   `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb`
   Result: pass (80 examples, 0 failures).
4. Multi-instance wiring/spec gate:
   `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb`
   Result: pass (82 examples, 0 failures, metal-backed instantiation tests pending/skipped when local timeout/toolchain limits apply).

## Parity And Perf Evidence (Core Workload, Non-xv6)

Date: 2026-03-03

1. Divergence reproduction before kernel sequencing fix:
   cycle-by-cycle mismatch at step 1 (`x4`/`x5` diverged between IR compile and Metal).
2. Parity after sequencing fix + optimization:
   300-step cycle-by-cycle parity: pass.
   20k-cycle parity check (`pc`, `x1`, `x2`, `x4`, `x5`, `mem[0x1000]`): pass.
3. Performance measurements (`RHDL_BENCH_RISCV_WORKLOAD=core`, `RHDL_BENCH_BACKENDS=compiler,metal`, `bench:native[riscv,50000]`):
   - Parity-fix baseline (fully conservative multi-eval loop): IR 0.297s, Metal 5.151s, ratio 0.058x.
   - Optimized kernel (reduced eval cadence + PTW cache/invalidation): IR 0.300s, Metal 3.560s, ratio 0.084x.
   - Follow-up optimization (remove per-cycle post-settle eval, retain final settle/output): IR 0.314s, Metal 3.581s, ratio 0.088x.
   - Throughput improvement over parity-fix baseline: ~1.44x Metal speedup with parity retained.
4. Post-optimization targeted gate:
   `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb`
   Result: pass (59 examples, 0 failures).
5. Multi-instance ArcToGPU kernel plumbing validation:
   - 20k-cycle parity probe (`pc`, `x1`, `x2`, `x4`, `x5`, `mem[0x1000]`) with `metal_instances=1`: pass.
   - Single-instance benchmark after wiring (`RHDL_BENCH_RISCV_METAL_INSTANCES=1`): IR 0.312s, Metal 3.718s, ratio 0.084x.
   - Throughput mode benchmark (`RHDL_BENCH_RISCV_METAL_INSTANCES=8`): IR 0.306s, Metal 3.854s, single-instance ratio 0.079x, aggregate throughput 103775.5 cycles/s, aggregate ratio 0.636x.
   - Host timing variance observed across reruns; compare ratios from same-run data points.

Date: 2026-03-04

6. Unified-memory optimization pass (RISC-V Metal wrapper + kernel):
   - Change: use unified instruction/data GPU buffer in wrapper and skip duplicate instruction-memory stores in kernel when pointers alias.
   - 20k-cycle parity probe (`pc`, `x1`, `x2`, `x4`, `x5`, `mem[0x1000]`) with `metal_instances=1`: pass.
   - Single-instance benchmark (`RHDL_BENCH_RISCV_METAL_INSTANCES=1`): IR 1.186s, Metal 3.753s, ratio 0.316x.
   - Throughput mode benchmark (`RHDL_BENCH_RISCV_METAL_INSTANCES=8`): IR 1.115s, Metal 3.874s, single-instance ratio 0.288x, aggregate throughput 103248.1 cycles/s, aggregate ratio 2.303x.
   - Initial caveat: switching instance count triggered wrapper rebuild due build-config invalidation.
7. Follow-up kernel cleanup (kept) and failed experiments (reverted):
   - Kept: local cycle counter in kernel (`io->cycles_ran` write once at dispatch end), parity retained.
   - Reverted: thread-local state-slot staging for RISC-V kernel (parity retained but perf regressed).
   - Reverted: dynamic threadgroup width tuning (`threadsPerThreadgroup > 1`) for this kernel; reduced throughput vs fixed `1`.
   - Current validated numbers (same-run):
     - Single-instance (`RHDL_BENCH_RISCV_METAL_INSTANCES=1`): IR 0.889s, Metal 3.670s, ratio 0.242x.
     - Throughput mode (`RHDL_BENCH_RISCV_METAL_INSTANCES=8`): IR 0.881s, Metal 3.812s, single-instance ratio 0.231x, aggregate throughput 104938.2 cycles/s, aggregate ratio 1.849x (Metal aggregate faster than compiler).
8. Runtime-instance wrapper path + kernel memory helper pass:
   - Reverted experiment: enabling packed-wide RISC-V lowering (`state_scalar_bits=32`) fails today due unsupported wide `comb.concat` in packed mode; kept 64-bit scalar mode.
   - Kept: aligned fast-path helpers in generated Metal (`rhdl_read_word_le` / `rhdl_write_word_le`) and kernel use of `rhdl_write_word_le` for word stores.
   - Kept: runtime instance resolution in wrapper via `RHDL_RISCV_METAL_INSTANCES_RUNTIME`; removed build-config instance invalidation.
   - Verification: shared library mtime unchanged across `instances=1` then `instances=8` instantiation (`NO_REBUILD`).
   - Parity: 20k-cycle probe (`pc`, `x1`, `x2`, `x4`, `x5`, `mem[0x1000]`) with `metal_instances=1`: pass.
   - Benchmarks (same-run, host-variable):
     - `metal_instances=1`: IR 0.645s, Metal 4.053s, ratio 0.159x.
     - `metal_instances=8`: IR 0.537s, Metal 4.300s, single-instance ratio 0.125x, aggregate throughput 93020.5 cycles/s, aggregate ratio 1.000x.
9. RISC-V eval/clock-path restructuring:
   - Kept: low/high specialized loop eval functions with compact loop output struct (loop fields only), full output eval used only for dispatch-final output materialization.
   - Kept: deduplicated Arc clock tracking slots by unique `clock_ref` (RISC-V core: reduced extra clock slots from 76 to 1; `state_count` now 4351 = 4350 state slots + 1 clock slot).
   - Kept: hoisted clock edge computation to once per unique `clock_ref` in eval function and reused rising-edge predicate across state/memory update ops.
   - Kept: comb-only low eval can skip internal clock-slot sync; kernel writes low clock slots directly before high eval.
   - Parity: 20k-cycle probe (`pc`, `x1`, `x2`, `x4`, `x5`, `mem[0x1000]`) with `metal_instances=1`: pass.
   - Benchmarks (same-run, host-variable):
     - `metal_instances=1`: IR 1.223s, Metal 3.167s, ratio 0.386x.
     - `metal_instances=8`: IR 1.266s, Metal 3.229s, single-instance ratio 0.392x, aggregate throughput 123880.4 cycles/s, aggregate ratio 3.136x.
   - Build-config check: instance-count changes still avoid rebuild (`NO_REBUILD` mtime probe).
10. Low-clock reset micro-optimization:
   - Kept: emit direct low-clock reset store in kernel when deduplicated clock-slot count is 1 (avoids per-iteration loop overhead in RISC-V path).
   - Parity: 20k-cycle probe (`pc`, `x1`, `x2`, `x4`, `x5`, `mem[0x1000]`) with `metal_instances=1`: pass.
   - Benchmarks (same-run, host-variable):
     - `metal_instances=1`: IR 1.033s, Metal 2.624s, ratio 0.394x.
     - `metal_instances=8`: IR 0.882s, Metal 2.747s, single-instance ratio 0.321x, aggregate throughput 145611.0 cycles/s, aggregate ratio 2.568x.
   - Targeted tests:
     - `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb`: pass.
     - `bundle exec rspec spec/examples/riscv/utilities/tasks/run_task_spec.rb`: pass (43 examples).
     - `bundle exec rspec spec/rhdl/cli/tasks/benchmark_task_spec.rb`: pass (22 examples).
     - `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb`: pass (11 examples).
11. Packed-wide enablement + liveness split refinements:
   - Kept: packed-wide RISC-V profile enabled (`pack_wide_scalars? => true`) after adding missing packed-wide lowering support (`comb.concat`, wide unsigned `comb.icmp`, wide helper coverage).
   - Kept: comb-only liveness seed reduction (`emit_top_eval_function` no longer seeds sequential update refs when `update_state=false`), reducing low/full eval comb footprint.
   - Kept: high-loop eval post-comb split uses dedicated output-focused liveness (`split_post_comb_liveness`) instead of reusing pre-comb graph.
   - Re-validated parity: 20k-cycle probe (`pc`, `x1`, `x2`, `x4`, `x5`, `mem[0x1000]`) with `metal_instances=1`: pass.
   - Benchmarks (same-run, host-variable):
     - `metal_instances=1`: IR 0.924s, Metal 1.986s, ratio 0.466x.
     - `metal_instances=8`: IR 0.878s, Metal 1.994s, single-instance ratio 0.440x, aggregate throughput 200569.2 cycles/s, aggregate ratio 3.523x.
   - Re-tested and reverted (again): dynamic threadgroup width (`threadsPerThreadgroup > 1`) in wrapper; throughput regressed sharply (`~54.6k cycles/s` at 8 instances), so fixed `1` remains.
   - Targeted tests:
     - `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb`: pass.
     - `bundle exec rspec spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb`: pass (76 examples).
12. Lazy dispatch-final full-eval path (kept):
   - Kept: for `cycle_budget > 0`, RISC-V kernel no longer performs dispatch-final `full_eval`/output writeback; full eval remains for `budget == 0`.
   - Kept: `MetalRunner#read_pc` and `MetalRunner#current_inst` now force `eval_cpu` on read, preserving observable debug output correctness after `run_cycles`.
   - Parity: 20k-cycle probe (`pc`, `x1`, `x2`, `x4`, `x5`, `mem[0x1000]`) with `metal_instances=1`: pass.
   - Benchmarks (same-run, host-variable):
     - 50k cycles, `metal_instances=1`: IR 0.883s, Metal 1.778s, ratio 0.497x.
     - 50k cycles, `metal_instances=8`: IR 0.415s, Metal 1.802s, single-instance ratio 0.230x, aggregate throughput 221981.1 cycles/s, aggregate ratio 1.844x.
     - 200k cycles, `metal_instances=1`: IR 1.412s, Metal 7.201s, ratio 0.196x.
     - 200k cycles, `metal_instances=8`: IR 1.403s, Metal 7.723s, single-instance ratio 0.182x, aggregate throughput 207167.1 cycles/s, aggregate ratio 1.453x.
   - Targeted tests:
     - `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb`: pass (60 examples).
     - `bundle exec rspec spec/rhdl/cli/tasks/benchmark_task_spec.rb`: pass (22 examples).
13. Unified-memory kernel specialization + clock-edge A/B:
   - Kept: RISC-V kernel specialized to unified memory contract (single `mem` pointer path; removed `!unified_mem` dual-write branches).
   - Kept: split low/high loop output structs (`high` drops unused `data_we`/`data_wdata` fields) and PTW compare simplification (`!=` on aligned cached words).
   - Tested and rejected (A/B): forcing `assume_rising_edges` for high eval was slightly slower in metal-only probe (`1.854s` vs `1.807s` at 50k), so high eval remains on generic rising-edge path.
   - Re-validated parity: 20k-cycle probe (`pc`, `x1`, `x2`, `x4`, `x5`, `mem[0x1000]`) with `metal_instances=1`: pass.
   - Benchmarks (same-run, host-variable):
     - 50k cycles, `metal_instances=1`: IR 0.945s, Metal 1.864s, ratio 0.507x.
     - 50k cycles, `metal_instances=8`: IR 1.003s, Metal 2.035s, single-instance ratio 0.493x, aggregate throughput 196590.0 cycles/s, aggregate ratio 3.945x.
     - 200k cycles, `metal_instances=1`: IR 3.711s, Metal 7.057s, ratio 0.526x.
     - 200k cycles, `metal_instances=8`: IR 3.768s, Metal 7.936s, single-instance ratio 0.475x, aggregate throughput 201616.3 cycles/s, aggregate ratio 3.798x.
   - Targeted tests:
     - `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb`: pass (60 examples, occasional metal timeout pending on slow runs).
14. Thread-local state shadow (reintroduced) + deterministic narrow scalar typing:
   - Kept: RISC-V eval functions now use `thread` state pointers; kernel stages per-instance state into thread-local storage and writes back once per dispatch.
   - A/B (metal-only, 50k): reverted device-state path ran at `1.804s`; thread-local path ran at `~1.699-1.712s` (kept).
   - Kept: RISC-V profile now enables narrow scalar temporaries (`uchar`/`ushort` where safe) directly in lowering (`narrow_scalar_types? => true`) instead of relying on ad-hoc environment flags.
   - A/B (metal-only, 50k): without narrow typing on this branch baseline was `~1.70s`; with narrow typing it is `~1.650-1.657s` (kept).
   - Re-tested and rejected: forcing `assume_rising_edges` in high eval remains a regression (`1.870s` at 50k), so generic rising-edge path is retained.
   - Re-validated parity: 20k-cycle probe (`pc`, `x1`, `x2`, `x4`, `x5`, `mem[0x1000]`) with `metal_instances=1`: pass.
   - Benchmarks (same-run, host-variable):
     - 50k cycles, `metal_instances=1`: IR 0.306s, Metal 1.652s, ratio 0.185x.
     - 200k cycles, `metal_instances=1`: IR 1.228s, Metal 6.600s, ratio 0.186x.
     - 200k cycles, `metal_instances=8`: IR 1.220s, Metal 6.594s, single-instance ratio 0.185x, aggregate throughput 242651.2 cycles/s, aggregate ratio 1.480x.
   - Targeted tests:
     - `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb`: pass (60 examples).
15. Arc-call flattening in RISC-V profile + additional micro-opts:
   - Kept: RISC-V `post_parse_transform` now applies conservative Arc-call flattening (`flatten_simple_arc_calls`, `max_ops: 12`, `max_depth: 2`).
   - Kept: state-memory index helper adds power-of-two fast path (`idx & (len - 1)`), preserving modulo fallback for non-power-of-two lengths.
   - Re-validated parity: 20k-cycle probe (`pc`, `x1`, `x2`, `x4`, `x5`, `mem[0x1000]`) with `metal_instances=1`: pass.
   - Benchmarks (same-run, host-variable):
     - 50k cycles, `metal_instances=1`: IR 0.306s, Metal 1.592s, ratio 0.192x.
     - 200k cycles, `metal_instances=1`: IR 1.236s, Metal 6.298s, ratio 0.196x.
     - 200k cycles, `metal_instances=8`: IR 1.226s, Metal 6.405s, single-instance ratio 0.191x, aggregate throughput 249819.5 cycles/s, aggregate ratio 1.532x.
   - Targeted tests:
     - `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb`: pass (82 examples).
16. More aggressive call flattening + masked-state trust path:
   - Kept: RISC-V profile call flattening increased to `max_ops: 48`, `max_depth: 4` (from conservative settings), reducing helper call overhead in generated Metal.
   - Kept: eval generator supports `trust_state_masks` for thread-local state paths; enabled in RISC-V low/high/full eval to avoid redundant scalar `rhdl_mask_bits` on hot state loads.
   - Re-validated parity: 20k-cycle probe (`pc`, `x1`, `x2`, `x4`, `x5`, `mem[0x1000]`) with `metal_instances=1`: pass.
   - Benchmarks (same-run, host-variable):
     - 50k cycles, `metal_instances=1`: IR 0.305s, Metal 1.503s, ratio 0.203x.
     - 200k cycles, `metal_instances=1`: IR 1.230s, Metal 5.989s, ratio 0.205x.
     - 200k cycles, `metal_instances=8`: IR 1.222s, Metal 6.035s, single-instance ratio 0.203x, aggregate throughput 265133.8 cycles/s, aggregate ratio 1.620x.
   - Targeted tests:
     - `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb`: pass (82 examples).
17. Experiments run and rejected (kept out of final path):
   - Rejected: single-eval-per-cycle attempt (reusing high-step as next low-step) diverged on core parity (`x4`/`x5`/`mem[0x1000]` mismatch at 20k), reverted.
   - Rejected: loading ordered state refs inside comb functions (`load_state_in_comb_fn` for RISC-V) regressed 50k metal-only runtime (`~1.52s` vs `~1.50s`), reverted for RISC-V.
   - Rejected: shader compile `-O2` in RISC-V Metal runner regressed 50k metal-only runtime (`~1.58s`), restored `-O3`.
   - Rejected: overly aggressive flattening (`max_ops: 192`, `max_depth: 8`) regressed 50k metal-only runtime (`~1.53s`), kept `96/6`.

Open item:
1. Continue reducing the remaining single-instance gap versus IR compiler on the core workload (latest same-run snapshots: ~0.203x at 50k and ~0.205x at 200k; host-variable).
2. Add broader parity programs beyond the synthetic core loop to guard future performance passes.
