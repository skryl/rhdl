# Status

Completed - March 19, 2026

## Context

The SPARC64 IR compiler path is no longer blocked on silent runtime-only fallback, but it is still blocked in practice by the size and shape of the emitted compiler input.

Fresh measurements on March 19, 2026 from the current local SPARC64 artifacts:

1. The importer-produced runtime JSON at [tmp/sparc64_import_trees/e98520f9592d987ce1f35db1a4a78d003041d0a343d12d7dd157069f264418db/s1_top.runtime.json](/Users/skryl/Dev/rhdl/codex-circt/tmp/sparc64_import_trees/e98520f9592d987ce1f35db1a4a78d003041d0a343d12d7dd157069f264418db/s1_top.runtime.json) is `273,916,660` bytes.
2. That payload contains `56,898` nets, `6,581` regs, `1,786,483` pooled exprs, and `56,904` assigns.
3. `56,552 / 56,904` assigns are direct-like forwards (`signal`, `signal_index`, or `expr_ref`), which means alias transport dominates the assign table.
4. Expr kind concentration is heavily skewed toward repeated structural forms:
   - `1,304,082` binary
   - `321,784` concat
   - `94,710` slice
   - `64,726` mux
5. The current generated Rust compiler unit at [rhdl_ir_b68101d1d02924c7.90415_1773934661788810000.rs](/var/folders/fx/2jqq5cks33g297zlybsqw6c40000gn/T/rhdl_cache/rhdl_ir_b68101d1d02924c7.90415_1773934661788810000.rs) is `87,018,125` bytes and `544,408` lines.
6. That Rust file still contains `36,237` direct copy stores and `5,452` repeated `wide_slice_u128(wide_load_signal(...))` patterns.

These measurements show two distinct cost centers:

1. Export-side duplication already present in compact runtime JSON.
2. Compiler-side codegen duplication when lowering repeated structural patterns from that payload.

## Goals

1. Reduce generated Rust source size and duplication on the SPARC64 compiler path without changing backend semantics.
2. Reduce obvious export-side duplication in compact runtime JSON before the compiler sees it.
3. Keep the work phaseable so each step has a narrow red/green gate and measurable artifact-level impact.

## Non-Goals

1. Redesigning the CIRCT runtime JSON schema.
2. Reworking SPARC64 import topology or parity harnesses in this pass.
3. Changing interpreter or JIT runtime semantics.
4. Claiming full SPARC64 compiler parity completion in this PRD.

## Phased Plan

### Phase 1: Compiler Repeated-Concat Compaction

#### Red

1. Add focused compiler coverage showing that repeated wide concat patterns currently inline long shift/or ladders instead of using a compact helper.
2. Capture the current generated-code failure signal on a repeated 256-bit concat case.

#### Green

1. Add a dedicated wide repeat helper in the generated Rust support code.
2. Lower repeated wide concat patterns through that helper instead of emitting repeated shift/or chains inline.
3. Keep functional behavior identical on the existing overwide compiler probes.

#### Exit Criteria

1. A repeated wide concat compiler probe passes and the generated code uses the dedicated helper.

### Phase 2: Runtime JSON Alias Transport Reduction

#### Red

1. Add focused runtime JSON coverage for alias-heavy assign chains that currently survive export.
2. Confirm the exported module still contains redundant alias forwarding in the compact path.

#### Green

1. Collapse alias-only assign chains during compact runtime JSON normalization/export when it is safe to do so.
2. Preserve runtime-visible names and existing liveness-sensitive behavior.

#### Exit Criteria

1. Alias-heavy compact runtime JSON exports collapse redundant forwards while preserving the surviving live targets.

### Phase 3: Runtime JSON Repeated-Concat Reduction

#### Red

1. Add focused runtime JSON coverage for repeated concat structures that currently serialize as large flat part lists.
2. Confirm the exporter still emits the repeated structure in expanded form.

#### Green

1. Introduce a compact export representation for repeated concat roots, or equivalent pooling that materially reduces serialized duplication without changing consumer semantics.
2. Teach the compiler-side parser/codegen to consume that compact representation if needed.

#### Exit Criteria

1. Repeated concat-heavy exports no longer serialize as fully duplicated part forests.

### Phase 4: SPARC64 Validation

#### Red

1. Re-measure the real SPARC64 runtime JSON and generated Rust artifacts after the targeted optimizations.
2. Re-run the focused SPARC64 compiler runner/parity gates that exercise the compile path.

#### Green

1. Keep targeted compiler and SPARC64 runner specs green.
2. Record the before/after artifact measurements in this PRD.

#### Exit Criteria

1. The measured SPARC64 artifacts are smaller or materially less duplicated than the baseline captured above.

## Acceptance Criteria

1. The work is landed in narrow red/green phases with targeted specs for each phase.
2. Repeated wide concat emission is compacted in the compiler backend.
3. At least one export-side duplication class is reduced in compact runtime JSON.
4. The PRD records concrete before/after measurements for the real SPARC64 artifacts.

## Risks And Mitigations

1. Export-side alias collapse could hide names that are still needed for runtime-visible probing.
   - Mitigation: keep the red focused on compact export shape and only collapse fully redundant alias transport after liveness-sensitive normalization.
2. Repeated-concat compaction could accidentally change bit ordering.
   - Mitigation: use end-to-end compiler probes that slice the repeated packed result back into observable outputs.
3. Small-source improvements may not translate into a practical rustc win on SPARC64.
   - Mitigation: keep each phase measurable and re-check the real SPARC64 artifacts after each landed optimization.

## Implementation Checklist

- [x] Phase 1: Compiler Repeated-Concat Compaction
- [x] Phase 2: Runtime JSON Alias Transport Reduction
- [x] Phase 3: Runtime JSON Repeated-Concat Reduction
- [x] Phase 4: SPARC64 Validation

## Latest Checkpoint

1. Phase 1 is green on March 19, 2026.
2. Red signal captured first:
   - `bundle exec rspec spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb --example 'uses a compact helper for repeated 256-bit concat patterns on the compiler backend'`
   - result: `1 example, 1 failure`
   - failure: generated code had `0` `wide_repeat_pattern(...)` hits
3. Green change landed in [lib/rhdl/sim/native/ir/ir_compiler/src/core.rs](/Users/skryl/Dev/rhdl/codex-circt/lib/rhdl/sim/native/ir/ir_compiler/src/core.rs):
   - generated Rust support code now includes `wide_repeat_pattern(...)`
   - repeated wide concat roots now lower through that helper instead of always emitting inline shift/or ladders
4. Focused validation is green:
   - `cargo build --manifest-path lib/rhdl/sim/native/ir/ir_compiler/Cargo.toml --release`
   - `bundle exec rspec spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb --order defined`
   - result: `11 examples, 0 failures`
5. Direct artifact-level probe after the change:
   - a live 256-bit repeated-output compiler probe now emits `2` `wide_repeat_pattern(...)` hits in generated Rust: one helper definition and one call site
6. Phase 2 and Phase 3 are green on March 19, 2026.
   - Red signals captured first:
     - `bundle exec rspec spec/rhdl/sim/native/ir/runtime_json_compaction_spec.rb --example 'collapses non-hierarchical alias chains during compact dump export'`
     - `bundle exec rspec spec/rhdl/sim/native/ir/runtime_json_compaction_spec.rb --example 'pools repeated concat parts through expr_ref in compact dump export'`
   - Green changes landed in [lib/rhdl/codegen/circt/runtime_json.rb](/Users/skryl/Dev/rhdl/codex-circt/lib/rhdl/codegen/circt/runtime_json.rb):
     - compact runtime export now collapses safe non-hierarchical signal alias chains during normalization
     - repeated concat roots can now pool a single repeated part through compact `expr_ref` reuse
   - Focused validation is green in the requested native-IR test area:
     - `bundle exec rspec spec/rhdl/sim/native/ir/runtime_json_compaction_spec.rb spec/rhdl/sim/native/ir/ir_compiler_overwide_runtime_only_spec.rb spec/rhdl/codegen/circt/runtime_json_spec.rb --order defined`
     - result: `28 examples, 0 failures`
   - One follow-up regression surfaced during the move:
     - streamed compact export in `dump_to_io` was missing the new repeat-key cache
     - fixed in [lib/rhdl/codegen/circt/runtime_json.rb](/Users/skryl/Dev/rhdl/codex-circt/lib/rhdl/codegen/circt/runtime_json.rb), covered by `streams the same repeated-concat compact payload through dump_to_io` in [spec/rhdl/sim/native/ir/runtime_json_compaction_spec.rb](/Users/skryl/Dev/rhdl/codex-circt/spec/rhdl/sim/native/ir/runtime_json_compaction_spec.rb)
7. Phase 4 is green on March 19, 2026.
   - Focused SPARC64 compile-path validation is green:
     - `bundle exec rspec spec/examples/sparc64/runners/ir_runner_spec.rb spec/examples/sparc64/runners/headless_runner_spec.rb --order defined`
     - result: `28 examples, 0 failures`
   - Real compiler artifact measurement on the cached SPARC64 runtime JSON:
     - `cargo run --manifest-path lib/rhdl/sim/native/ir/ir_compiler/Cargo.toml --release --bin aot_codegen -- tmp/sparc64_import_trees/e98520f9592d987ce1f35db1a4a78d003041d0a343d12d7dd157069f264418db/s1_top.runtime.json tmp/phase4/s1_top.from_baseline_runtime.rs`
     - result: [tmp/phase4/s1_top.from_baseline_runtime.rs](/Users/skryl/Dev/rhdl/codex-circt/tmp/phase4/s1_top.from_baseline_runtime.rs) is `53,910,178` bytes and `145,152` lines
   - Export-side replay measurement on the same real SPARC64 runtime artifact:
     - `ruby tmp/phase4/optimize_runtime_json_proxy.rb`
     - baseline JSON: `273,916,660` bytes, `1,786,483` exprs, `1,801` repeated-concat-ref roots
     - optimized proxy JSON: `273,612,461` bytes, `1,786,929` exprs, `2,341` repeated-concat-ref roots
   - Real compiler artifact measurement on the optimized proxy JSON:
     - `cargo run --manifest-path lib/rhdl/sim/native/ir/ir_compiler/Cargo.toml --release --bin aot_codegen -- tmp/phase4/s1_top.optimized_proxy.runtime.json tmp/phase4/s1_top.from_optimized_proxy.rs`
     - result: [tmp/phase4/s1_top.from_optimized_proxy.rs](/Users/skryl/Dev/rhdl/codex-circt/tmp/phase4/s1_top.from_optimized_proxy.rs) is `53,917,571` bytes and `145,720` lines
   - Net outcome:
     - the compiler-side repeated-concat work reduced the real SPARC64 generated Rust artifact from the original `87,018,125` byte baseline in this PRD down to `53,910,178` bytes
     - the export-side repeated-concat pooling reduced the real SPARC64 JSON payload by `304,199` bytes on the cached artifact replay path
     - that export-side reduction did not reduce generated Rust further on the current `aot_codegen` path for this cached SPARC64 artifact
