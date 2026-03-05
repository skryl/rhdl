# CPU8bit GEM-to-GPU Integration PRD

## Status
In Progress (updated 2026-03-04; phases 1-7 complete, phase 8 in progress, phase 9 in progress, phases 10-14 planned)

## Context
We need a new GPU path for CPU8bit that does not depend on arcilator Arc lowering and can be analyzed/planned with GEM-style graph metadata. The existing `synth_to_gpu` path lowers HW/Synth MLIR to Metal, but it does not annotate partition/layer execution metadata. We also need the backend to be first-class in harness and benchmarks.

A hard requirement remains in scope: GPU execution must maintain parity with the IR compiler path for complex 8-bit programs (Conway, Mandelbrot, etc.).

Scope correction: phases 1-3 delivered GEM integration, parity validation, and baseline benchmarks. Full GEM-paper execution behavior is not complete yet. The remaining paper-aligned architecture work (VBP/VLIW execution model, dynamic scheduling, RepCut/merge partitioning, timing-aware boomerang repartitioning, and device-side synchronization) is tracked in phases 9-14 below.

## Goals
1. Add a `gem_gpu` backend for CPU8bit that builds via Synth->GPU lowering with GEM-style graph analysis metadata.
2. Integrate `gem_gpu` into `FastHarness` and native benchmark task (`bench:native[cpu8bit,*]`).
3. Add tests covering lowering metadata, harness backend behavior, and benchmark backend filtering.
4. Validate complex-program parity against IR compiler path for CPU8bit.
5. Record benchmark results for compiler vs ArcToGPU vs SynthToGPU vs GemGPU at `5k`, `50k`, and `500k` cycles.
6. Implement execution-path changes aligned with the GEM paper: dependency-aware partition/layer scheduling, reduced synchronization, and throughput improvements.
7. Add a GEM-style VBP instruction stream path (bit-level ops + compact control stream) rather than metadata-only planning.
8. Implement two-level dynamic scheduling (partition-level dependency scheduling and intra-device work distribution).
9. Implement paper-style partition optimization passes (RepCut-like partitioning and partition-merge refinement).
10. Implement timing-aware repartitioning/floorplan heuristics (boomerang-style critical-path rebalancing) and measure single-instance impact.

## Non-Goals
1. Re-architecting Apple2 or RISC-V GPU paths.
2. Upstream CIRCT/arcilator changes.
3. Cross-vendor CUDA-specific runtime implementation in this PRD (this plan remains Metal-first).

## Phased Plan

### Phase 1: GEM Lowering Stage
Red:
1. Add failing lowering spec requiring GEM metadata in output JSON (`version`, `gem` stats).
2. Add deterministic expectations for partition/layer stats on a fixed synth fixture.

Green:
1. Add `GemToGpuLowering` wrapper around `SynthToGpuLowering`.
2. Implement deterministic synth graph analysis (`synth.aig.and_inv` dependency graph, depth/layer/partition metrics).
3. Persist GEM metadata fields into lowering JSON artifact.

Exit Criteria:
1. Lowering emits `version=GemToGpuLoweringV1`.
2. `gem` metadata block is present and deterministic across repeated lowering runs.

### Phase 2: CPU8bit Runner/Harness/Benchmark Integration
Red:
1. Add failing harness tests for `FastHarness(sim: :gem_gpu)` runner behavior and error surfacing.
2. Add failing benchmark task test for `RHDL_BENCH_BACKENDS=gem` alias mapping.

Green:
1. Wire `gem_gpu` pipeline option in CPU8bit Metal runner build path.
2. Add `gem_gpu_status`/availability checks and `sim: :gem_gpu` initialization path in `FastHarness`.
3. Add `gem_gpu` backend entry and `gem -> gem_gpu` filter alias in benchmark task.

Exit Criteria:
1. `FastHarness.new(sim: :gem_gpu)` works as a native runner backend.
2. `bench:native[cpu8bit,*]` can run `GemGPU` and select it via backend filter.

### Phase 3: Complex Parity + Benchmark Validation
Red:
1. Add failing complex parity checks (`gem_gpu` vs compiler) on Conway, Mandelbrot, and arithmetic loop workloads.

Green:
1. Implement/adjust test scaffolding for GEM parity checkpoints.
2. Run targeted spec suite for lowering/harness/benchmark/parity.
3. Run CPU8bit benchmark sweeps at `5k`, `50k`, and `500k` cycles.

Exit Criteria:
1. Complex parity tests pass for selected workloads.
2. Benchmark table recorded with all four backends.

### Phase 4: Partition/Layer-Driven GPU Execution
Red:
1. Add failing integration test that asserts GEM execution consumes partition/layer metadata (not metadata-only writeout).
2. Add failing perf smoke that demonstrates no throughput gain without schedule usage.

Green:
1. Generate execution schedule artifacts from `metadata['gem']` (partition DAG/layer plan).
2. Update Metal wrapper/kernel invocation to execute by partition/layer plan.
3. Keep cycle parity semantics identical to phase-3 behavior.

Exit Criteria:
1. `gem_gpu` runtime actively uses GEM schedule metadata.
2. Parity remains green on complex programs.

### Phase 5: Batch Synchronization Elimination
Red:
1. Add failing instrumentation test showing extra waits inside cycle batches.

Green:
1. Remove per-dispatch host waits during `runner_run_cycles`.
2. Submit all work for a batch in one command-buffer timeline and sync once at batch end.
3. Preserve deterministic IO visibility at documented sync boundaries.

Exit Criteria:
1. No host waits inside batch loop.
2. Throughput improves at `50k`/`500k` compared to phase 3 baseline.

### Phase 6: Kernel/Memory Path Tightening
Red:
1. Add failing tests for packed IO/state layout compatibility guards.

Green:
1. Introduce tighter state/temporary packing for hot path.
2. Reduce redundant loads/stores across partition steps.
3. Inline generated helpers where safe to reduce call overhead.

Exit Criteria:
1. Parity remains green.
2. `gem_gpu` cycles/sec improves materially vs phase 5.

### Phase 7: Multi-Instance Parallel Throughput Mode
Red:
1. Add failing benchmark harness test for N-instance batched API.

Green:
1. Add optional multi-instance execution mode (`N` independent CPU states per dispatch).
2. Map instances to Metal threadgroups with deterministic per-instance memory windows.
3. Add benchmark mode and reporting for single-instance vs multi-instance scaling.

Exit Criteria:
1. Functional parity for each instance.
2. Throughput scaling demonstrated in benchmark logs.

### Phase 8: Interim Baseline and Gap Freeze
Red:
1. Add failing acceptance benchmark thresholds for long runs.

Green:
1. Run full parity suite (complex programs) plus benchmark sweep (`5k`, `50k`, `500k`).
2. Compare against compiler and ArcToGPU baselines.
3. Freeze a measured baseline and map residual GEM-paper gaps to concrete implementation phases.

Exit Criteria:
1. Baseline parity/performance snapshot is recorded and reproducible.
2. Residual GEM-paper gaps are fully enumerated and tracked in phases 9-14.

### Phase 9: VBP/VLIW Execution Path
Red:
1. Add failing lowering spec requiring a serialized GEM instruction stream artifact (opcode stream + block boundaries + metadata version).
2. Add failing runtime spec that asserts `gem_gpu` can execute through instruction-stream interpretation mode.

Green:
1. Add a lowering stage that maps synth AIG ops into a compact VBP-style instruction stream for GPU execution.
2. Encode required primitive ops (boolean compute, state read/write, memory read/write, output materialization, control markers).
3. Emit instruction-stream metadata and checksum for deterministic regeneration tests.

Exit Criteria:
1. End-to-end instruction-stream execution path exists and is selectable.
2. Complex parity tests pass in instruction-stream mode.

### Phase 10: Two-Level Dynamic Scheduler
Red:
1. Add failing scheduler unit tests for partition dependency readiness and deterministic fallback ordering.
2. Add failing perf instrumentation test showing idle partitions/work starvation under static-order execution.

Green:
1. Build a runtime partition DAG scheduler with readiness queues.
2. Add intra-device work distribution (work-stealing or equivalent queue-based balancing) across active workers.
3. Keep a deterministic schedule mode for parity and regression tests.

Exit Criteria:
1. Runtime no longer relies on static partition order only.
2. Parity remains green and scheduler metrics show reduced idle/blocked execution time.

### Phase 11: RepCut + Partition Merge Optimization
Red:
1. Add failing partitioner tests for cut-size balancing and cross-partition edge minimization.
2. Add failing metadata-regression test requiring improved partition metrics over fixed-size slicing.

Green:
1. Implement RepCut-like partition refinement using dependency/cut metrics.
2. Implement partition merge pass to eliminate tiny/high-overhead partitions.
3. Surface tunables and record selected defaults in metadata.

Exit Criteria:
1. Cross-partition edges and/or synchronization points are reduced on CPU8bit synth graphs.
2. Parity remains green with optimized partition plans.

### Phase 12: Timing-Aware Boomerang Repartitioning
Red:
1. Add failing tests for criticality scoring and boomerang-trigger conditions.
2. Add failing benchmark assertion requiring single-instance speedup on long runs after timing-aware repartitioning.

Green:
1. Compute critical-path/timing-criticality metrics from graph depth + activity.
2. Repartition timing-critical partitions with boomerang-style rebalance heuristics.
3. Persist timing annotations and repartition decisions for inspection/regression tests.

Exit Criteria:
1. Timing-criticality metadata is emitted and tested.
2. Single-instance `gem_gpu` throughput improves materially versus Phase 11 baseline.

### Phase 13: Device-Side Sync + Global-State-Read Semantics
Red:
1. Add failing runtime test that detects command-buffer wait per dispatch inside batched execution.
2. Add failing lowering/runtime tests requiring explicit global-state-read semantics in the execution stream.

Green:
1. Add global-state-read modeling in the execution stream and kernel-side consumption path.
2. Remove per-dispatch host wait in batch execution; use single batch fence at defined host-visible boundaries.
3. Add explicit device-side barriers/sync points tied to scheduler dependency boundaries.

Exit Criteria:
1. No per-dispatch host wait remains in batched execution path.
2. Host-visible behavior and parity remain deterministic at documented synchronization boundaries.

### Phase 14: Full GEM-Paper Closeout
Red:
1. Add failing acceptance gates for paper-feature presence (instruction stream, dynamic scheduler, repartitioning, timing-aware path, device-side sync).
2. Add failing performance acceptance checks for single-instance and multi-instance benchmark targets.

Green:
1. Run full parity suite (complex programs) and benchmark sweep (`5k`, `50k`, `500k`, plus long-run target).
2. Compare against compiler, ArcToGPU, and Phase 8 baseline snapshots.
3. Document any remaining deviations from the paper and include measured rationale.

Exit Criteria:
1. All acceptance criteria are satisfied.
2. PRD status can be moved to `Completed`.

## Acceptance Criteria
1. CPU8bit has a functional `gem_gpu` backend in lowering, harness, and benchmark surfaces.
2. GEM metadata (`partition_count`, layer metrics, cross-partition edges, etc.) is emitted and tested.
3. Complex 8-bit programs (Conway, Mandelbrot, arithmetic loop) pass parity against compiler backend.
4. Benchmark results are captured for `5k`, `50k`, and `500k` cycles across compiler/ArcToGPU/SynthToGPU/GemGPU.
5. GEM metadata is consumed by runtime scheduling (not metadata-only).
6. Batch execution avoids in-loop host synchronization and shows improved long-run throughput.
7. Instruction-stream/VBP execution path is implemented, tested, and parity-clean.
8. Two-level dynamic scheduler is implemented with deterministic test mode.
9. RepCut-style partition refinement and partition-merge optimization are implemented and measured.
10. Timing-aware boomerang repartitioning is implemented with recorded critical-path metrics.
11. Batched execution removes per-dispatch host waits and uses explicit device-side synchronization boundaries.
12. Remaining gaps against GEM-paper behavior are either implemented or explicitly documented with measurements and justification.

## Risks and Mitigations
1. Risk: GEM analyzer parse drift from generated synth syntax.
   Mitigation: parse both plain and parenthesized operand forms; lock behavior with deterministic spec fixture.
2. Risk: Harness backend selection regressions.
   Mitigation: dedicated `FastHarness(sim: :gem_gpu)` specs plus benchmark task alias test.
3. Risk: Complex parity regressions hidden by microbench-only validation.
   Mitigation: checkpoint parity tests on Conway/Mandelbrot/arithmetic loop.
4. Risk: Removing synchronization may break host-visible IO semantics.
   Mitigation: define explicit sync boundaries and validate against parity checkpoints.
5. Risk: Multi-instance mode introduces memory aliasing bugs.
   Mitigation: enforce per-instance address-space windows and add deterministic stress tests.
6. Risk: Instruction-stream execution path diverges from existing eval semantics.
   Mitigation: dual-path parity harness (`legacy eval` vs `instruction stream`) with checkpoint-by-checkpoint comparison.
7. Risk: Dynamic scheduler introduces nondeterministic ordering bugs.
   Mitigation: deterministic scheduler mode and seeded queue-order tests.
8. Risk: Timing-aware repartitioning overfits one workload and regresses others.
   Mitigation: evaluate across Conway/Mandelbrot/arithmetic workloads and retain fallback thresholds.
9. Risk: RepCut/merge cost may increase compile/lowering time excessively.
   Mitigation: cache partition plans and gate expensive passes behind measurable perf wins.

## Benchmark Evidence Log
### Phase 3 CPU8bit Benchmark (`RHDL_BENCH_BACKENDS=compiler,arc_to_gpu,synth_to_gpu,gem_gpu`)
Command set:
1. `bundle exec rake "bench:native[cpu8bit,5000]"`
2. `bundle exec rake "bench:native[cpu8bit,50000]"`
3. `bundle exec rake "bench:native[cpu8bit,500000]"`

`5,000` cycles:
1. Compiler: `0.075s` (`66,667 cycles/s`)
2. ArcToGPU: `0.029s` (`172,414 cycles/s`, `2.542x` vs compiler)
3. SynthToGPU: `0.144s` (`34,722 cycles/s`, `0.520x`)
4. GemGPU: `0.128s` (`39,063 cycles/s`, `0.585x`)

`50,000` cycles:
1. Compiler: `0.703s` (`71,124 cycles/s`)
2. ArcToGPU: `0.151s` (`331,126 cycles/s`, `4.665x` vs compiler)
3. SynthToGPU: `1.110s` (`45,045 cycles/s`, `0.633x`)
4. GemGPU: `1.109s` (`45,086 cycles/s`, `0.633x`)

`500,000` cycles:
1. Compiler: `7.103s` (`70,393 cycles/s`)
2. ArcToGPU: `1.239s` (`403,551 cycles/s`, `5.735x` vs compiler)
3. SynthToGPU: `11.038s` (`45,298 cycles/s`, `0.644x`)
4. GemGPU: `11.026s` (`45,347 cycles/s`, `0.644x`)

### Phase 3 Complex Parity Evidence
Command:
1. `bundle exec rspec spec/examples/8bit/hdl/cpu/gem_gpu_complex_parity_spec.rb`

Result:
1. `3 examples, 0 failures`.
2. Workloads validated:
   - Conway glider 80x24 checkpoints
   - Mandelbrot 80x24 checkpoints
   - long-running arithmetic loop checkpoints

### Phase 4 Runtime-Schedule Consumption Evidence
Commands:
1. `bundle exec rspec spec/examples/8bit/utilities/runners/synth_to_gpu_runner_spec.rb spec/rhdl/codegen/firrtl/gem_to_gpu_lowering_spec.rb`
2. `bundle exec rspec spec/examples/8bit/hdl/cpu/gem_gpu_complex_parity_spec.rb`
3. `bundle exec rake "bench:native[cpu8bit,50000]"`
4. `bundle exec rake "bench:native[cpu8bit,500000]"`

Results:
1. GEM metadata now includes execution plan fields:
   - `gem.execution.schedule_version=GemExecutionPlanV1`
   - `gem.execution.partition_order`
   - `gem.execution.layer_count`
   - `gem.execution.dispatch_cycle_granularity`
2. Generated `gem_gpu` wrapper consumes GEM schedule metadata and runs chunked dispatch loop in `sim_runner_run_cycles`.
3. Parity remained green: `3 examples, 0 failures` on complex workloads.
4. Benchmark snapshots after phase 4:
   - `50,000` cycles:
     - Compiler: `0.640s` (`78,125 cycles/s`)
     - ArcToGPU: `0.148s` (`337,838 cycles/s`, `4.326x`)
     - SynthToGPU: `1.120s` (`44,643 cycles/s`, `0.571x`)
     - GemGPU: `1.104s` (`45,290 cycles/s`, `0.580x`)
   - `500,000` cycles:
     - Compiler: `6.621s` (`75,517 cycles/s`)
     - ArcToGPU: `1.212s` (`412,541 cycles/s`, `5.460x`)
     - SynthToGPU: `10.978s` (`45,545 cycles/s`, `0.603x`)
     - GemGPU: `10.973s` (`45,567 cycles/s`, `0.603x`)

### Phase 5 Host-Side Batch Sync Elimination Evidence
Commands:
1. `bundle exec rspec spec/examples/8bit/hdl/cpu/fast_harness_gem_gpu_spec.rb spec/examples/8bit/hdl/cpu/fast_harness_synth_to_gpu_spec.rb spec/examples/8bit/hdl/cpu/fast_harness_arcilator_gpu_spec.rb`
2. `bundle exec rspec spec/examples/8bit/hdl/cpu/gem_gpu_complex_parity_spec.rb`
3. `bundle exec rake "bench:native[cpu8bit,50000]"`
4. `bundle exec rake "bench:native[cpu8bit,500000]"`

Results:
1. `FastHarness#run_cycles` now issues one external `runner_run_cycles(n)` call for native runner backends (host-side batch loop removed).
2. Added regression assertion: `run_cycles(100, batch_size: 16)` calls `runner_run_cycles(100, 0, false)` once and does not issue `runner_run_cycles(16, ...)`.
3. Complex parity remains green: `3 examples, 0 failures`.
4. Benchmark snapshots after phase 5:
   - `50,000` cycles:
     - Compiler: `0.666s` (`75,075 cycles/s`)
     - ArcToGPU: `0.136s` (`367,647 cycles/s`, `4.912x`)
     - SynthToGPU: `1.102s` (`45,372 cycles/s`, `0.604x`)
     - GemGPU: `1.077s` (`46,426 cycles/s`, `0.618x`)
   - `500,000` cycles:
     - Compiler: `6.580s` (`75,988 cycles/s`)
     - ArcToGPU: `1.179s` (`424,088 cycles/s`, `5.581x`)
     - SynthToGPU: `10.779s` (`46,387 cycles/s`, `0.610x`)
     - GemGPU: `10.745s` (`46,533 cycles/s`, `0.612x`)

### Phase 6 Kernel/Memory Path Tightening Evidence
Commands:
1. `bundle exec rspec spec/rhdl/codegen/firrtl/gem_to_gpu_lowering_spec.rb spec/examples/8bit/utilities/runners/synth_to_gpu_runner_spec.rb spec/examples/8bit/hdl/cpu/gem_gpu_complex_parity_spec.rb`
2. `bundle exec rake "bench:native[cpu8bit,5000]"`
3. `bundle exec rake "bench:native[cpu8bit,50000]"`
4. `bundle exec rake "bench:native[cpu8bit,500000]"`

Implementation details:
1. CPU8bit profile now enables aggressive eval generation:
   - `use_state_snapshot: false`
   - `split_post_comb_liveness: true`
   - `trust_state_masks: true`
   - `load_state_in_comb_fn: true`
   - `eval_always_inline: true`
   - `schedule_aware_emit: true`
2. Lowering spec now asserts these runtime-shape properties in generated Metal:
   - no `state_old_*` snapshot temporaries,
   - `always_inline` on `eval_cpu8bit`,
   - presence of split post-comb helper with `state_slots` argument.

Results:
1. Parity remained green: `3 examples, 0 failures` on complex workloads.
2. Benchmarks after phase 6:
   - `5,000` cycles:
     - Compiler: `0.172s` (`29,070 cycles/s`)
     - ArcToGPU: `0.014s` (`357,143 cycles/s`, `12.326x`)
     - SynthToGPU: `0.105s` (`47,619 cycles/s`, `1.640x`)
     - GemGPU: `0.079s` (`63,291 cycles/s`, `2.184x`)
   - `50,000` cycles:
     - Compiler: `1.328s` (`37,651 cycles/s`)
     - ArcToGPU: `0.107s` (`467,290 cycles/s`, `12.463x`)
     - SynthToGPU: `0.786s` (`63,613 cycles/s`, `1.690x`)
     - GemGPU: `0.787s` (`63,532 cycles/s`, `1.687x`)
   - `500,000` cycles:
     - Compiler: `14.330s` (`34,893 cycles/s`)
     - ArcToGPU: `0.930s` (`537,634 cycles/s`, `15.408x`)
     - SynthToGPU: `7.842s` (`63,759 cycles/s`, `1.827x`)
     - GemGPU: `7.811s` (`64,013 cycles/s`, `1.835x`)

### Phase 7 Multi-Instance Parallel Throughput Evidence
Commands:
1. `bundle exec rspec spec/examples/8bit/utilities/runners/synth_to_gpu_runner_spec.rb spec/examples/8bit/hdl/cpu/fast_harness_gem_gpu_spec.rb spec/rhdl/cli/tasks/benchmark_task_spec.rb`
2. `RHDL_CPU8BIT_GPU_INSTANCES=8 bundle exec rspec spec/examples/8bit/hdl/cpu/gem_gpu_complex_parity_spec.rb`
3. `RHDL_CPU8BIT_GPU_INSTANCES=1 RHDL_BENCH_BACKENDS=gem_gpu bundle exec rake "bench:native[cpu8bit,500000]"`
4. `RHDL_CPU8BIT_GPU_INSTANCES=8 RHDL_BENCH_BACKENDS=compiler,gem_gpu bundle exec rake "bench:native[cpu8bit,500000]"`
5. `RHDL_CPU8BIT_GPU_INSTANCES=16 RHDL_BENCH_BACKENDS=gem_gpu bundle exec rake "bench:native[cpu8bit,500000]"`

Implementation details:
1. CPU8bit kernel emitter now uses `tid`-indexed slices for state/memory/io in generic `emit_kernel`:
   - `state_slots = all_state_slots + (tid * state_slot_count)`
   - `memory = all_memory + (tid * 65536)`
   - `io = all_io + tid`
2. Runner wrapper now allocates buffers for `INSTANCE_COUNT` and dispatches `INSTANCE_COUNT` threads per call.
3. Runner API exposes `runner_parallel_instances`.
4. `FastHarness` exposes `parallel_instances`.
5. Benchmark output now reports `Instances` and `Effective` cycles/s, plus `Effective Performance Ratios` when multi-instance mode is active.

Results:
1. Targeted specs remain green (`39 examples, 0 failures`).
2. Complex parity remains green with `RHDL_CPU8BIT_GPU_INSTANCES=8` (`3 examples, 0 failures`).
3. Multi-instance throughput scaling (GemGPU, `500,000` cycles):
   - `instances=1`: `8.724s` (`57,313 cycles/s`)
   - `instances=8`: `8.736s` raw (`57,234 cycles/s`), effective `457,882 cycles/s`
   - `instances=16`: `8.748s` raw (`57,155 cycles/s`), effective `914,503 cycles/s`
4. With compiler baseline (`instances=8`, `500,000` cycles):
   - Compiler: `6.503s` (`76,888 cycles/s`)
   - GemGPU raw: `0.744x` vs compiler
   - GemGPU effective: `5.955x` vs compiler

### Phase 8 Interim Baseline Evidence (In Progress)
Commands:
1. `bundle exec rspec spec/examples/8bit/hdl/cpu/gem_gpu_complex_parity_spec.rb`
2. `RHDL_CPU8BIT_GPU_INSTANCES=8 bundle exec rspec spec/examples/8bit/hdl/cpu/gem_gpu_complex_parity_spec.rb`
3. `RHDL_BENCH_BACKENDS=compiler,arc_to_gpu,synth_to_gpu,gem_gpu bundle exec rake "bench:native[cpu8bit,5000]"`
4. `RHDL_BENCH_BACKENDS=compiler,arc_to_gpu,synth_to_gpu,gem_gpu bundle exec rake "bench:native[cpu8bit,50000]"`
5. `RHDL_BENCH_BACKENDS=compiler,arc_to_gpu,synth_to_gpu,gem_gpu bundle exec rake "bench:native[cpu8bit,500000]"`
6. `RHDL_CPU8BIT_GPU_INSTANCES=8 RHDL_BENCH_BACKENDS=compiler,gem_gpu bundle exec rake "bench:native[cpu8bit,5000]"`
7. `RHDL_CPU8BIT_GPU_INSTANCES=8 RHDL_BENCH_BACKENDS=compiler,gem_gpu bundle exec rake "bench:native[cpu8bit,50000]"`
8. `RHDL_CPU8BIT_GPU_INSTANCES=8 RHDL_BENCH_BACKENDS=compiler,gem_gpu bundle exec rake "bench:native[cpu8bit,500000]"`

Results snapshot:
1. Parity remains green in both modes:
   - `instances=1`: `3 examples, 0 failures`
   - `instances=8`: `3 examples, 0 failures`
2. Single-instance benchmark (`instances=1`):
   - `5,000`: Compiler `0.070s`, ArcToGPU `0.031s`, SynthToGPU `0.105s`, GemGPU `0.087s`
   - `50,000`: Compiler `0.662s`, ArcToGPU `0.116s`, SynthToGPU `0.868s`, GemGPU `0.869s`
   - `500,000`: Compiler `6.525s`, ArcToGPU `0.973s`, SynthToGPU `8.680s`, GemGPU `8.681s`
3. Multi-instance (`instances=8`) effective scaling:
   - `5,000`: GemGPU effective `385,721 cycles/s` (`5.652x` vs compiler)
   - `50,000`: GemGPU effective `451,529 cycles/s` (`6.010x` vs compiler)
   - `500,000`: GemGPU effective `457,826 cycles/s` (`6.092x` vs compiler)

Residual gap for final closeout:
1. Single-instance GemGPU is still below compiler on this snapshot (`~0.75x` at `50k/500k`).
2. Multi-instance mode provides the intended throughput win (`~6x effective` vs compiler); this baseline defines targets for phases 9-14.

### Phase 9 VBP/VLIW Instruction-Stream Scaffolding (In Progress)
Commands:
1. `bundle exec rspec spec/rhdl/codegen/firrtl/gem_to_gpu_lowering_spec.rb spec/examples/8bit/utilities/runners/synth_to_gpu_runner_spec.rb`
2. `bundle exec rspec spec/examples/8bit/hdl/cpu/gem_gpu_instruction_stream_parity_spec.rb`
3. `RHDL_GEM_GPU_EXECUTION_MODE=instruction_stream bundle exec rspec spec/examples/8bit/hdl/cpu/gem_gpu_complex_parity_spec.rb`
4. `RHDL_GEM_GPU_EXECUTION_MODE=instruction_stream RHDL_BENCH_BACKENDS=compiler,gem_gpu bundle exec rake "bench:native[cpu8bit,50000]"`

Results:
1. GEM metadata now emits deterministic instruction-stream artifacts:
   - `gem.instruction_stream.version=GemInstructionStreamV1`
   - `instruction_count`, `block_boundaries`, `extern_refs`, `instructions`, `primitive_counts`, `control_program`, and `checksum_sha256`
   - execution metadata now includes partition dependency shape:
     - `gem.partition_dependency_edges`
     - `gem.execution.partition_dependency_edge_count`
     - `gem.execution.ready_layer_count`
     - `gem.execution.ready_layers`
2. `gem_gpu` runner/wrapper now supports explicit execution mode selection (`legacy_eval` vs `instruction_stream`) and exposes runtime mode introspection.
3. Runner instruction-stream tuning now consumes stream/plan structure:
   - `GEM_INSTRUCTION_COUNT`
   - `GEM_STATE_READ_COUNT`
   - `GEM_CONTROL_STEP_COUNT`
   - `GEM_DEPENDENCY_EDGE_COUNT`
   - `GEM_READY_LAYER_COUNT`
   to derive chunk scale in stream mode.
4. GEM stream mode now enables kernel-side control-program interpretation during lowering (`RHDL_CPU8BIT_GEM_KERNEL_INTERPRETER=1`), emitting Metal control-op switch loop markers:
   - `constexpr ushort kGemControlOps[7]`
   - `switch (op)` over control micro-ops.
   - Kernel now binds instruction stream buffer (`[[buffer(3)]]`) and executes per-node `and_inv` shadow interpretation through `rhdl_gem_execute_shadow`.
5. Stream mode now includes deterministic ready-layer scheduling in `sim_runner_run_cycles` when dependency metadata is present (`GEM_SCHEDULER_MODE`), splitting chunk execution across `GEM_READY_LAYER_COUNT`.
   - Wrapper now embeds topology arrays:
     - `GEM_READY_LAYER_OFFSETS[]`
     - `GEM_READY_LAYER_PARTITIONS[]`
   - Wrapper now embeds packed instruction stream words:
   - `GEM_INSTRUCTION_WORD_COUNT`
   - `GEM_INSTRUCTION_WORDS[]`
   - Dynamic scheduler can be toggled with `RHDL_GEM_GPU_DYNAMIC_SCHEDULER=0/1`.
   - Layer budgets are weighted by per-layer partition counts.
6. Instruction-stream mode parity is green:
   - arithmetic parity spec: `1 example, 0 failures`
   - complex parity suite (Conway/Mandelbrot/arithmetic): `3 examples, 0 failures`
7. Instruction payload ABI now matches kernel parser layout:
   - `[instruction_count, flags, instruction_words..., watch_count, watch_words...]`
   - runner default empty payload now materializes as `{ 0u, 0u, 0u, 0u, 0u, 0u }` to avoid out-of-bounds watch/control/extern reads.
8. Lowering now emits deterministic output-watch metadata in stream artifacts:
   - `instruction_stream.output_watch_names`
   - `instruction_stream.output_watch_sources`
   for `mem_write_en`, `mem_read_en`, `halted`, `zero_flag_out`.
9. Output-watch override is now explicit/opt-in (`instruction_stream.output_watch_override=true`) instead of auto-enabled, preserving parity in default stream mode.
10. Fast-default scheduler behavior:
   - single-instance (`instances=1`): dynamic ready-layer scheduler defaults to disabled unless explicitly enabled.
   - multi-instance (`instances>1`): dynamic scheduler remains enabled by default.
11. Stream payload now carries serialized control program ops and kernel consumes them:
   - runner appends control tail: `[... watch_count, watch_words..., control_count, control_ops...]`
   - interpreter kernel now reads `control_count/control_ops` and falls back to static 7-op sequence only when absent.
   - this removes hard-wiring of control order and is a direct step toward fully stream-driven execution.
12. Instruction-stream benchmark snapshots (`50,000` cycles, latest runs):
   - default (`instances=1`):
     - Compiler run: `0.636s`
     - GemGPU run: `0.906s`
     - GemGPU vs compiler: `0.702x`
   - multi-instance (`instances=8`):
     - Compiler run: `0.695s`
     - GemGPU run: `0.960s`
     - GemGPU raw vs compiler: `0.724x`
     - GemGPU effective vs compiler: `5.793x`
13. Kernel now pre-decodes serialized control ops into thread-local storage once per dispatch:
   - removes per-cycle global-memory reads of control op words in the hot loop.
   - parity remains green on arithmetic + complex workloads.
14. Stream payload now includes extern reference table and kernel-side extern-table decode mode:
   - metadata emits `extern_ref_kinds` and `extern_ref_values`.
   - runner appends extern tail: `[... control_count, control_ops..., extern_count, extern_values...]`.
   - kernel decode now supports table-backed extern values when `gem_flags & 0x4` is set (fallback constant decode retained).
15. Stream payload now includes runtime extern-source descriptors and kernel descriptor decode mode:
   - metadata emits `extern_sources` entries (`const`, `state_bit`, `io_bit`, `unknown`) by analyzing synth `comb.extract` definitions against state/input layouts.
   - runner appends descriptor tail:
     `[... extern_count, extern_values..., extern_desc_count, extern_desc_words...]`.
   - kernel decode now supports descriptor-backed extern resolution when `gem_flags & 0x8` is set:
     - state bit extraction from `state_slots`
     - IO bit extraction from `RhdlArcGpuIo`.
16. Updated instruction-stream benchmark snapshots (`50,000` cycles, latest runs after control predecode + extern table/descriptor mode):
   - default (`instances=1`):
     - Compiler run: `0.685s`
     - GemGPU run: `0.904s`
     - GemGPU vs compiler: `0.758x`
   - multi-instance (`instances=8`):
     - Compiler run: `0.697s`
     - GemGPU run: `0.973s`
     - GemGPU raw vs compiler: `0.716x`
     - GemGPU effective vs compiler: `5.726x`
17. Build artifact cache-key now includes GEM compile-time toggles:
   - `execution_mode`, dynamic scheduler setting, and output-watch-override flag are encoded in `build_dir` suffix.
   - prevents cross-run contamination when switching env-driven stream modes in the same workspace.
18. Output-watch override mode is now cycle-correct when enabled:
   - shadow stream execution runs each cycle when override flag is set (instead of only cycle 0).
   - to preserve loop progress correctness, override currently applies to:
     - `mem_write_en`
     - `mem_read_en`
     - `zero_flag_out`
     and leaves `halted` authoritative from eval path.
19. Override-mode cost snapshot (`5,000` cycles):
   - Compiler: `0.076s`
   - GemGPU (`RHDL_GEM_GPU_OUTPUT_WATCH_OVERRIDE=1`): `0.341s`
   - ratio: `0.222x`
   - indicates current per-cycle shadow execution is correctness scaffolding, not a fast default path.
20. Shadow execution now precomputes extern values once per cycle into a thread-local cache (`kGemExternValueCap`) and decode reads from cache first:
   - reduces repeated descriptor/table decode overhead per source evaluation.
   - keeps parity green in both default and override modes.
21. Output-watch override now uses metadata-driven subset execution when available:
   - lowering emits `watch_eval_indices` closure for watch-driven node dependencies.
   - runner serializes watch-eval index tail:
     `[... extern_desc_count, extern_desc_words..., watch_eval_count, watch_eval_indices...]`.
   - kernel executes only this subset when override mode is active (fallback to full stream otherwise).
   - improved override benchmark from `7.557s` to `0.341s` at `5,000` cycles on latest snapshot.
22. Remaining phase-9 gap: kernel-side stream interpretation currently runs as shadow execution and does not yet drive architectural outputs/state updates directly (eval path still authoritative).

## Implementation Checklist
- [x] Phase 1 red tests added.
- [x] Phase 1 green implementation completed.
- [x] Phase 1 exit criteria met.
- [x] Phase 2 red tests added.
- [x] Phase 2 green implementation completed.
- [x] Phase 2 exit criteria met.
- [x] Phase 3 red tests added.
- [x] Phase 3 green implementation completed.
- [x] Phase 3 benchmarks recorded.
- [x] Phase 3 parity checks recorded.
- [x] Phase 4 red tests added.
- [x] Phase 4 green implementation completed.
- [x] Phase 4 exit criteria met.
- [x] Phase 5 red tests added.
- [x] Phase 5 green implementation completed.
- [x] Phase 5 exit criteria met.
- [x] Phase 6 red tests added.
- [x] Phase 6 green implementation completed.
- [x] Phase 6 exit criteria met.
- [x] Phase 7 red tests added.
- [x] Phase 7 green implementation completed.
- [x] Phase 7 exit criteria met.
- [ ] Phase 8 red tests added.
- [ ] Phase 8 green implementation completed.
- [ ] Phase 8 exit criteria met.
- [x] Phase 9 red tests added.
- [ ] Phase 9 green implementation completed.
- [ ] Phase 9 exit criteria met.
- [ ] Phase 10 red tests added.
- [ ] Phase 10 green implementation completed.
- [ ] Phase 10 exit criteria met.
- [ ] Phase 11 red tests added.
- [ ] Phase 11 green implementation completed.
- [ ] Phase 11 exit criteria met.
- [ ] Phase 12 red tests added.
- [ ] Phase 12 green implementation completed.
- [ ] Phase 12 exit criteria met.
- [ ] Phase 13 red tests added.
- [ ] Phase 13 green implementation completed.
- [ ] Phase 13 exit criteria met.
- [ ] Phase 14 red tests added.
- [ ] Phase 14 green implementation completed.
- [ ] Phase 14 exit criteria met.
- [ ] PRD status updated to Completed.
