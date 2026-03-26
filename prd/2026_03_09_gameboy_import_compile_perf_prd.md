# Status

In Progress - March 9, 2026

## Context

Game Boy mixed import and compiler-backed parity flows are showing long wall-clock times and multi-GB Ruby RSS growth during the import/compile path. Fresh measurement on March 9, 2026 showed bounded time in GHDL and `circt-verilog`, followed by Ruby CPU/RSS growth inside post-import processing while exporting normalized Verilog and downstream runtime artifacts.

## Goals

1. Reduce Ruby-side wall-clock time in Game Boy mixed import.
2. Reduce Ruby-side peak memory during Game Boy mixed import/compiler setup.
3. Preserve existing import artifact and parity behavior.

## Non-Goals

1. Reworking the imported CIRCT artifact model.
2. Replacing the IR compiler backend.
3. Large-scale redesign of the runtime JSON format in this pass.

## Phased Plan

### Phase 1: Importer Rescan Reduction

#### Red

1. Reproduce the Game Boy importer slowdown with timed progress output.
2. Confirm repeated full-file Verilog scans in `SystemImporter`.

#### Green

1. Cache per-file Verilog analysis during one importer run.
2. Reuse the selected-module analysis instead of recomputing it.
3. Remove avoidable quadratic queue and duplicate-edge work in module graph construction.

#### Exit Criteria

1. One importer run no longer rereads/reparses the same source Verilog files multiple times for module indexing/reference graph construction.

### Phase 2: Canonical Verilog Overlay Rewrite Cost

#### Red

1. Reproduce the importer stalling inside normalized Verilog export.
2. Confirm Ruby-side whole-file regex replacement over canonical Verilog.

#### Green

1. Replace repeated per-module regex replacement with a single parsed module-span rewrite pass.
2. Preserve generated-memory overlay behavior for canonical normalized Verilog.

#### Exit Criteria

1. Canonical Verilog overlay runs in one linear pass over the normalized Verilog text.

### Phase 3: Runtime/Compiler Path Follow-Up

#### Red

1. Re-measure importer/runtime parity after phases 1 and 2.
2. If still needed, isolate remaining duplicate runtime JSON work.

#### Green

1. Land the smallest additional runtime JSON / simulator reductions needed for Game Boy compiler-backed parity.

#### Exit Criteria

1. Remaining hot path is no longer dominated by avoidable duplicate Ruby preprocessing.

## Acceptance Criteria

1. Targeted importer/import-task specs remain green.
2. Game Boy importer repro shows materially lower Ruby RSS and/or improved time in the previously hot post-import steps.
3. No Game Boy import artifact path/regression expectations break in touched specs.

## Risks And Mitigations

1. Verilog module-block parsing could change overlay semantics.
   - Mitigation: keep existing overlay specs green and preserve exact module-block replacement behavior.
2. Importer caching could accidentally leak stale state across runs.
   - Mitigation: scope caches to importer instances and key by expanded file path plus resolved source set.
3. Remaining slowdown may move to runtime JSON generation after importer fixes.
   - Mitigation: re-measure before broadening the change set.

## Implementation Checklist

- [x] Phase 1: Importer Rescan Reduction
- [x] Phase 2: Canonical Verilog Overlay Rewrite Cost
- [ ] Phase 3: Runtime/Compiler Path Follow-Up
  - Runtime JSON liveness recursion and module-wide DAG hoisting landed.
  - Import runtime JSON now writes compact `expr_ref` form for compiler-backed consumers.
  - Remaining work: compact runtime JSON expression-table construction is still the dominant late-stage RSS spike for full Game Boy import.
