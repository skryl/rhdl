# RISC-V ArcToGPU Metal Performance Phase 2 PRD

**Status:** In Progress (2026-03-04)  
**Date:** 2026-03-04

## Context

`prd/2026_03_03_riscv_arctogpu_metal_runner_prd.md` established a working RISC-V ArcToGPU Metal path with core-workload parity and meaningful aggregate throughput in multi-instance mode. The remaining issue is the single-instance performance gap versus IR compiled execution on long runs.

The latest validated snapshots in the prior PRD still show single-instance Metal behind compiler on the synthetic core workload (for example, around `0.203x` at 50k cycles and `0.205x` at 200k cycles in same-run comparisons), even though multi-instance aggregate throughput can exceed compiler.

This follow-on PRD defines the next optimization wave in explicit phases, with hard red/green gates and benchmark evidence at 5k / 50k / 500k cycles.

## Goals

1. Reduce single-instance RISC-V Metal runtime overhead on the core workload.
2. Preserve cycle parity and externally visible runner semantics.
3. Eliminate avoidable host/device synchronization and hot-loop external I/O in batch execution.
4. Reduce generated kernel work by removing dead helpers/temporaries and minimizing state traffic.
5. Improve multi-instance throughput scaling without regressing single-instance behavior.
6. Produce repeatable benchmark evidence (`cycles/s` and ratio vs compiler) at 5k, 50k, and 500k.

## Non-Goals

1. Upstreaming ArcToGPU changes to CIRCT in this phase.
2. Full xv6/Linux MMIO parity in Metal mode.
3. Replacing the existing RISC-V architecture model or IR compiler backend.
4. Broad benchmark redesign outside targeted RISC-V core workload/perf harness changes.

## Phased Plan

### Phase 0: Baseline + Measurement Harness Hardening

**Red:** No locked baseline for 5k/50k/500k with explicit sync/dispatch assumptions.  
**Green:** Baseline measurements and instrumentation are captured, with clearly defined “one dispatch per batch” execution contract.

Exit criteria:
1. Record baseline compiler vs Metal timings (`instances=1` and throughput mode) at 5k, 50k, and 500k.
2. Record current dispatch/wait behavior in wrapper and benchmark docs.
3. Add/extend a benchmark guard check that fails if batching contract regresses (unexpected extra dispatch/sync in a single `run_cycles` batch).

### Phase 1: Host Sync And Dispatch Contract Tightening

**Red:** Batch execution still performs unnecessary host-visible sync/read/write operations in hot paths.  
**Green:** For `run_cycles(N)` with `N > 0`, hot-loop execution performs no intermediate host syncs; sync/wait is deferred to dispatch completion only.

Exit criteria:
1. No host waits inside per-cycle loop logic in native wrapper path.
2. Exactly one kernel dispatch per contiguous `run_cycles` batch in benchmark flow.
3. Hot-loop external writes (debug/output materialization) occur only when required by API semantics.
4. RISC-V parity checks remain green.

### Phase 2: State Traffic Reduction (Hot/Cold Split + Selective Snapshotting)

**Red:** Kernel loop and eval paths still snapshot/copy more state than required by live update/output cones.  
**Green:** State staging/snapshotting is liveness-driven and split by access pattern.

Exit criteria:
1. Selective `comb_pre` snapshotting includes only refs required by update logic and required outputs.
2. Hot/cold state strategy is implemented (hot refs local/thread-cached, cold refs direct as needed) with a profile-safe fallback.
3. State copy loops and loop-time state reads/writes are reduced and measured.
4. Parity remains green for targeted RISC-V checks.

### Phase 3: Emitted-Code Cleanup (Liveness DCE + Array Peepholes + Helper Reachability DCE)

**Red:** Generated Metal includes dead helper graph, avoidable temporaries, and pattern-generated allocas in hot eval paths.  
**Green:** Emission is pruned to live work only, and common temporary-heavy patterns are folded away.

Exit criteria:
1. Liveness-driven comb emission only materializes refs needed for updates/required outputs.
2. Peepholes fold `array_get(array_create(...), idx)` and `array_get(aggregate_constant(...), idx)` when statically safe.
3. Reachability-based helper DCE removes unused generated helper functions.
4. Generated-source size and/or compiler warnings for unused helpers drop measurably.

### Phase 4: Call/Inline Policy Retuning (Performance-Safe Flattening)

**Red:** Inline and flattening behavior is either too conservative in hot paths or too aggressive globally, causing regressions.  
**Green:** Inline/flatten policy is profile-tuned by function size/use, improving runtime without parity risk.

Exit criteria:
1. Generated helper annotations distinguish tiny/hot helpers from large eval functions (avoid blanket `always_inline` on large bodies).
2. Flattening thresholds are re-tuned with bounded caps and A/B evidence.
3. No regression in shader compile reliability for RISC-V Metal path.
4. Targeted perf probes show non-negative delta versus Phase 3.

### Phase 5: Multi-Instance And Threadgroup Scaling Pass

**Red:** Instance scaling exists but threadgroup/mapping strategy remains fixed and under-tuned for current kernels.  
**Green:** Throughput path is tuned for instance-level parallelism with explicit no-regression guard for `instances=1`.

Exit criteria:
1. Threadgroup sizing/mapping policy is explicit and benchmarked (including rejected variants if they regress).
2. `instances > 1` path improves aggregate `cycles/s` on at least one long-run point (50k or 500k).
3. `instances=1` performance does not regress beyond agreed tolerance (<=5% from prior phase median on same host/run conditions).

### Phase 6: Validation, Documentation, And Completion Gate

**Red:** Optimizations exist without consolidated parity/perf evidence and completion criteria closure.  
**Green:** PRD includes full evidence for parity + performance gates and checklist/status reflects real completion.

Exit criteria:
1. Targeted specs for lowering/runner/benchmark wiring pass.
2. Parity checks for RISC-V Metal vs compiler on core workload pass at required checkpoints.
3. Benchmark table for 5k / 50k / 500k includes compiler vs Metal (`instances=1`, and throughput mode where enabled) with `cycles/s` and ratio.
4. PRD status is updated to `Completed (date)` only when all phase exit criteria are satisfied.

### Phase 7: Kernel Variant Specialization (Invariant Inputs)

**Red:** Core benchmark executes fully generic kernel path even when selected top-level inputs are invariant for workload duration.  
**Green:** Metal core workload supports an explicit specialization mode that pins safe invariant inputs and produces a measurable speedup with parity intact.

Exit criteria:
1. Add a benchmark-visible toggle for core specialization (`on/off`) with explicit reporting.
2. Add ArcToGPU lowering support for safe invariant input pinning in RISC-V profile/kernel emission.
3. Ensure build artifacts are invalidated when specialization toggles change (no stale shader A/B).
4. Re-run parity/perf probes demonstrating no functional regression and non-negative runtime delta.

### Phase 8: Fast/Slow Kernel Split

**Red:** One monolithic kernel handles both common-case and rare-case logic, inflating hot-path instruction count and branch pressure.  
**Green:** Dispatch path supports separate fast and fallback kernels, with runtime selection based on explicit preconditions.

Exit criteria:
1. Introduce a fast kernel constrained to common-case conditions and a correctness-preserving fallback.
2. Add dispatch-time gating logic and instrumentation to report fast-path hit rate.
3. Prove parity with fallback coverage for rare cases.
4. Show net runtime improvement on core workload at 50k/500k.

### Phase 9: Dirty-Cone / Event-Driven Execution

**Red:** Every cycle recomputes broad combinational regions even when active signal cone is small.  
**Green:** Generated path supports dirty propagation and evaluates only impacted cones per cycle segment.

Exit criteria:
1. Build dependency/fanout index for refs used in cycle update path.
2. Add dirty-set propagation and selective op evaluation.
3. Validate parity under targeted regressions and benchmark programs.
4. Demonstrate reduced per-cycle work and measurable speedup.

### Phase 10: Scheduled Dataflow Emitter

**Red:** Current codegen emits mostly linear op text with limited scheduling structure for backend optimization.  
**Green:** RISC-V path has a schedule-aware emitter mode (levelized blocks and explicit phase regions) that can target GPU execution patterns.

Exit criteria:
1. Add schedule extraction/lowering structure alongside existing emitter (profile-gated).
2. Preserve semantics and fallback to legacy emitter when disabled.
3. Validate with existing lowering/runner tests.
4. Use schedule metadata as the basis for later parallel execution work.

### Phase 11: Single-Instance Intra-Kernel Parallelism

**Red:** Single-instance path is effectively single-threaded per simulated core, leaving significant GPU compute underutilized.  
**Green:** Single-core simulation can partition combinational work across lanes in a threadgroup with synchronization barriers and deterministic ordering.

Exit criteria:
1. Define a partition strategy from Arc schedule metadata (work chunks + barrier points).
2. Implement multi-lane execution path for at least one stable phase region.
3. Validate parity against compiler/interpreter checkpoints.
4. Demonstrate meaningful single-instance speedup versus prior phase.

## Acceptance Criteria

1. All phases execute with explicit red/green evidence and checklist updates.
2. No cycle-parity regressions are introduced in targeted RISC-V Metal parity checks.
3. Single-instance Metal performance improves by at least `1.5x` versus this PRD’s Phase 0 baseline on at least two of the three benchmark points (5k, 50k, 500k).
4. Throughput mode (`instances > 1`) remains operational and demonstrates aggregate scaling evidence with no hidden semantic drift.
5. Benchmark reporting clearly distinguishes single-instance ratio vs aggregate throughput ratio.

## Risks And Mitigations

1. Risk: aggressive pruning/peepholes can alter cycle semantics.
   Mitigation: keep parity checks as hard gates after each phase; default to conservative fallback when uncertain.
2. Risk: host timing variance can obscure performance deltas.
   Mitigation: compare same-run measurements and capture multiple runs when changes are close.
3. Risk: threadgroup or flattening changes can improve one regime and regress another.
   Mitigation: keep explicit A/B probes for 5k/50k/500k and enforce `instances=1` no-regression tolerance.
4. Risk: codegen complexity increases maintenance burden.
   Mitigation: keep profile-specific logic isolated and documented; require targeted specs for new transforms.

## Testing Gates

1. Lowering/codegen unit gates:
   - `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb`
2. RISC-V runner/task gates:
   - `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb`
3. Benchmark task gate:
   - `bundle exec rspec spec/rhdl/cli/tasks/benchmark_task_spec.rb`
4. Perf/parity execution gate (core workload):
   - `bundle exec rake 'bench:native[riscv,5000]'`
   - `bundle exec rake 'bench:native[riscv,50000]'`
   - `bundle exec rake 'bench:native[riscv,500000]'`
   with explicit env capture for backend filter and instance count.

## Implementation Checklist

- [x] Phase 0: Capture 5k/50k/500k baseline table (compiler vs Metal; `instances=1` and throughput mode).
- [x] Phase 0: Document current dispatch/wait contract and add regression guard check.
- [x] Phase 1: Remove remaining hot-loop intermediate host sync/read/write operations.
- [x] Phase 1: Enforce one-dispatch-per-batch contract in benchmarked `run_cycles` path.
- [x] Phase 1: Re-run parity probes and targeted specs.
- [x] Phase 2: Implement selective `comb_pre` snapshotting for required refs only.
- [x] Phase 2: Implement hot/cold state handling in RISC-V Metal profile/generator.
- [x] Phase 2: Measure state-traffic reduction impact on 5k/50k/500k benchmarks.
- [x] Phase 3: Add array-get peephole folds for create/aggregate-constant patterns.
- [x] Phase 3: Add helper reachability DCE and liveness-pruned comb emission.
- [x] Phase 3: Record generated-code and performance deltas.
- [x] Phase 4: Retune inline/flatten settings with bounded heuristics and A/B evidence.
- [x] Phase 4: Keep compile reliability checks and revert regressive settings.
- [x] Phase 5: Tune threadgroup/instance mapping for throughput mode with `instances=1` guard.
- [x] Phase 5: Record aggregate throughput scaling evidence.
- [x] Phase 6: Run full targeted spec gates and parity checkpoints.
- [x] Phase 6: Publish final benchmark table and close Phase 6 validation gates.
- [x] Phase 7: Add specialization toggle/plumbing + rebuild-safe A/B for invariant-input kernel variants.
- [x] Phase 7: Validate parity and measure specialization-on vs specialization-off deltas.
- [x] Phase 8: Implement fast-path kernel dispatch and enforce fast-only runtime path (fallback path removed per updated requirement).
- [ ] Phase 9: Implement dirty-cone/event-driven combinational execution.
- [x] Phase 10: Add schedule-aware dataflow emitter mode for RISC-V ArcToGPU path (profile-gated; default off pending perf-positive tuning).
- [ ] Phase 11: Implement single-instance intra-kernel parallel execution from schedule partitions.

## Execution Update (2026-03-04)

Implemented in this pass:

1. Added RISC-V lowering transforms:
   - Constant-fold `hw.array_get(hw.array_create(...), const_idx)` into alias.
   - Constant-fold `hw.array_get(hw.aggregate_constant(...), const_idx)` into constant.
   - Reachability-prune unused `arc.define` functions from the parsed call graph.
2. Added additional liveness pruning:
   - Function-body op emission now liveness-prunes to outputs.
   - `split_post_comb_liveness` path no longer seeds output refs into `comb_pre`.
   - Budgeted RISC-V kernel path now stages/copies back value-state slots only (`clock` tracking slots are not copied for `budget > 0` dispatches).
3. Retuned generated inline policy (initial pass):
   - Top eval/comb functions use non-forced inline.
   - `arc.define` helpers use bounded always-inline heuristic (`<= 12` ops, small returns), with env overrides.
4. Added dispatch/wait batch instrumentation in RISC-V Metal wrapper:
   - Exported `sim_dispatch_count` / `sim_wait_count`.
   - Exposed `MetalRunner#dispatch_count` / `#wait_count`.
   - Benchmark now reports dispatch/wait counts per benchmark batch.
   - Added guard env `RHDL_BENCH_VERIFY_DISPATCH_BATCH=1` to fail when per-batch dispatch count is not exactly 1.

Validation gates run:

1. `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb`  
   Result: pass.
2. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb`  
   Result: pass.

Dispatch contract probe:

1. `RHDL_BENCH_RISCV_WORKLOAD=core RHDL_BENCH_BACKENDS=metal RHDL_BENCH_RISCV_METAL_INSTANCES=1 RHDL_BENCH_VERIFY_DISPATCH_BATCH=1 bundle exec rake 'bench:native[riscv,5000]'`  
   Result: pass, `Metal dispatches: 1 per benchmark batch`, `Metal waits: 1 per benchmark batch`.

Benchmark baselines (core workload, same-run points):

Single-instance (`RHDL_BENCH_RISCV_METAL_INSTANCES=1`, `RHDL_BENCH_BACKENDS=compiler,metal`):

1. `5000` cycles: IR `0.031s`, Metal `0.152s`, ratio `0.203x`.
2. `50000` cycles: IR `0.309s`, Metal `1.487s`, ratio `0.208x`.
3. `500000` cycles: IR `3.100s`, Metal `14.828s`, ratio `0.209x`.

Throughput mode (`RHDL_BENCH_RISCV_METAL_INSTANCES=8`, `RHDL_BENCH_BACKENDS=compiler,metal`):

1. `5000` cycles: IR `0.031s`, Metal `0.153s`, single-instance ratio `0.199x`, aggregate ratio `1.591x`.
2. `50000` cycles: IR `0.306s`, Metal `1.482s`, single-instance ratio `0.207x`, aggregate ratio `1.652x`.
3. `500000` cycles: IR `3.095s`, Metal `14.860s`, single-instance ratio `0.208x`, aggregate ratio `1.666x`.

Notes:

1. Current batching contract is enforced and observed as one dispatch + one wait per benchmark `run_steps(cycles)` call.
2. Inline/flatten A/B now includes rebuild-correct comparisons with explicit keep/revert outcomes.
3. Single-instance gap remains large; next work is Phase 2/5 (state traffic reduction + scaling strategy) to improve single-instance runtime while preserving parity.

## Execution Update (2026-03-04, Continued)

Implemented in this continuation pass:

1. Completed RISC-V hot/cold state split in emitted kernel path:
   - `emit_kernel_riscv` now accepts `cold_memory_layout`.
   - Large cold memory ranges are excluded from per-batch thread-local copy for `budget > 0`.
   - Eval functions are invoked with explicit `cold_state_slots` pointer for cold memory read/write ops.
   - Hot state ranges are copied back at batch end; cold ranges stay device-resident.
2. Added threadgroup mapping policy in native Metal wrapper:
   - Replaced fixed `threadsPerThreadgroup = 1` with dynamic width derived from
     `pipeline.threadExecutionWidth`, bounded by `maxTotalThreadsPerThreadgroup` and `instanceCount`.
   - Kept one-dispatch/one-wait contract per benchmark batch.

Validation gates run:

1. `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb`  
   Result: pass.
2. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb`  
   Result: pass.
3. `RHDL_BENCH_RISCV_WORKLOAD=core RHDL_BENCH_BACKENDS=metal RHDL_BENCH_RISCV_METAL_INSTANCES=8 RHDL_BENCH_VERIFY_DISPATCH_BATCH=1 bundle exec rake 'bench:native[riscv,50000]'`  
   Result: pass, dispatch/wait remains `1/1` per batch.
4. Inline policy A/B probe (`instances=1`, `500000` cycles, Metal-only):
   - default inline policy: `14.265s`
   - `RHDL_ARC_TO_GPU_FORCE_ALWAYS_INLINE=1`: `14.241s`
   - `RHDL_ARC_TO_GPU_DISABLE_ALWAYS_INLINE=1`: `14.246s`
   Result: differences are within run noise; no default-policy change from this probe.

Post-change benchmarks (core workload, same-run points):

Single-instance (`RHDL_BENCH_RISCV_METAL_INSTANCES=1`, `RHDL_BENCH_BACKENDS=compiler,metal`):

1. `5000` cycles: IR `0.032s`, Metal `0.155s`, ratio `0.205x`.
2. `50000` cycles: IR `0.319s`, Metal `1.432s`, ratio `0.222x`.
3. `500000` cycles: IR `3.163s`, Metal `14.246s`, ratio `0.222x`.

Throughput mode (`RHDL_BENCH_RISCV_METAL_INSTANCES=8`, `RHDL_BENCH_BACKENDS=compiler,metal`):

1. `5000` cycles: IR `0.031s`, Metal `0.152s`, single-instance ratio `0.206x`, aggregate ratio `1.652x`.
2. `50000` cycles: IR `0.315s`, Metal `1.447s`, single-instance ratio `0.218x`, aggregate ratio `1.743x`.
3. `500000` cycles: IR `3.141s`, Metal `14.426s`, single-instance ratio `0.218x`, aggregate ratio `1.742x`.

Observed deltas versus earlier baseline in this PRD:

1. Single-instance ratio improved from ~`0.209x` baseline to ~`0.222x` on long runs (`500k`).
2. Throughput aggregate ratio improved from ~`1.666x` baseline to ~`1.742x` on long runs (`500k`, `instances=8`).
3. Metal is still behind IR compiler in `instances=1`; remaining work is focused on Phase 4 code-shape/inlining retuning and deeper kernel-level hot-loop simplification.

## Execution Update (2026-03-04, Continued 2)

Implemented in this continuation pass:

1. Added explicit ArcToGPU tuning knobs:
   - `RHDL_ARC_TO_GPU_RISCV_FLATTEN_MAX_OPS`
   - `RHDL_ARC_TO_GPU_RISCV_FLATTEN_MAX_DEPTH`
   - `RHDL_ARC_TO_GPU_ALWAYS_INLINE_MAX_OPS`
   - `RHDL_ARC_TO_GPU_ALWAYS_INLINE_MAX_RETURNS`
2. Fixed Metal build invalidation for tuning correctness:
   - RISC-V Metal runner now records tracked ArcToGPU env values in `riscv_metal_build_config.json`.
   - Any tracked env change now forces a rebuild, preventing stale-shader A/B results.
3. Attempted kernel loop refactor (single helper-call-per-cycle) and reverted:
   - Rebuild-correct benchmarks showed regression versus baseline.
   - Kept existing hot loop shape to satisfy no-regression requirement.
4. Ran flatten/inlining A/B with rebuild correctness:
   - Candidate flatten `160/8` looked better in stale-cache runs but regressed in rebuild-correct runs.
   - Baseline `96/6` retained as default.

Validation gates run:

1. `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb`  
   Result: pass.
2. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb`  
   Result: pass.
3. `RHDL_BENCH_RISCV_WORKLOAD=core RHDL_BENCH_BACKENDS=metal RHDL_BENCH_RISCV_METAL_INSTANCES=8 RHDL_BENCH_VERIFY_DISPATCH_BATCH=1 bundle exec rake 'bench:native[riscv,50000]'`  
   Result: pass, dispatch/wait remains `1/1` per batch.

Rebuild-correct flatten A/B evidence (`instances=1`, `500000` cycles, Metal-only):

1. Baseline `96/6`: `14.447s`
2. Candidate `160/8`: `14.690s`
3. Decision: keep baseline defaults.

Latest benchmark table (core workload, same-run points):

Single-instance (`RHDL_BENCH_RISCV_METAL_INSTANCES=1`, `RHDL_BENCH_BACKENDS=compiler,metal`):

1. `5000` cycles: IR `0.032s`, Metal `0.149s`, ratio `0.213x`.
2. `50000` cycles: IR `0.329s`, Metal `1.451s`, ratio `0.227x`.
3. `500000` cycles: IR `3.140s`, Metal `14.468s`, ratio `0.217x`.

Throughput mode (`RHDL_BENCH_RISCV_METAL_INSTANCES=8`, `RHDL_BENCH_BACKENDS=compiler,metal`):

1. `5000` cycles: IR `0.032s`, Metal `0.147s`, single-instance ratio `0.216x`, aggregate ratio `1.729x`.
2. `50000` cycles: IR `0.315s`, Metal `1.475s`, single-instance ratio `0.214x`, aggregate ratio `1.710x`.
3. `500000` cycles: IR `3.143s`, Metal `14.651s`, single-instance ratio `0.215x`, aggregate ratio `1.716x`.

Current outcome:

1. Phase 4 is complete with explicit A/B and keep/revert behavior.
2. Perf remains materially below IR compiler for `instances=1`.
3. Next progress likely requires architecture-level changes (true multi-thread-in-kernel partitioning or per-workload specialized kernels), not further small inline/flatten tweaks.

## Execution Update (2026-03-04, Continued 3)

Implemented in this continuation pass:

1. Added architecture-phase scaffolding in this PRD (Phase 7-11):
   - invariant-input kernel specialization
   - fast/slow kernel split
   - dirty-cone/event-driven execution
   - schedule-aware emitter
   - intra-kernel parallel partitioning
2. Executed Phase 7 (invariant-input specialization) first:
   - Added benchmark toggle `RHDL_BENCH_RISCV_METAL_CORE_SPECIALIZE` with explicit benchmark reporting.
   - Added `metal_core_specialize` plumbing from benchmark -> `HeadlessRunner` -> `MetalRunner`.
   - Added ArcToGPU RISC-V kernel invariant pinning for safe IRQ inputs (`irq_software`, `irq_timer`, `irq_external`).
3. Hardened specialization A/B reliability:
   - Build invalidation now tracks specialization env in `riscv_metal_build_config.json`.
4. Correctness fix during execution:
   - Initial specialization attempt that pinned `debug_reg_addr` and `rst` caused external-observability/reset regressions.
   - Reverted those pins and kept only safe IRQ invariant pins.

Validation gates run:

1. `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb`  
   Result: pass (`88` examples, `0` failures).
2. `RHDL_BENCH_RISCV_METAL_CORE_SPECIALIZE=1 RHDL_BENCH_RISCV_WORKLOAD=core RHDL_BENCH_BACKENDS=metal RHDL_BENCH_RISCV_METAL_INSTANCES=8 RHDL_BENCH_VERIFY_DISPATCH_BATCH=1 bundle exec rake 'bench:native[riscv,50000]'`  
   Result: pass, dispatch/wait remains `1/1` per batch.

Specialization A/B (Metal-only, `instances=1`):

1. `5000` cycles: off `0.161s`, on `0.142s` (~`1.13x` faster).
2. `50000` cycles: off `1.461s`, on `1.416s` (~`1.03x` faster).
3. `500000` cycles: off `14.496s`, on `14.177s` (~`1.02x` faster).

Latest benchmark table with specialization enabled (`RHDL_BENCH_RISCV_METAL_CORE_SPECIALIZE=1`):

Single-instance (`RHDL_BENCH_RISCV_METAL_INSTANCES=1`, `RHDL_BENCH_BACKENDS=compiler,metal`):

1. `5000` cycles: IR `0.031s`, Metal `0.143s`, ratio `0.221x`.
2. `50000` cycles: IR `0.311s`, Metal `1.417s`, ratio `0.220x`.
3. `500000` cycles: IR `3.095s`, Metal `14.203s`, ratio `0.218x`.

Throughput mode (`RHDL_BENCH_RISCV_METAL_INSTANCES=8`, `RHDL_BENCH_BACKENDS=compiler,metal`):

1. `5000` cycles: IR `0.031s`, Metal `0.156s`, single-instance ratio `0.198x`, aggregate ratio `1.587x`.
2. `50000` cycles: IR `0.312s`, Metal `1.439s`, single-instance ratio `0.217x`, aggregate ratio `1.734x`.
3. `500000` cycles: IR `3.084s`, Metal `14.405s`, single-instance ratio `0.214x`, aggregate ratio `1.713x`.

Current outcome:

1. Phase 7 is executed with measurable positive delta and preserved parity/dispatch contracts.
2. Phase 8-11 remain pending and are now the primary path to material single-instance gains.
3. PRD remains `In Progress` because later optimization phases and full acceptance criteria (notably the `1.5x` single-instance target) are still unmet.

## Execution Update (2026-03-04, Continued 4)

Implemented in this continuation pass:

1. Removed RISC-V Metal runtime fallback dispatch path:
   - Wrapper no longer builds/keeps a secondary fallback pipeline.
   - Dispatch always targets the fast ArcToGPU kernel entry.
   - Runtime gating method for fallback selection was removed.
2. Simplified ArcToGPU metadata + kernel emission for RISC-V:
   - Removed separate `metal.fast_entry` metadata key.
   - Primary kernel entry now emits/uses the fast-path kernel body directly.
3. Preserved metrics compatibility while enforcing no fallback:
   - `dispatch_count`, `wait_count`, `fast_dispatch_count` remain exported.
   - `fallback_dispatch_count` remains exported and now reports `0`.
4. Fixed runner FIRRTL API wiring in this branch shape:
   - Added explicit `require 'rhdl/codegen/firrtl/firrtl'` so `RHDL::Codegen::FIRRTL.generate` resolves during Metal build.
5. Added runner coverage:
   - Extended `spec/examples/riscv/runners/hdl_harness_spec.rb` with `MetalRunner` definition/interface checks.

Validation gates run:

1. `bundle exec rake native:build`  
   Result: pass (rebuilt IR + netlist native extensions used for parity/perf comparisons).
2. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb:90`  
   Result: pass (`62` examples, `0` failures).
3. Direct parity/dispatch probe (Metal runner):
   - `run_cycles(500000)` delta counters: `dispatch=1`, `wait=1`, `fast=1`, `fallback=0`.
   - Final state: `pc=0x14`, `x1=0x186B4` (matches compiler run for same core loop program).

Direct harness benchmark (core loop program, warmup + timed batch):

1. `5000` cycles: IR `0.031s`, Metal `0.101s`, ratio `0.305x`.
2. `50000` cycles: IR `0.318s`, Metal `0.999s`, ratio `0.318x`.
3. `500000` cycles: IR `3.232s`, Metal `9.904s`, ratio `0.326x`.

Current outcome:

1. Runtime fallback path is eliminated for the RISC-V Metal ArcToGPU dispatch path.
2. Batch contract and parity checkpoints remain intact on the core loop workload.
3. Single-instance Metal remains below IR compiler, but current long-run ratio improved to ~`0.326x` on this host/run.

## Execution Update (2026-03-04, Continued 5)

Implemented in this continuation pass:

1. Closed Phase 6 checklist gating item:
   - Marked Phase 6 benchmark/reporting gate complete in this PRD checklist.
2. Started Phase 9 (dirty-cone/event-driven path) on RISC-V lowering:
   - Added profile-level toggle `RHDL_ARC_TO_GPU_RISCV_DIRTY_SETTLE`.
   - Added dirty-set tracking in the fast high-loop eval function (`track_state_dirty` + `state_dirty` output).
   - Added conservative fast-forward rule in fast kernel loop:
     - if `high.state_dirty == 0` and `low.data_we == 0`, mark remaining batch cycles as completed and exit loop early.
   - Kept this path **opt-in** (default off) due neutral/slightly regressive core-loop A/B.
3. Ensured rebuild correctness for A/B:
   - Added `RHDL_ARC_TO_GPU_RISCV_DIRTY_SETTLE` to Metal build-config tracked env vars.
4. Added lowering regression coverage:
   - New spec verifies dirty-settle guard emission when toggle is enabled.

Validation gates run:

1. `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb`  
   Result: pass (`61` examples, `0` failures).
2. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb:90`  
   Result: pass (`63` examples, `0` failures).

Direct dirty-settle A/B benchmark (core loop, direct harness):

1. `5000` cycles:
   - IR `0.030s`
   - Metal dirty=0 `0.105s` (`0.289x`)
   - Metal dirty=1 `0.116s` (`0.262x`)
2. `50000` cycles:
   - IR `0.318s`
   - Metal dirty=0 `0.996s` (`0.319x`)
   - Metal dirty=1 `0.994s` (`0.320x`)
3. `500000` cycles:
   - IR `3.173s`
   - Metal dirty=0 `9.824s` (`0.323x`)
   - Metal dirty=1 `9.844s` (`0.322x`)

Dispatch/parity checkpoints in this A/B:

1. Per timed batch: `dispatch=1`, `wait=1`, `fast=1`, `fallback=0`.
2. Final parity: `pc=0x14`, `x1=0x3FC/0x2724/0x186B4` matches IR at 5k/50k/500k.

Current outcome:

1. Phase 9 functionality is now present behind a guarded toggle with parity intact.
2. Core-loop throughput benefit is not yet demonstrated; default remains `dirty_settle=off` until improved heuristics/partitioning are added.
3. Next work remains Phase 9 refinement (higher-hit-rate dirty criteria), then Phase 10 scheduling groundwork.

## Execution Update (2026-03-04, Continued 6)

Implemented in this continuation pass:

1. Executed Phase 10 schedule-aware emitter groundwork for RISC-V:
   - Added profile toggle `RHDL_ARC_TO_GPU_RISCV_SCHEDULED_EMIT`.
   - Added profile metadata mode reporting (`legacy` vs `levelized`).
   - Added levelized emission structure for comb/post-comb op generation (schedule phase + schedule level markers).
   - Kept legacy emission as default fallback path (`scheduled_emit=0`).
2. Added rebuild-safe A/B support:
   - Added `RHDL_ARC_TO_GPU_RISCV_SCHEDULED_EMIT` to Metal runner tracked ArcToGPU env vars.
3. Added coverage:
   - New lowering spec verifies schedule-aware markers and metadata when enabled.
   - Existing RISC-V lowering/runner/task gates remain green.

Validation gates run:

1. `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb`  
   Result: pass (`62` examples, `0` failures).
2. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb:90`  
   Result: pass (`64` examples, `0` failures).

Direct scheduled-emitter A/B benchmark (core loop, dirty-settle forced off):

1. `5000` cycles:
   - IR `0.031s`
   - Metal scheduled=0 `0.106s` (`0.291x`)
   - Metal scheduled=1 `0.115s` (`0.266x`)
2. `50000` cycles:
   - IR `0.320s`
   - Metal scheduled=0 `1.002s` (`0.319x`)
   - Metal scheduled=1 `1.010s` (`0.316x`)
3. `500000` cycles:
   - IR `3.209s`
   - Metal scheduled=0 `9.828s` (`0.326x`)
   - Metal scheduled=1 `9.878s` (`0.325x`)

Dispatch/parity checkpoints in this A/B:

1. Per timed batch: `dispatch=1`, `wait=1`, `fast=1`, `fallback=0`.
2. Final parity: `pc=0x14`, `x1=0x3FC/0x2724/0x186B4` matches IR at 5k/50k/500k.

Current outcome:

1. Phase 10 structure is implemented and profile-gated with legacy fallback preserved.
2. Current levelized emission is performance-neutral to slightly regressive on core loop; default remains `scheduled_emit=off`.
3. Next work is Phase 9 refinement and then Phase 11 intra-kernel parallel partitioning built on this schedule metadata.

## Execution Update (2026-03-04, Continued 7)

Implemented in this continuation pass:

1. Refined Phase 9 dirty-tracking overhead:
   - Updated generated `state_dirty` writeback checks to short-circuit once dirty is already set.
   - This avoids repeated expensive state equality comparisons after first detected mutation in a cycle.
2. Kept dirty-settle as profile-gated behavior (`RHDL_ARC_TO_GPU_RISCV_DIRTY_SETTLE`) with default off.

Validation gates run:

1. `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb`  
   Result: pass (`11` examples, `0` failures).
2. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb:90`  
   Result: pass (`64` examples, `0` failures).

Direct dirty-settle A/B benchmark after short-circuit change (scheduled emit forced off):

1. `5000` cycles:
   - IR `0.031s`
   - Metal dirty=0 `0.113s` (`0.273x`)
   - Metal dirty=1 `0.114s` (`0.269x`)
2. `50000` cycles:
   - IR `0.323s`
   - Metal dirty=0 `1.003s` (`0.323x`)
   - Metal dirty=1 `1.007s` (`0.321x`)
3. `500000` cycles:
   - IR `3.246s`
   - Metal dirty=0 `9.894s` (`0.328x`)
   - Metal dirty=1 `9.908s` (`0.328x`)

Dispatch/parity checkpoints:

1. Per timed batch: `dispatch=1`, `wait=1`.
2. Final parity: `pc=0x14`, `x1=0x3FC/0x2724/0x186B4` remains aligned with IR at 5k/50k/500k.

Current outcome:

1. Dirty tracking overhead is reduced and now near-neutral in long runs.
2. Core-loop still does not show a positive dirty-settle speedup, so default remains off pending better quiescence heuristics or workload-specific gating.

## Execution Update (2026-03-04, Continued 8)

Implemented in this continuation pass:

1. Added Phase 9 selective-eval split for fast low-loop write data:
   - Added profile toggle `RHDL_ARC_TO_GPU_RISCV_SPLIT_LOW_WDATA` (default off).
   - Added split output sets:
     - base fast low outputs (without `data_wdata`)
     - dedicated fast low write-data output (`data_wdata`) in a separate eval function.
   - Fast kernel now evaluates the dedicated low write-data function only when `low0.data_we != 0`.
2. Added metadata and rebuild tracking:
   - Added `metal.fast_low_wdata_mode` metadata (`inline` or `split`).
   - Added `RHDL_ARC_TO_GPU_RISCV_SPLIT_LOW_WDATA` to tracked build env vars in Metal runner.
3. Added lowering coverage:
   - New spec verifies split fast low write-data function emission and metadata mode when enabled.

Validation gates run:

1. `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb`  
   Result: pass (`12` examples, `0` failures).
2. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb:90`  
   Result: pass (`65` examples, `0` failures).

Direct split A/B benchmark (core loop, dirty-settle/scheduled emit off, core specialization on):

1. split=0:
   - `5000`: IR `0.030s`, Metal `0.113s` (`0.267x`)
   - `50000`: IR `0.317s`, Metal `0.990s` (`0.320x`)
   - `500000`: IR `3.170s`, Metal `9.838s` (`0.322x`)
2. split=1:
   - `5000`: IR `0.033s`, Metal `0.112s` (`0.294x`)
   - `50000`: IR `0.316s`, Metal `0.986s` (`0.321x`)
   - `500000`: IR `3.171s`, Metal `9.808s` (`0.323x`)

Parity checkpoints in this A/B:

1. Final state parity remained aligned (`pc=0x14`, `x1=0x3FB/0x2723/0x186B3`, `mem[0x100]=0x55`).
2. Batch counters observed as `dispatch=3`, `wait=3`, `fast=3`, `fallback=0` in probe output because post-batch state reads trigger extra `sim_eval` calls; timed batch dispatch contract for `run_cycles` remains one kernel dispatch per call.

Current outcome:

1. Split low write-data selective eval is implemented and parity-clean for the core loop probe.
2. Throughput delta is small but non-negative on 50k/500k in this run.
3. Phase 9 remains in progress; next work is to extend selective eval to other conditional cones with a clearer long-run speedup.

## Execution Update (2026-03-04, Continued 9)

Implemented in this continuation pass:

1. Added Phase 9 selective-eval split for fast high-loop data address:
   - Added profile toggle `RHDL_ARC_TO_GPU_RISCV_SPLIT_HIGH_DATA_ADDR` (default off).
   - Added split output sets:
     - base fast high outputs (without `data_addr`)
     - dedicated fast high data-address output (`data_addr`) in a separate eval function.
   - Fast kernel now evaluates the dedicated high data-address function only when `high.data_re != 0`.
2. Added metadata and rebuild tracking:
   - Added `metal.fast_high_data_addr_mode` metadata (`inline` or `split`).
   - Added `RHDL_ARC_TO_GPU_RISCV_SPLIT_HIGH_DATA_ADDR` to tracked build env vars in Metal runner.
3. Added lowering coverage:
   - New spec verifies split fast high data-address function emission and metadata mode when enabled.

Validation gates run:

1. `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb`  
   Result: pass (`13` examples, `0` failures).
2. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb:90`  
   Result: pass (`66` examples, `0` failures).

Direct split-combination A/B benchmark (core loop, dirty-settle/scheduled emit off, core specialization on):

1. baseline (`low=0 high=0`):
   - `5000`: IR `0.031s`, Metal `0.118s` (`0.260x`)
   - `50000`: IR `0.318s`, Metal `0.993s` (`0.320x`)
   - `500000`: IR `3.179s`, Metal `9.840s` (`0.323x`)
2. low split only (`low=1 high=0`):
   - `5000`: IR `0.032s`, Metal `0.111s` (`0.292x`)
   - `50000`: IR `0.317s`, Metal `0.992s` (`0.319x`)
   - `500000`: IR `3.178s`, Metal `9.848s` (`0.323x`)
3. high split only (`low=0 high=1`):
   - `5000`: IR `0.032s`, Metal `0.110s` (`0.293x`)
   - `50000`: IR `0.318s`, Metal `1.001s` (`0.317x`)
   - `500000`: IR `3.179s`, Metal `9.894s` (`0.321x`)
4. both splits (`low=1 high=1`):
   - `5000`: IR `0.032s`, Metal `0.114s` (`0.284x`)
   - `50000`: IR `0.322s`, Metal `0.999s` (`0.322x`)
   - `500000`: IR `3.203s`, Metal `9.843s` (`0.325x`)

Parity checkpoints in this A/B:

1. Final state parity remained aligned for all configs (`pc=0x14`, `x1=0x3FB/0x2723/0x186B3`, `mem[0x100]=0x55`).
2. Probe counter deltas show `dispatch=3`, `wait=3`, `fast=3`, `fallback=0` because the script reads state after timing and triggers evals; timed batch dispatch contract for `run_cycles` remains one dispatch per call.

Current outcome:

1. High data-address selective eval is implemented and parity-clean.
2. Combined low+high split is slightly best at longer points in this run, but gains are still small.
3. Phase 9 remains in progress; next optimization should target larger conditional cones (for example PTW outputs or decode/debug cone split) to increase long-run delta.

## Execution Update (2026-03-04, Continued 10)

Implemented in this continuation pass:

1. Reduced fast-loop invariant input churn:
   - Hoisted constant PTW input-zero writes (`inst_ptw_pte0/1`, `data_ptw_pte0/1`) out of the per-cycle loop in the fast kernel path.
   - This keeps semantics aligned with existing fast path behavior (always-zero PTW PTE inputs in loop mode) while removing repeated per-iteration stores.
2. Re-ran split-combination A/B after this change.

Validation gates run:

1. `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb`  
   Result: pass (`13` examples, `0` failures).

Direct split-combination A/B benchmark after invariant-hoist (core loop, dirty-settle/scheduled emit off, core specialization on):

1. baseline (`low=0 high=0`):
   - `5000`: IR `0.033s`, Metal `0.106s` (`0.311x`)
   - `50000`: IR `0.319s`, Metal `1.020s` (`0.313x`)
   - `500000`: IR `3.207s`, Metal `9.746s` (`0.329x`)
2. low split only (`low=1 high=0`):
   - `5000`: IR `0.033s`, Metal `0.108s` (`0.308x`)
   - `50000`: IR `0.319s`, Metal `1.017s` (`0.313x`)
   - `500000`: IR `3.558s`, Metal `9.763s` (`0.364x`) *(IR timing variance observed in this run)*
3. high split only (`low=0 high=1`):
   - `5000`: IR `0.032s`, Metal `0.111s` (`0.288x`)
   - `50000`: IR `0.320s`, Metal `1.012s` (`0.316x`)
   - `500000`: IR `3.217s`, Metal `9.773s` (`0.329x`)
4. both splits (`low=1 high=1`):
   - `5000`: IR `0.032s`, Metal `0.108s` (`0.295x`)
   - `50000`: IR `0.324s`, Metal `0.984s` (`0.329x`)
   - `500000`: IR `3.217s`, Metal `9.725s` (`0.331x`)

Parity checkpoints in this A/B:

1. Final state parity remained aligned for all configs (`pc=0x14`, `x1=0x3FB/0x2723/0x186B3`, `mem[0x100]=0x55`).
2. Probe counter deltas remained `dispatch=3`, `wait=3`, `fast=3`, `fallback=0` due post-timing state reads; timed batch dispatch contract for `run_cycles` remains one dispatch per call.

Current outcome:

1. Fast-loop invariant write churn is reduced, with parity preserved.
2. In this run, combined low+high split remains the best long-run configuration.
3. Phase 9 still needs a larger cone-level pruning pass to achieve a clearer single-instance gain.

## Execution Update (2026-03-04, Continued 11)

Implemented in this continuation pass:

1. Added Phase 9 selective-eval split for fast low-loop data address:
   - Added profile toggle `RHDL_ARC_TO_GPU_RISCV_SPLIT_LOW_DATA_ADDR` (default off).
   - Added split output sets:
     - base fast low outputs (without `data_addr`)
     - dedicated fast low data-address output (`data_addr`) in a separate eval function.
   - Fast kernel now evaluates the dedicated low data-address function only when `(low.data_re | low.data_we) != 0`.
2. Added metadata and rebuild tracking:
   - Added `metal.fast_low_data_addr_mode` metadata (`inline` or `split`).
   - Added `RHDL_ARC_TO_GPU_RISCV_SPLIT_LOW_DATA_ADDR` to tracked build env vars in Metal runner.
3. Added lowering coverage:
   - New spec verifies split fast low data-address function emission and metadata mode when enabled.

Validation gates run:

1. `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb`  
   Result: pass (`14` examples, `0` failures).
2. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb spec/examples/riscv/utilities/tasks/run_task_spec.rb spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb:90`  
   Result: pass (`67` examples, `0` failures).

Targeted config A/B benchmark (core loop, dirty-settle/scheduled emit off, core specialization on):

1. baseline (`low_w=0 high_addr=0 low_addr=0`):
   - `5000`: IR `0.030s`, Metal `0.111s` (`0.273x`)
   - `50000`: IR `0.321s`, Metal `0.980s` (`0.327x`)
   - `500000`: IR `3.190s`, Metal `9.712s` (`0.328x`)
2. previous combined (`low_w=1 high_addr=1 low_addr=0`):
   - `5000`: IR `0.033s`, Metal `0.109s` (`0.301x`)
   - `50000`: IR `0.321s`, Metal `1.002s` (`0.321x`)
   - `500000`: IR `3.195s`, Metal `9.722s` (`0.329x`)
3. new low-addr only (`low_w=0 high_addr=0 low_addr=1`):
   - `5000`: IR `0.033s`, Metal `0.136s` (`0.242x`)
   - `50000`: IR `0.321s`, Metal `0.979s` (`0.327x`)
   - `500000`: IR `3.192s`, Metal `9.776s` (`0.326x`)
4. all three splits (`low_w=1 high_addr=1 low_addr=1`):
   - `5000`: IR `0.033s`, Metal `0.114s` (`0.286x`)
   - `50000`: IR `0.318s`, Metal `0.995s` (`0.320x`)
   - `500000`: IR `3.672s`, Metal `9.706s` (`0.378x`) *(IR timing variance observed in this run)*

Parity checkpoints in this A/B:

1. Final state parity remained aligned for all configs (`pc=0x14`, `x1=0x3FB/0x2723/0x186B3`, `mem[0x100]=0x55`).
2. Probe counter deltas remained `dispatch=3`, `wait=3`, `fast=3`, `fallback=0` due post-timing state reads; timed batch dispatch contract for `run_cycles` remains one dispatch per call.

Current outcome:

1. Low data-address selective eval is implemented and parity-clean.
2. Measured impact is neutral to slightly regressive on this core loop workload; keep default off.
3. Next meaningful gain likely requires larger cone-level pruning (for example gated PTW/debug/decode cone emission), not additional micro-splits.

## Execution Update (2026-03-04, Continued 12)

Implemented in this continuation pass:

1. Corrected high data-address split helper semantics:
   - The dedicated high data-address helper is now emitted as comb-only (`update_state: false` and no comb-only clock-slot sync side effects).
   - This avoids accidental double state-update risk when helper is invoked conditionally after high update step.
2. Re-ran the targeted config A/B matrix to confirm parity and updated timing trends.

Validation gates run:

1. `bundle exec rspec spec/rhdl/codegen/firrtl/arc_to_gpu_lowering_spec.rb`  
   Result: pass (`14` examples, `0` failures).

Targeted config A/B benchmark after semantic fix (core loop, dirty-settle/scheduled emit off, core specialization on):

1. baseline (`low_w=0 high_addr=0 low_addr=0`):
   - `5000`: IR `0.030s`, Metal `0.111s` (`0.275x`)
   - `50000`: IR `0.320s`, Metal `0.985s` (`0.325x`)
   - `500000`: IR `3.188s`, Metal `9.791s` (`0.326x`)
2. previous combined (`low_w=1 high_addr=1 low_addr=0`):
   - `5000`: IR `0.032s`, Metal `0.114s` (`0.284x`)
   - `50000`: IR `0.318s`, Metal `0.984s` (`0.323x`)
   - `500000`: IR `3.183s`, Metal `9.753s` (`0.326x`)
3. new low-addr only (`low_w=0 high_addr=0 low_addr=1`):
   - `5000`: IR `0.033s`, Metal `0.107s` (`0.305x`)
   - `50000`: IR `0.319s`, Metal `0.997s` (`0.320x`)
   - `500000`: IR `3.193s`, Metal `9.856s` (`0.324x`)
4. all three splits (`low_w=1 high_addr=1 low_addr=1`):
   - `5000`: IR `0.032s`, Metal `0.113s` (`0.285x`)
   - `50000`: IR `0.317s`, Metal `0.979s` (`0.324x`)
   - `500000`: IR `3.250s`, Metal `9.677s` (`0.336x`)

Parity checkpoints in this A/B:

1. Final state parity remained aligned for all configs (`pc=0x14`, `x1=0x3FB/0x2723/0x186B3`, `mem[0x100]=0x55`).
2. Probe counter deltas remained `dispatch=3`, `wait=3`, `fast=3`, `fallback=0` due post-timing state reads; timed batch dispatch contract for `run_cycles` remains one dispatch per call.

Current outcome:

1. High split helper semantics are now correctness-safe by construction.
2. Best observed long-run config in this pass is all three selective splits enabled, with a small improvement versus baseline.
3. Gains remain modest; larger cone-level pruning is still required for meaningful single-instance improvement.
