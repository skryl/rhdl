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
- Risk: AO486 clean imported runtime still depends on a broader reference-frontend/l1-icache path that is already red outside the new MLIR frontend work.
  - Mitigation: keep the MLIR frontend rollout focused on frontend/export correctness, and track AO486 boot-state failures separately once they are shown to reproduce on the legacy flattened-runtime path too.

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
- [x] Phase 3 MLIR/frontend-specific regressions green
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
- `bundle exec rspec spec/rhdl/import/import_paths_spec.rb -e 'relinks raised instance classes after dependency retries so deep hierarchy export stays intact'`
  - Green: 1 example, 0 failures
- `cargo test runtime_fallback_assigns && cargo build --release`
  - `lib/rhdl/sim/native/ir/ir_compiler`
  - Green after allowing mixed compiled/runtime evaluation without tick helpers
- `bundle exec rspec spec/rhdl/sim/native/ir/ir_simulator_input_format_spec.rb -e 'chooses the uninstantiated root module instead of the last module in MLIR order' -e 'allows the compiler backend to mix compiled logic with runtime fallback overwide assigns'`
  - Green: 2 examples, 0 failures
- `bundle exec rspec spec/examples/ao486/integration/ir_runner_boot_smoke_spec.rb:37`
  - Still red after the MLIR frontend/export fixes: `pipeline_inst__decode_inst__eip` remains `0` while reset is released and prefetch arms `0xFFFF0/16`
- `bundle exec rspec spec/examples/ao486/import/unit/cache/l1_icache_runtime_spec.rb`
  - Still red on the legacy flattened CIRCT-runtime-JSON path: `state` and `update_tag_addr` remain `0`, so the clean imported `l1_icache` startup bug reproduces outside the new MLIR frontend
- `bundle exec rspec spec/rhdl/import/import_paths_spec.rb -e 'does not reuse cached imported MLIR text during hierarchy or direct MLIR regeneration' -e 'reuses attached imported CIRCT modules for hierarchy MLIR export on raised imported components'`
  - Green: 2 examples, 0 failures
- `bundle exec rake native:build`
  - Green after canonicalizing parsed MLIR signal widths against the final module width map
- `bundle exec rspec spec/rhdl/sim/native/ir/ir_simulator_input_format_spec.rb -e 'preserves full signal widths for forward-referenced seq registers in MLIR'`
  - Green: 1 example, 0 failures
- `bundle exec rspec spec/examples/ao486/import/unit/cache/l1_icache_runtime_spec.rb -e 'delays the first memory request until the startup tag clear sweep completes on IR JIT via the MLIR frontend'`
  - Green: the imported AO486 `l1_icache` startup sweep now reaches the first `MEM_REQ` on the MLIR frontend path
- `bundle exec rspec spec/examples/ao486/import/unit/cache/l1_icache_runtime_spec.rb -e 'delays the first memory request until the startup tag clear sweep completes on IR JIT'`
  - Green: both the legacy flattened path and the MLIR frontend path pass together
