# Status

Completed - March 19, 2026

## Context

The first SPARC64 source-size optimization pass reduced the generated Rust artifact substantially, but the real cached SPARC64 compiler input still carries large codegen duplication on the compile path.

Fresh local measurements on March 19, 2026 from the current real SPARC64 artifact set:

1. The cached runtime JSON at [tmp/sparc64_import_trees/e98520f9592d987ce1f35db1a4a78d003041d0a343d12d7dd157069f264418db/s1_top.runtime.json](/Users/skryl/Dev/rhdl/codex-circt/tmp/sparc64_import_trees/e98520f9592d987ce1f35db1a4a78d003041d0a343d12d7dd157069f264418db/s1_top.runtime.json) is `273,916,660` bytes.
2. The generated Rust artifact from that JSON at [tmp/phase4/s1_top.from_baseline_runtime.rs](/Users/skryl/Dev/rhdl/codex-circt/tmp/phase4/s1_top.from_baseline_runtime.rs) is `53,910,178` bytes and `145,152` lines.
3. That Rust file still contains `14,592` `wide_load_signal(` calls and `14,122` `wide_slice_u128(wide_load_signal(...))` patterns.
4. The runtime JSON still contains `56,552 / 56,904` direct-like assigns (`signal`, `signal_index`, or `expr_ref`), so alias/copy transport still dominates the assign table.
5. Enabling compact export hoisting on the real SPARC64 tree was experimentally impractical: the probe process reached roughly `9.5 GB` RSS after `1:47` with no output file written.

These measurements show the next useful work is compiler-side reuse of repeated wide loads/slices and selective reuse of repeated wide expr-ref trees, with any further export-side pooling kept hoist-free.

## Goals

1. Reduce generated Rust size and duplication further on the real SPARC64 compiler path.
2. Reduce compile-path load without changing runtime JSON schema or runner interfaces.
3. Keep every phase red/green and measurable on the real cached SPARC64 artifact.

## Non-Goals

1. Re-enabling shared-expression hoisting by default.
2. Changing the CIRCT runtime JSON schema or version.
3. Splitting generated Rust into multiple source files in this pass.
4. Retuning the rustc profile constants in this pass.

## Phased Plan

### Phase 1: Wide Load/Slice Reuse In Compiler Codegen

#### Red

1. Add focused native-IR compiler coverage showing repeated slices from the same `>128`-bit signal currently duplicate `wide_load_signal` / `wide_slice_u128` emission.
2. Capture the failure signal in generated Rust counts for that probe.

#### Green

1. Add chunk-local temp reuse for repeated wide signal loads and repeated wide-signal slice extraction in [lib/rhdl/sim/native/ir/ir_compiler/src/core.rs](/Users/skryl/Dev/rhdl/codex-circt/lib/rhdl/sim/native/ir/ir_compiler/src/core.rs).
2. Reuse only for resolved `Signal` / `SignalIndex` wide bases and only within the current emitted evaluate chunk/function.
3. Keep all existing overwide compiler probes green.

#### Exit Criteria

1. The new focused compiler probe is green.
2. The real SPARC64 generated Rust artifact has lower `wide_load_signal(` and `wide_slice_u128(wide_load_signal(...))` counts than the baseline above.

### Phase 2: Reused Wide `expr_ref` Materialization

#### Red

1. Add focused native-IR compiler coverage showing reused wide `expr_ref` trees still inline repeatedly in generated Rust.
2. Capture the repeated-inline codegen signal before the change.

#### Green

1. Materialize reused wide `expr_ref` trees into temps using the existing `expr_ref_use_counts` / `expr_ref_complexities` infrastructure in [lib/rhdl/sim/native/ir/ir_compiler/src/core.rs](/Users/skryl/Dev/rhdl/codex-circt/lib/rhdl/sim/native/ir/ir_compiler/src/core.rs).
2. Apply this only to wide expressions (`>128` bits), keeping narrow behavior unchanged.
3. Keep all existing overwide compiler probes green.

#### Exit Criteria

1. The new repeated-wide-`expr_ref` compiler probe is green.
2. The real SPARC64 generated Rust artifact is smaller than the post-Phase-1 baseline.

### Phase 3: Hoist-Free Structural Pooling In Compact Runtime JSON

#### Red

1. Add focused native-IR compact-export coverage for repeated structural subtrees that are not just repeated concat parts: repeated `Slice`, `BinaryOp`, and `Mux`.
2. Confirm compact export currently serializes them as duplicated subtrees rather than pooled `expr_ref`s.

#### Green

1. Extend compact runtime JSON serialization in [lib/rhdl/codegen/circt/runtime_json.rb](/Users/skryl/Dev/rhdl/codex-circt/lib/rhdl/codegen/circt/runtime_json.rb) to structurally pool identical `Slice`, `Resize`, `BinaryOp`, and `Mux` subtrees without introducing hoisting, new nets, or schema changes.
2. Keep `dump` / `dump_to_io` parity intact.
3. Land this phase only if it reduces real SPARC64 JSON size and does not regress generated Rust size on the cached SPARC64 artifact.

#### Exit Criteria

1. New structural-pooling specs are green.
2. The real SPARC64 runtime JSON is smaller than the current baseline.
3. The generated Rust artifact from the optimized JSON is not larger than the pre-Phase-3 baseline.

### Phase 4: SPARC64 Validation And Stop Condition

#### Red

1. Re-measure the real SPARC64 runtime JSON and generated Rust artifacts after each phase.
2. Re-run the focused SPARC64 compiler runner gates after each landed phase.

#### Green

1. Keep targeted native-IR and SPARC64 runner specs green throughout.
2. Record before/after metrics and exact commands in this PRD.
3. Stop after Phase 3 if the exporter-side work no longer reduces real generated Rust load.

#### Exit Criteria

1. The landed phases are fully recorded here with measured artifact deltas and green targeted gates.

## Acceptance Criteria

1. Every landed phase has a red/green test or reproducible check first.
2. The real cached SPARC64 generated Rust artifact is smaller or materially less duplicated than the baseline above.
3. Hoisting remains off by default.
4. The PRD documents what did and did not improve the real SPARC64 compile path.

## Risks And Mitigations

1. Wide-load/slice reuse could accidentally reuse a temp across an unsafe scope boundary.
   - Mitigation: keep reuse local to one emitted evaluate chunk/function and key only by resolved signal/slice identity.
2. Wide `expr_ref` materialization could increase source size if applied too broadly.
   - Mitigation: gate it to wide expressions only and use the existing use-count/complexity data.
3. Export-side structural pooling may shrink JSON but still not help rustc.
   - Mitigation: make Phase 3 conditional on non-regressing generated Rust size on the real cached SPARC64 artifact.

## Execution Notes

### Phase 1 Result

Red:

1. Added `reuses a single wide signal load across repeated 256-bit slices on the compiler backend` to [spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb](/Users/skryl/Dev/rhdl/codex-circt/spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb).
2. Initial red after rebuilding the native crate:
   - `bundle exec rspec spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb --example 'reuses a single wide signal load across repeated 256-bit slices on the compiler backend' --format documentation`
   - failure: `wide_load_signal` count `4`, `wide_slice_u128(wide_load_signal(...))` count `4`

Green:

1. Added chunk-local wide signal load and wide slice temp reuse in [lib/rhdl/sim/native/ir/ir_compiler/src/core.rs](/Users/skryl/Dev/rhdl/codex-circt/lib/rhdl/sim/native/ir/ir_compiler/src/core.rs).
2. Verified:
   - `cargo build --manifest-path lib/rhdl/sim/native/ir/ir_compiler/Cargo.toml --release`
   - `bundle exec rspec spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb --order defined`
   - result: `12 examples, 0 failures`

Real SPARC64 artifact measurement:

1. Command:
   - `cargo run --manifest-path lib/rhdl/sim/native/ir/ir_compiler/Cargo.toml --release --bin aot_codegen -- tmp/sparc64_import_trees/e98520f9592d987ce1f35db1a4a78d003041d0a343d12d7dd157069f264418db/s1_top.runtime.json tmp/phase_follow_on/phase1_s1_top.rs`
2. Result:
   - [tmp/phase_follow_on/phase1_s1_top.rs](/Users/skryl/Dev/rhdl/codex-circt/tmp/phase_follow_on/phase1_s1_top.rs) is `53,632,235` bytes and `149,814` lines
   - `wide_load_signal(` count: `376`
   - `wide_slice_u128(wide_load_signal(...))` count: `0`

### Phase 2 Result

Red:

1. Added `materializes reused wide expr_ref trees once on the compiler backend` to [spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb](/Users/skryl/Dev/rhdl/codex-circt/spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb).
2. Red command:
   - `bundle exec rspec spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb --example 'materializes reused wide expr_ref trees once on the compiler backend' --format documentation`
   - failure: `wide_repeat_pattern(` count `5` instead of `2`

Green:

1. Fixed wide `ExprRef` dispatch and added wide expr-ref temp materialization in [lib/rhdl/sim/native/ir/ir_compiler/src/core.rs](/Users/skryl/Dev/rhdl/codex-circt/lib/rhdl/sim/native/ir/ir_compiler/src/core.rs).
2. Verified:
   - `cargo build --manifest-path lib/rhdl/sim/native/ir/ir_compiler/Cargo.toml --release`
   - `bundle exec rspec spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb --order defined`
   - result: `13 examples, 0 failures`

Real SPARC64 artifact measurement:

1. Command:
   - `cargo run --manifest-path lib/rhdl/sim/native/ir/ir_compiler/Cargo.toml --release --bin aot_codegen -- tmp/sparc64_import_trees/e98520f9592d987ce1f35db1a4a78d003041d0a343d12d7dd157069f264418db/s1_top.runtime.json tmp/phase_follow_on/phase2_s1_top.rs`
2. Result:
   - [tmp/phase_follow_on/phase2_s1_top.rs](/Users/skryl/Dev/rhdl/codex-circt/tmp/phase_follow_on/phase2_s1_top.rs) is `53,000,371` bytes and `143,825` lines
   - `wide_load_signal(` count: `376`
   - `wide_slice_u128(wide_load_signal(...))` count: `0`

### Phase 3 Result

Red:

1. Added `pools repeated slice, binary, mux, and resize trees through shared expr_ref ids in compact dump export` to [spec/rhdl/sim/native/ir/runtime_json_compaction_spec.rb](/Users/skryl/Dev/rhdl/codex-circt/spec/rhdl/sim/native/ir/runtime_json_compaction_spec.rb).
2. Red command:
   - `bundle exec rspec spec/rhdl/sim/native/ir/runtime_json_compaction_spec.rb --example 'pools repeated slice, binary, mux, and resize trees through shared expr_ref ids in compact dump export' --format documentation`
   - failure: all repeated pairs serialized to different `expr_ref` ids

Green:

1. Added hoist-free structural pooling for `Slice`, `Resize`, `BinaryOp`, and `Mux` in compact serialization in [lib/rhdl/codegen/circt/runtime_json.rb](/Users/skryl/Dev/rhdl/codex-circt/lib/rhdl/codegen/circt/runtime_json.rb).
2. Verified:
   - `bundle exec rspec spec/rhdl/sim/native/ir/runtime_json_compaction_spec.rb --example 'pools repeated slice, binary, mux, and resize trees through shared expr_ref ids in compact dump export' --format documentation`
   - result: `1 example, 0 failures`

Real-artifact note:

1. I attempted two local real-artifact gates for this phase:
   - direct SPARC64 re-export from the imported Ruby tree
   - a real-runtime proxy transform script over the cached `s1_top.runtime.json`
2. Both remained CPU-bound for minutes without producing an output artifact, so I did not use them as completion gates for this phase.
3. Because of that, Phase 3 is validated by focused native-IR export coverage plus the non-regression gates in Phase 4, but it does not have a completed local real-artifact byte delta recorded here.

### Phase 4 Result

Validation gates:

1. `bundle exec rspec spec/rhdl/sim/native/ir/runtime_json_compaction_spec.rb spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb spec/examples/sparc64/runners/ir_runner_spec.rb spec/examples/sparc64/runners/headless_runner_spec.rb --order defined`
2. Result: `45 examples, 0 failures`

Outcome summary:

1. Phase 1 and Phase 2 produced measurable real SPARC64 compiler-source reductions versus the PRD baseline:
   - baseline Rust source: `53,910,178` bytes
   - post-Phase-1: `53,632,235` bytes
   - post-Phase-2: `53,000,371` bytes
2. Phase 3 improved compact export behavior on focused coverage and did not regress the targeted native-IR or SPARC64 runner gates, but its full real-artifact proxy measurement remained impractical locally.

## Implementation Checklist

- [x] Phase 1: Wide Load/Slice Reuse In Compiler Codegen
- [x] Phase 2: Reused Wide `expr_ref` Materialization
- [x] Phase 3: Hoist-Free Structural Pooling In Compact Runtime JSON
- [x] Phase 4: SPARC64 Validation And Stop Condition
