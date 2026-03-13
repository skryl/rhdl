# Status

Completed - March 9, 2026

## Context

The shared CIRCT importer can currently relax dependency closure with `extern_modules`, but it cannot replace selected imported modules with deterministic stub implementations. That makes it hard to:

1. trim known-problem subsystems out of an imported design without editing source HDL
2. keep raise/runtime/ARC flows aligned on the same stubbed module graph
3. run targeted experiments like Game Boy Arcilator parity with disabled subsystems removed from the imported artifact itself

The AO486 importer has its own source-level blackbox stub flow, but the shared CIRCT import path does not yet expose an equivalent module-replacement option.

## Goals

1. Add a shared importer option that can stub selected imported modules automatically.
2. Make the option available through the shared import cleanup path so it affects raise/runtime/ARC consumers consistently.
3. Thread the option through the Game Boy importer and ARC-prep helpers.

## Non-Goals

1. Building a full behavioral mocking DSL for arbitrary modules.
2. Replacing AO486's separate source-tree stub strategy.
3. Solving Game Boy Arcilator legality by itself in this change.

## Phased Plan

### Phase 1: Shared Cleanup Stubbing

#### Red

1. Add failing cleanup-level coverage for replacing a selected module even when the input MLIR has no LLHD overlay.
2. Add failing coverage for simple output overrides so stubbed modules can do more than constant-zero outputs when requested.

#### Green

1. Extend `ImportCleanup.cleanup_imported_core_mlir` with `stub_modules`.
2. Support deterministic default stubs plus simple per-output overrides.

#### Exit Criteria

1. Cleanup can replace named modules with generated stub modules and emit valid MLIR.

### Phase 2: Threading

#### Red

1. Add failing task/importer/tooling coverage showing the new option is not propagated.

#### Green

1. Thread `stub_modules` through `ImportTask`, shared ARC-prep tooling, and Game Boy `SystemImporter`.
2. Record stub metadata in the shared import report.

#### Exit Criteria

1. Shared importer callers can request module stubbing from the top-level API and see it reflected in the report/result metadata.

### Phase 3: Validation

#### Red

1. Run focused cleanup/task/importer/tooling specs covering the new option.

#### Green

1. Keep targeted specs green and document any remaining limitations.

#### Exit Criteria

1. The new importer option is implemented, covered, and documented by tests/PRD status.

## Acceptance Criteria

1. Import cleanup accepts a `stub_modules` option.
2. A stub can be requested by module name with deterministic default output behavior.
3. A stub can optionally override selected outputs with constants or passthrough input signals.
4. `ImportTask`, ARC-prep tooling, and Game Boy `SystemImporter` expose the option.
5. Import reports include the requested stub modules.

## Risks And Mitigations

1. Generated stubs could silently hide important behavior.
   - Mitigation: keep stubs opt-in and record them in importer metadata/reports.
2. Selective per-module reparsing could get slower when stubbing modules without LLHD overlays.
   - Mitigation: only force reparse when `stub_modules` is non-empty.
3. Output override flexibility could become too broad and fragile.
   - Mitigation: keep the first version narrow: constant values plus input passthrough by signal name.

## Implementation Checklist

- [x] Phase 1: Shared Cleanup Stubbing
- [x] Phase 2: Threading
- [x] Phase 3: Validation
