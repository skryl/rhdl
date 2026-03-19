# Status

In Progress - March 19, 2026

## Context

The original SPARC64 experiment path tried:

1. `RHDL -> to_mlir_hierarchy`
2. `circt-opt` variants
3. `import_circt_mlir`
4. `RHDL::Codegen::CIRCT::Flatten.to_flat_module`
5. runtime JSON export

Actual command runs showed that this is too expensive for a practical experiment gate. The measured breakdown on the full SPARC64 top was:

1. `to_mlir_hierarchy(top_name:, core_mlir_path:)`: effectively immediate on the cached-core path.
2. `import_circt_mlir(... strict: false)`: about `22s`.
3. `RHDL::Codegen::CIRCT::Flatten.to_flat_module(...)`: about `1s`.
4. `RuntimeJSON.normalized_runtime_modules_from_input(... compact_exprs: true)`: about `22.3s`.
5. Compact JSON `assigns` writing alone: about `9.0s` before later sections completed.

That means the slow part was not hierarchy MLIR emission; it was the downstream runtime JSON path. The experiment was then simplified to `to_mlir_hierarchy -> circt-opt`, but the user revised the requirement again: the matrix should keep the common RHDL round-trip boundary and run:

1. imported core `.mlir`
2. `RHDL::Codegen.import_circt_mlir`
3. `RHDL::Codegen.raise_circt_components`
4. `to_mlir_hierarchy`
5. `circt-opt` variants

The point of the revision is to exercise the same import/export path whether the starting point is an imported `.mlir` artifact or an in-memory RHDL-generated design.

The final user revision for this PRD was stricter still:

1. do not use a cached import tree
2. build a fresh staged import from the latest staged Verilog
3. use the raw `circt-verilog` output `.core.mlir`
4. turn off cached imported MLIR text reuse during `to_mlir_hierarchy`

## Goals

1. Add a dedicated slow SPARC64 spec that round-trips through CIRCT import and raised RHDL components before re-emitting hierarchy MLIR.
2. Run a small matrix of `circt-opt` variants, including a flatten variant.
3. Measure optimized MLIR byte size per variant.
4. Record the cost of:
   - fresh staged import / raw core MLIR generation
   - `import_circt_mlir`
   - `raise_circt_components`
   - `to_mlir_hierarchy`
5. Add a real profiler to the SPARC64 `to_mlir_hierarchy` path and capture a timeboxed profile from the actual test flow.

## Non-Goals

1. Running a full MLIR -> JSON export matrix.
2. Changing the production SPARC64 IR compiler backend path.
3. Removing RHDL flatten from the runtime/compiler backend.
4. Solving the full compact runtime JSON serialization cost in this PRD.

## Phased Plan

### Phase 1: Red Matrix Spec

#### Objective

Revise the dedicated SPARC64 MLIR-size experiment spec so it requires the `.mlir -> import -> raise -> to_mlir_hierarchy` round-trip and fail it before the helper is updated.

#### Red

1. Tighten the slow SPARC64 matrix spec to require import/raise timing and round-trip metadata.
2. Run it against the old helper and capture the missing-field failure.

#### Green

1. Add the helper that:
   - loads the cached SPARC64 core `.mlir`
   - imports that MLIR through `RHDL::Codegen.import_circt_mlir`
   - raises the imported modules through `RHDL::Codegen.raise_circt_components`
   - emits `to_mlir_hierarchy` from the raised top component
   - runs `circt-opt` variants
   - measures optimized MLIR file size
   - writes a report under `tmp/`

#### Exit Criteria

1. The new spec is green.
2. The report contains import/raise/to_mlir timings plus the requested `circt-opt` variants and a smallest successful result.

### Phase 2: Validation And Documentation

#### Objective

Run the revised matrix spec and record the measured result.

#### Red

1. Capture the missing-field failure from Phase 1.

#### Green

1. Re-run the new matrix spec to completion.
2. Record the measured best variant plus import/raise/to_mlir timings here.

#### Exit Criteria

1. The matrix spec is green.
2. The PRD reflects the measured outcome.

### Phase 3: Profile The Slow Export Path

#### Objective

Add a profiler dependency and use it on the real SPARC64 raw-core import -> raise -> `to_mlir_hierarchy` path so the export bottleneck is observable from an actual test.

#### Red

1. Add a dedicated slow profiling spec that expects profiler artifacts and top-frame output.
2. Run it before the profiler integration exists and capture the failure.

#### Green

1. Add a profiler dependency to the development bundle.
2. Add a profiling helper that:
   - reuses the fresh raw-core import path
   - profiles `to_mlir_hierarchy` with a timeboxed sampler
   - writes raw and text profile artifacts under `tmp/`
   - records the hottest frames in a report
3. Run the dedicated profiling spec and record the result here.

#### Exit Criteria

1. The profiling spec is green.
2. The report contains profiler artifacts and a ranked top-frame summary.

## Acceptance Criteria

1. The repo contains a dedicated slow SPARC64 hierarchy-MLIR optimization matrix spec.
2. The matrix includes at least:
   - passthrough
   - `--canonicalize --cse`
   - `--hw-flatten-modules`
   - `--hw-flatten-modules --canonicalize --cse`
3. The report records:
   - `import_circt_mlir` time
   - `raise_circt_components` time
   - `to_mlir_hierarchy` time
   - optimized MLIR byte size
4. No MLIR -> JSON pass is required for this experiment.
5. The repo can produce a profiler report for the real SPARC64 `to_mlir_hierarchy` path from a slow spec.

## Risks And Mitigations

1. The extra import/raise round-trip may make the matrix noticeably slower.
   - Mitigation: measure each stage independently so the bottleneck is obvious.
2. Some `circt-opt` variants may fail.
   - Mitigation: record failures per variant in the report.

## Results

The completed matrix wrote its report to:

- `tmp/sparc64_ir_compiler_mlir_opt_matrix/report.json`

Fresh-input source:

- fresh import dir: `tmp/sparc64_ir_compiler_mlir_opt_matrix/artifacts/fresh_import`
- raw source MLIR: `tmp/sparc64_ir_compiler_mlir_opt_matrix/artifacts/fresh_import/.mixed_import/s1_top.core.mlir`
- `reuse_cached_mlir_text`: `false`

Measured stage timings:

1. fresh importer run: `38.2971120000002s`
2. `import_circt_mlir`: `20.890310999995563s`
3. `raise_circt_components`: `27.960735000000568s`
4. `to_mlir_hierarchy`: `2.7789390000107232s`

Measured input size:

- regenerated hierarchy MLIR bytes: `21676047`

Measured successful `circt-opt` variants:

1. `circt_opt_passthrough`
   - output bytes: `15632977`
   - bytes saved: `6043070`
   - size ratio: `0.7212097759337761`
2. `canonicalize_cse`
   - output bytes: `2988361`
   - bytes saved: `18687686`
   - size ratio: `0.13786466692935295`
3. `hw_flatten_modules`
   - output bytes: `15632977`
   - bytes saved: `6043070`
   - size ratio: `0.7212097759337761`
4. `hw_flatten_modules_canonicalize_cse`
   - output bytes: `2988361`
   - bytes saved: `18687686`
   - size ratio: `0.13786466692935295`

Best successful variant:

- `canonicalize_cse`
- command: `circt-opt --canonicalize --cse <input.mlir> -o <output.mlir>`

Key findings:

1. Fresh input plus import/raise round-trip only became valid for `circt-opt` once cached imported MLIR text reuse was disabled.
2. With cache reuse disabled, `to_mlir_hierarchy` is no longer effectively free, but it is still materially cheaper than the import and raise steps.
3. `--canonicalize --cse` was again the best size reduction path.
4. On this regenerated input, `--hw-flatten-modules` made no size difference over passthrough, and `--hw-flatten-modules --canonicalize --cse` matched `--canonicalize --cse`.

## Phase 3 Profiling Results

The repo now includes a real stackprof-based profiling path for the SPARC64 raw-core import -> raise -> `to_mlir_hierarchy` flow:

- spec: `spec/examples/sparc64/runners/ir_runner_mlir_profile_spec.rb`
- report: `tmp/sparc64_ir_compiler_mlir_profile/report.json`
- raw profile: `tmp/sparc64_ir_compiler_mlir_profile/to_mlir_hierarchy.stackprof.dump`
- text profile: `tmp/sparc64_ir_compiler_mlir_profile/to_mlir_hierarchy.stackprof.txt`

Measured profiling run:

1. fresh raw-core import: `32.221340999996755s`
2. `import_circt_mlir`: `21.05708699999377s`
3. `raise_circt_components`: `27.65957200000412s`
4. profiled `to_mlir_hierarchy` sample window: `61.18621600000188s`
5. export completion: `timed_out` after the 60-second sample window, with no final MLIR emitted

Top sampled frames from the real profile:

1. `RHDL::DSL::Behavior::BehaviorSlice#to_ir` — `14207` samples
2. `RHDL::Codegen::CIRCT::IR::Slice#initialize` — `6809` samples
3. `RHDL::Codegen::CIRCT::IR::Signal#initialize` — `6578` samples
4. `RHDL::DSL::Behavior::BehaviorSignalRef#to_ir` — `6178` samples
5. `RHDL::Codegen::CIRCT::IR::Expr#initialize` — `2930` samples

Profiler-level findings:

1. The slowdown is dominated by behavior-to-IR expression lowering, especially repeated slice lowering and signal reference lowering.
2. A large amount of time is spent allocating IR nodes (`Slice`, `Signal`, `Expr`) rather than in final MLIR string emission.
3. GC is a material part of the cost: `16898 / 60010` samples (`28.16%`) were GC (`marking` + `sweeping`).
4. This means the first optimization target should be reducing repeated slice/signal IR object creation, not `circt-opt` and not MLIR text concatenation.

## Variant-First Profiling Results

The repo now also has a real profile for the exact stalled path:

1. fresh raw `circt-verilog` core MLIR
2. `circt-opt --hw-flatten-modules --canonicalize --cse`
3. `import_circt_mlir`
4. `raise_circt_components`
5. profiled `to_mlir_hierarchy`

Artifacts:

- report: `tmp/sparc64_ir_compiler_mlir_profile_variant/report.json`
- optimized input: `tmp/sparc64_ir_compiler_mlir_profile_variant/artifacts/01.hw_flatten_modules_canonicalize_cse.mlir`
- raw stackprof: `tmp/sparc64_ir_compiler_mlir_profile_variant/hw_flatten_modules_canonicalize_cse.to_mlir_hierarchy.stackprof.dump`
- text stackprof: `tmp/sparc64_ir_compiler_mlir_profile_variant/hw_flatten_modules_canonicalize_cse.to_mlir_hierarchy.stackprof.txt`

Measured run:

1. `circt-verilog` command confirmed `--ir-hw`
2. fresh raw-core import: `31.955343000008725s`
3. optimized MLIR size after `--hw-flatten-modules --canonicalize --cse`: `4774335` bytes
4. `import_circt_mlir` on the optimized MLIR: `7.597966000001179s`
5. `raise_circt_components` on the optimized MLIR: `51.742394000000786s`
6. profiled `to_mlir_hierarchy` window: `61.870713000011165s`
7. export completion: `timed_out` after the 60-second profile window, with no final MLIR emitted

Top sampled frames:

1. `RHDL::DSL::Behavior::BehaviorSlice#to_ir` — `15501` samples
2. `RHDL::Codegen::CIRCT::IR::Slice#initialize` — `7326` samples
3. `RHDL::Codegen::CIRCT::IR::Signal#initialize` — `7012` samples
4. `RHDL::DSL::Behavior::BehaviorSignalRef#to_ir` — `6664` samples
5. `RHDL::Codegen::CIRCT::IR::Expr#initialize` — `3034` samples

Key comparison to the raw-core profile:

1. The hot path is the same: slice lowering plus IR object allocation.
2. GC is still large but somewhat lower than the raw-core profile: `13746 / 60092` samples (`22.87%`).
3. The post-`circt-opt` path reduces import time materially (`~7.6s` vs `~21.1s`) but increases raise time materially (`~51.7s` vs `~27.7s`).
4. The thing that still hangs is not final MLIR printing; it is the same behavior-to-IR rebuilding work inside `to_mlir_hierarchy`.

## Implementation Checklist

- [x] Phase 1 complete
- [x] Phase 2 complete
- [x] Phase 3 complete

## Command Log

1. `bundle exec rspec spec/examples/sparc64/runners/ir_runner_mlir_opt_matrix_spec.rb --format documentation`
   - result: `fail`
   - notes: initial red failed on missing `spec/support/sparc64/mlir_opt_matrix_support.rb`.
2. `bundle exec ruby -Ilib - <<'RUBY' ... to_mlir_hierarchy(top_name:, core_mlir_path:) ... import_circt_mlir ... Flatten.to_flat_module ... RuntimeJSON.normalized_runtime_modules_from_input ... RUBY`
   - result: `pass`
   - notes: showed the old MLIR->JSON experiment cost was dominated by runtime JSON normalization and compact write, not by `to_mlir_hierarchy`.
3. `bundle exec rspec spec/examples/sparc64/runners/ir_runner_mlir_opt_matrix_spec.rb --tag slow --format documentation`
   - result: `fail`
   - notes: revised red failed on missing `import_circt_mlir_seconds` / round-trip metadata.
4. `bundle exec rspec spec/examples/sparc64/runners/ir_runner_mlir_opt_matrix_spec.rb --tag slow --format documentation`
   - result: `fail`
   - notes: round-trip through cached core `.mlir` produced invalid regenerated MLIR with zero-operand `hw.instance @dff_s() -> ()` in `bw_r_irf`.
5. `bundle exec rspec spec/examples/sparc64/runners/ir_runner_mlir_opt_matrix_spec.rb --tag slow --format documentation`
   - result: `fail`
   - notes: switching to a fresh staged import core MLIR did not change that invalid regenerated shape while cached imported MLIR text reuse was still enabled.
6. `bundle exec rspec spec/rhdl/import/import_paths_spec.rb --example 'can disable cached imported MLIR text reuse during hierarchy MLIR regeneration' --order defined`
   - result: `pass`
   - notes: focused unit coverage for the new `reuse_cached_mlir_text: false` option.
7. `bundle exec rspec spec/examples/sparc64/runners/ir_runner_spec.rb --order defined`
   - result: `pass`
   - notes: `16 examples, 0 failures`.
8. `bundle exec rspec spec/examples/sparc64/runners/ir_runner_mlir_opt_matrix_spec.rb --tag slow --format documentation`
   - result: `pass`
   - notes: final green on the fresh-input round-trip path with cached imported MLIR text reuse disabled; `1 example, 0 failures` in about `1m36s`.
9. `bundle exec ruby -e 'require "stackprof"'`
   - result: `fail`
   - notes: red signal before adding the profiler dependency: `cannot load such file -- stackprof`.
10. `bundle install`
   - result: `pass`
   - notes: installed `stackprof 0.2.28`.
11. `bundle exec rspec spec/examples/sparc64/runners/ir_runner_mlir_profile_spec.rb --tag slow --format documentation`
   - result: `fail`
   - notes: first green attempt wrote a dump but used `StackProf.stop` instead of `StackProf.results`, so `top_frames` was empty.
12. `bundle exec rspec spec/examples/sparc64/runners/ir_runner_mlir_profile_spec.rb --tag slow --format documentation`
   - result: `pass`
   - notes: final green; `1 example, 0 failures` in about `2m33s`, with stackprof dump/text plus ranked top frames recorded in the report.
13. `bundle exec rspec spec/examples/sparc64/runners/ir_runner_mlir_profile_spec.rb --tag slow --example 'captures stackprof samples for the first circt-opt variant before the downstream export' --format documentation`
   - result: `pass`
   - notes: profiled the exact `--hw-flatten-modules --canonicalize --cse -> import -> raise -> to_mlir_hierarchy` path; `1 example, 0 failures` in about `2m47s`.
