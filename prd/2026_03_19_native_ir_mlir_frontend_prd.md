# Native IR MLIR Frontend PRD

Status: In Progress
Date: 2026-03-19

## Context

The native IR simulator backends (`interpreter`, `jit`, `compiler`) currently accept only compact CIRCT runtime JSON. The repo can already export real CIRCT `hw/comb/seq` MLIR via `to_mlir_hierarchy`, but there is no native frontend that can consume that text directly.

The immediate goal is narrower than the broader import/export unification discussion: add a native IR frontend that accepts MLIR emitted by `to_mlir_hierarchy` and makes it usable by the existing native IR backends, while preserving the current JSON path.

## Goals

- Add a shared native frontend used by the interpreter, JIT, and compiler backends.
- Accept MLIR text emitted by `to_mlir_hierarchy`.
- Preserve the existing native CIRCT runtime JSON input path.
- Support hierarchical MLIR by resolving the exported top module and flattening instances before execution.
- Expose the new frontend through `RHDL::Sim::Native::IR::Simulator`.

## Non-goals

- Rework the broader RHDL import -> normalize -> export pipeline.
- Add web frontend support in this pass.
- Support arbitrary third-party MLIR dialect mixtures.
- Fully cover async array-style memory lowering in v1 if the native frontend encounters shapes outside the repo’s current targeted subset.

## Scope

- Ruby wrapper changes in `lib/rhdl/sim/native/ir/simulator.rb`.
- Shared Rust/native frontend code under `lib/rhdl/sim/native/ir/common/`.
- Interpreter/JIT/compiler backend entry-point integration.
- Ruby integration coverage for JSON parity, MLIR acceptance, and hierarchical MLIR flattening.

## Risks And Mitigations

- Risk: `to_mlir_hierarchy` emits a broader op subset than the native frontend initially handles.
  - Mitigation: target the concrete exporter subset exercised by the new specs first; fail clearly on unsupported MLIR ops/types instead of silently mis-lowering.
- Risk: compiler backend behavior could regress if the shared frontend changes normalization shape.
  - Mitigation: keep the backend-facing normalized IR shape stable and run targeted parity checks across all available native backends.
- Risk: hierarchy flattening semantics could diverge from the existing Ruby flatten path.
  - Mitigation: add a dedicated hierarchical MLIR spec that checks both top-level outputs and flattened instance-visible signals.

## Acceptance Criteria

- `RHDL::Sim::Native::IR::Simulator` accepts compact CIRCT runtime JSON and `to_mlir_hierarchy` MLIR.
- Available native backends execute the same counter behavior from JSON and MLIR input.
- Hierarchical MLIR with `hw.instance` is flattened correctly for native execution.
- Existing JSON callers continue to work unchanged.
- The PRD status/checklist reflects the delivered state.

## Phased Plan

### Phase 1: Frontend API Red

Red:
- Add failing Ruby specs for:
  - MLIR input-format support in the simulator wrapper
  - MLIR autodetection/effective format reporting
  - native backend execution from `to_mlir_hierarchy`
  - hierarchical MLIR flattening through `hw.instance`
- Capture the baseline failure signal from the targeted spec file.

Green:
- Update the Ruby wrapper API surface to recognize MLIR input format and route MLIR payloads into the native frontend path.

Exit Criteria:
- The spec file fails for the missing MLIR/native frontend behavior before backend implementation.

### Phase 2: Shared Native Frontend Green

Red:
- Keep the new Ruby MLIR specs failing while the native backends remain JSON-only.

Green:
- Introduce a shared native frontend module that:
  - accepts compact runtime JSON and exported MLIR
  - normalizes payloads into the backend runtime module shape
  - resolves the top MLIR module and flattens hierarchy
- Wire interpreter, JIT, and compiler to use the shared frontend instead of private JSON-only parsing.

Exit Criteria:
- Available native backends pass the new MLIR execution specs.

### Phase 3: Regression And Lock-In

Red:
- Run targeted native IR regressions to expose compatibility issues in the preserved JSON path.

Green:
- Fix any JSON or backend-specific regressions.
- Update this PRD status/checklist/command log to match the delivered result.

Exit Criteria:
- Targeted native IR regressions pass and the PRD is updated to the completed state if all work lands.

## Execution Checklist

- [x] Phase 1 red specs added
- [x] Phase 1 baseline failure captured
- [x] Phase 2 shared native frontend implemented
- [x] Phase 2 MLIR execution specs green
- [ ] Phase 3 targeted native regressions green
- [x] PRD status/checklist/command log updated

## Command Log

- `bundle exec rspec spec/rhdl/sim/native/ir/ir_simulator_input_format_spec.rb`
  - Red baseline: 8 failures for missing `:auto`/`:mlir` support and MLIR native execution
- `bundle exec ruby -c lib/rhdl/sim/native/ir/simulator.rb`
- `cargo check`
  - `lib/rhdl/sim/native/ir/ir_interpreter`
  - `lib/rhdl/sim/native/ir/ir_jit`
  - `lib/rhdl/sim/native/ir/ir_compiler`
- `bundle exec rake native:build`
- `bundle exec rspec spec/rhdl/sim/native/ir/ir_simulator_input_format_spec.rb`
  - Green: 19 examples, 0 failures
- `cargo test`
  - `lib/rhdl/sim/native/ir/ir_interpreter`
  - Green
- `cargo test`
  - `lib/rhdl/sim/native/ir/ir_jit`
  - Green
- `cargo test`
  - `lib/rhdl/sim/native/ir/ir_compiler`
  - Fails on existing `core::tests::reports_fast_path_blockers_for_runtime_fallback_assigns`
- `bundle exec rspec spec/rhdl/sim/native/ir/circt_hierarchy_flatten_runtime_spec.rb`
  - Fails on existing `child_y` visibility expectations on the compact runtime JSON path
