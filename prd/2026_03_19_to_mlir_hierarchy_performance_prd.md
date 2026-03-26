# Title

`to_mlir_hierarchy` Fresh IR Generation Performance PRD

# Status

Completed - March 19, 2026

# Date

2026-03-19

## Context

`to_mlir_hierarchy` is now intentionally a fresh export path. It does not reuse imported MLIR text and instead rebuilds CIRCT IR from the raised in-memory RHDL component hierarchy before emitting MLIR.

That is the correct architecture for import/export consistency, but the original implementation was too slow on large raised designs. The baseline real profile on the first SPARC64 round-trip variant showed:

1. fresh `circt-verilog` import: `31.62s`
2. `import_circt_mlir`: `7.65s`
3. `raise_circt_components`: `51.43s`
4. profiled `to_mlir_hierarchy`: `303.94s`
5. `to_mlir_hierarchy` still timed out without producing output

The profile did not show final MLIR text emission as the bottleneck. It showed repeated fresh IR reconstruction inside export:

1. `RHDL::DSL::Behavior::BehaviorSlice#to_ir`
2. `RHDL::Codegen::CIRCT::IR::Slice#initialize`
3. `RHDL::Codegen::CIRCT::IR::Signal#initialize`
4. `RHDL::DSL::Behavior::BehaviorSignalRef#to_ir`
5. GC consuming about `26%` of samples

After the completed optimization phases in this PRD, the same real profiling gate now shows:

1. fresh `circt-verilog` import: `32.64s`
2. `import_circt_mlir`: `7.48s`
3. `raise_circt_components`: `52.32s`
4. `to_mlir_hierarchy`: `113.66s`
5. export completed successfully and produced `30,171,993` bytes of MLIR
6. GC dropped to `21.42%`

The hottest frames are no longer `BehaviorSlice#to_ir` and `BehaviorSignalRef#to_ir`. The bottleneck shifted to:

1. `Kernel#define_singleton_method`
2. `RHDL::Codegen::CIRCT::MLIR::ModuleEmitter#find_width`
3. `RHDL::DSL::Behavior::BehaviorContext#create_proxies`

So the performance problem is global fresh IR generation during export, not SPARC64-specific logic, and not imported-MLIR reuse.

## Goals

1. Optimize fresh CIRCT IR generation inside `to_mlir_hierarchy`.
2. Keep the export path fully regenerated from raised RHDL components.
3. Reduce redundant IR object creation for repeated expression subtrees.
4. Add codegen-level tests that lock in the optimization behavior.
5. Preserve existing export semantics and MLIR output correctness.

## Non-Goals

1. Re-enabling cached imported MLIR text reuse.
2. Short-circuiting export back to raw imported MLIR.
3. Making this optimization SPARC64-specific.
4. Rewriting the importer, raise pipeline, or runtime JSON pipeline in this PRD.
5. Introducing ARC lowering or JSON serialization into the test gates for this work.

## Scope

In scope:

1. `lib/rhdl/dsl/behavior.rb`
2. `lib/rhdl/synth/*.rb`
3. `lib/rhdl/synth/context.rb`
4. `lib/rhdl/dsl/codegen.rb`
5. `lib/rhdl/dsl/sequential.rb`
6. `lib/rhdl/codegen/circt/raise.rb`
7. `spec/rhdl/codegen/circt/*`

Out of scope:

1. `examples/sparc64/*` implementation changes except for using existing profiling specs as measurement gates
2. import caching behavior changes beyond keeping reuse disabled
3. backend compiler/runtime changes

## Risks And Mitigations

1. Memoization could accidentally retain stale IR across exports.
   - Mitigation: keep caches local to a single export pass and key by current expression object identity only.
2. Reusing IR nodes could accidentally change mutation assumptions.
   - Mitigation: only cache immutable expression nodes; do not cache mutable module/package wrappers.
3. Performance fixes could hide semantic regressions.
   - Mitigation: add codegen-level semantic round-trip tests and keep existing CIRCT codegen regressions green.
4. A microbenchmark-only optimization could miss the real workload.
   - Mitigation: use focused codegen specs for red/green and keep the real SPARC64 profiling spec as the final measurement gate.

## Acceptance Criteria

1. A dedicated codegen PRD exists for fresh `to_mlir_hierarchy` optimization.
2. New tests live under `spec/rhdl/codegen`.
3. Codegen specs prove repeated shared subexpressions do not rebuild duplicate IR trees during a single fresh export pass for behavior, synth, raise, and sequential export paths.
4. Existing CIRCT codegen tests for raise/import/export remain green in touched areas.
5. The real SPARC64 profiling spec shows a material reduction in time spent inside fresh `to_mlir_hierarchy`.
6. The implementation still performs a full raise -> fresh export path with no imported-MLIR text reuse.

## Phased Plan

### Phase 0: Baseline Export Gates

#### Objective

Create codegen-level failing coverage that exposes redundant expression-to-IR rebuilding during fresh export.

#### Red

1. Add a focused spec under `spec/rhdl/codegen/circt/` that constructs a component with shared slice/signal subexpressions and proves fresh export rebuilds duplicate CIRCT IR nodes today.
2. Add a codegen-level regression gate that exercises `raise_circt_components(...).components.fetch(top).to_mlir_hierarchy(...)`.
3. Capture the baseline failure signal in the PRD and spec output.

#### Green

1. Add the minimum instrumentation or observable hook needed for the new spec to detect duplicate lowering work.
2. Keep the behavior local to test/profiling support; do not optimize yet in this phase.

#### Exit Criteria

1. A codegen spec fails for redundant fresh export rebuilding before the optimization lands.
2. The failure signal is stable and does not depend on SPARC64 fixtures.

Status: Completed

Implemented:

1. Added focused codegen coverage in `spec/rhdl/codegen/circt/to_mlir_hierarchy_performance_spec.rb`.
2. Captured duplicate fresh-export lowering for repeated slice/signal subexpressions.

### Phase 1: Behavior Expression IR Memoization

#### Objective

Remove redundant fresh IR rebuilding in behavior expression lowering.

#### Red

1. Use the Phase 0 spec to show repeated `BehaviorSlice` / `BehaviorSignalRef` lowering creates duplicate IR nodes.
2. Add a second focused spec if needed for repeated behavior locals or repeated mux trees.

#### Green

1. Introduce per-export expression-to-IR memoization for behavior expressions in `lib/rhdl/dsl/behavior.rb`.
2. Keep the cache local to a single export pass.
3. Do not reuse imported MLIR or prebuilt module text.

#### Exit Criteria

1. The new behavior-level codegen specs are green.
2. Fresh export semantics are unchanged for existing round-trip tests.

Status: Completed

Implemented:

1. Added per-export memoization in `lib/rhdl/dsl/behavior.rb`.
2. Reduced repeated `BehaviorSlice` / `BehaviorSignalRef` lowering in focused codegen specs.

### Phase 2: Synth Expression IR Memoization

#### Objective

Extend the same fresh-export optimization to the synthesis expression tree used by raised behavior emission.

#### Red

1. Add a focused spec under `spec/rhdl/codegen/circt/` that proves repeated synth slice/signal expressions rebuild duplicate IR nodes when converting assignments/locals.
2. Record the failing duplicate-lowering signal.

#### Green

1. Add per-export memoization to `lib/rhdl/synth/*.rb` and `lib/rhdl/synth/context.rb`.
2. Ensure locals and assignments share the same export-pass cache where safe.
3. Keep all caching scoped to the current export call.

#### Exit Criteria

1. Synth-level codegen specs are green.
2. Existing `spec/rhdl/codegen/circt/raise_spec.rb` and adjacent CIRCT codegen tests remain green.

Status: Completed

Implemented:

1. Added and preserved synth-path caching in `lib/rhdl/synth/*.rb` and `lib/rhdl/synth/context.rb`.
2. Reduced cross-assignment redundant lowering in `lib/rhdl/codegen/circt/raise.rb`.
3. Added a sequential export regression case and fixed the missing per-pass cache in `lib/rhdl/dsl/sequential.rb`.

### Phase 3: Export Integration And Regression Gates

#### Objective

Integrate the memoized lowering path cleanly into `to_mlir_hierarchy` and validate it with broader codegen tests.

#### Red

1. Add or tighten integration coverage in `spec/rhdl/codegen/circt/` for fresh hierarchy export after raise.
2. Confirm the current path still triggers the slow lowering behavior before the integration change.

#### Green

1. Thread the per-export cache through the component export path in `lib/rhdl/dsl/codegen.rb`.
2. Keep export semantics unchanged and keep imported-MLIR reuse disabled.
3. Re-run touched CIRCT codegen specs.

#### Exit Criteria

1. All new codegen tests are green.
2. Touched CIRCT codegen regressions are green.

Status: Completed

Implemented:

1. Integrated the fresh-export caching path into `to_mlir_hierarchy` end-to-end with no imported-MLIR reuse.
2. Kept CIRCT codegen regression gates green.

### Phase 4: Real-Workload Validation

#### Objective

Verify that the global fresh-export optimization materially improves the real large-design case.

#### Red

1. Re-run the existing real SPARC64 profiling spec as the baseline.
2. Record the pre-optimization `to_mlir_hierarchy` timing and top frames.

#### Green

1. Re-run the same profiling spec after the codegen optimization lands.
2. Record:
   - fresh import time
   - import time
   - raise time
   - `to_mlir_hierarchy` time
   - whether export completes
   - top frames after optimization

#### Exit Criteria

1. The real profiling spec is green.
2. The PRD records before/after measurements.
3. The optimization shows a material reduction in fresh export cost.

Status: Completed

Measured result:

1. Baseline: `to_mlir_hierarchy` timed out after about `303.94s` without producing output.
2. Final: `to_mlir_hierarchy` completed in `113.66s` and wrote `01.hw_flatten_modules_canonicalize_cse.exported.mlir`.
3. Baseline hottest frames: `BehaviorSlice#to_ir`, `BehaviorSignalRef#to_ir`, `IR::Slice#initialize`, `IR::Signal#initialize`.
4. Final hottest frames: `Kernel#define_singleton_method`, `ModuleEmitter#find_width`, `BehaviorContext#create_proxies`.
5. Baseline GC: about `26%`.
6. Final GC: `21.42%`.

## Test Plan

Primary tests for this PRD must live under `spec/rhdl/codegen`.

Required new or updated gates:

1. focused fresh-export memoization specs in `spec/rhdl/codegen/circt/`
2. `bundle exec rspec spec/rhdl/codegen/circt/raise_spec.rb --order defined`
3. `bundle exec rspec spec/rhdl/codegen/circt/api_spec.rb --order defined`
4. any new dedicated `to_mlir_hierarchy` performance or duplicate-lowering specs under `spec/rhdl/codegen/circt/`

Real-workload measurement gate:

1. `bundle exec rspec spec/examples/sparc64/runners/ir_runner_mlir_profile_spec.rb --tag slow --example 'captures stackprof samples for the first circt-opt variant before the downstream export' --format documentation`

## Implementation Checklist

- [x] Phase 0 complete
- [x] Phase 1 complete
- [x] Phase 2 complete
- [x] Phase 3 complete
- [x] Phase 4 complete
- [x] Codegen regression checks complete
- [x] PRD status updated with measured results

## Command Log

1. `SPARC64_MLIR_PROFILE_SAMPLE_SECONDS=300 bundle exec rspec spec/examples/sparc64/runners/ir_runner_mlir_profile_spec.rb --tag slow --example 'captures stackprof samples for the first circt-opt variant before the downstream export' --format documentation`
   - result: `pass`
   - notes: profiled the real fresh export path for `--hw-flatten-modules --canonicalize --cse`; `to_mlir_hierarchy` timed out after about `303.94s` with hottest frames in `BehaviorSlice#to_ir` and `BehaviorSignalRef#to_ir`.

2. `rg -n "to_mlir_hierarchy|to_ir\\(" spec/rhdl/codegen -g'*.rb'`
   - result: `pass`
   - notes: identified current codegen spec coverage that should host the new export-performance tests.

3. `bundle exec rspec spec/rhdl/codegen/circt/to_mlir_hierarchy_performance_spec.rb --example 'uses the fresh export-pass cache during sequential to_mlir_hierarchy export' --format documentation`
   - result: `fail` then `pass`
   - notes: captured the missing per-pass sequential export cache (`expected: 1`, `got: 2` slices), then verified the fix in `SequentialContext#to_sequential_ir`.

4. `bundle exec rspec spec/rhdl/codegen/circt/to_mlir_hierarchy_performance_spec.rb --order defined`
   - result: `pass`
   - notes: focused fresh-export codegen performance specs all green (`7 examples, 0 failures`).

5. `bundle exec rspec spec/rhdl/codegen/circt/raise_spec.rb spec/rhdl/codegen/circt/api_spec.rb spec/rhdl/codegen/circt/circt_core_spec.rb --order defined`
   - result: `pass`
   - notes: touched CIRCT codegen regression gates green (`67 examples, 0 failures`).

6. `SPARC64_MLIR_PROFILE_SAMPLE_SECONDS=300 bundle exec rspec spec/examples/sparc64/runners/ir_runner_mlir_profile_spec.rb --tag slow --example 'captures stackprof samples for the first circt-opt variant before the downstream export' --format documentation`
   - result: `pass`
   - notes: `to_mlir_hierarchy` completed in `113.66s`; prior baseline timed out after about `303.94s`.
