# Status

In Progress - March 9, 2026

## Context

The remaining non-unit Game Boy import correctness gates are not failing on explicit parity assertions first. They are running for minutes while Ruby RSS grows into multi-GB territory, which makes the suite operationally unreliable even when individual examples appear close to finishing.

March 9 update:
- the heavy specs now drop importer/report state earlier, avoid trace-copy alignment, and explicitly close native IR simulators
- parity specs were switched away from importer-written `runtime_json_path` artifacts onto imported `core.mlir` with `emit_runtime_json: false`
- targeted simulator regressions are green
- imported compiler-backed setup is materially smaller than it was at the start of the day:
  - compiler FFI now initializes tracer metadata lazily
  - the Game Boy import runner no longer retains the flattened module graph or full signal-name table after deriving the small lookup state it actually uses
  - the import runner now drops flat Ruby nodes before entering `Simulator.new`
  - compiler-backed Game Boy simulators can now trim batched-only runtime state during `Simulator.new`
- the remaining blocker is still the imported compiler-backed execution path under the heavy Game Boy parity workload, which continues to grow into the high-GB range before a clean certified exit
- latest sequential behavioral probe on March 9, 2026:
  - importer + source-runner path stayed roughly in the `0.45-0.65 GB RSS` range
  - imported runner init improved to about `3.1 GB RSS` at `~1m47s`, `7.5 GB` at `~3m10s`, `10.6 GB` at `~4m29s`
  - the process still reached about `12.4 GB RSS` by `~5m23s` before termination, so the gate remains improved but uncertified

## Goals

1. Reduce Ruby-side retained memory in the heavy Game Boy import correctness specs.
2. Keep the behavioral/parity assertions unchanged.
3. Get at least one of the remaining heavy sequential gates to complete more cleanly after the reductions.

## Non-Goals

1. Reworking the imported Game Boy design itself.
2. Changing the intended parity coverage.
3. Broad importer/runtime redesign outside the immediate test harness retention path.

## Phased Plan

### Phase 1: Drop Avoidable Retained State

#### Red

1. Confirm heavy examples retain large objects beyond the point they are needed.
2. Confirm simulator setup keeps full runtime JSON in Ruby memory after native initialization.

#### Green

1. Add an opt-out for retaining simulator input JSON once the native backend is created.
2. Release importer/result/report objects earlier inside the heavy Game Boy import specs and force GC between phases where helpful.

#### Exit Criteria

1. Heavy examples no longer keep the full imported runtime JSON string and importer objects alive unnecessarily across later phases.

### Phase 2: Remove Trace Comparison Duplication

#### Red

1. Confirm parity specs duplicate large trace arrays during alignment/comparison.

#### Green

1. Compare aligned traces without allocating dropped/trimmed copies of the full traces.

#### Exit Criteria

1. Trace comparison no longer duplicates the retained trace arrays for the main Verilator/IR/Arcilator comparisons.

### Phase 3: Validation

#### Red

1. Run targeted simulator regressions for the new simulator option.
2. Rerun at least one heavy Game Boy import correctness gate sequentially.

#### Green

1. Keep targeted regressions green.
2. Record whether the heavy gate now finishes cleanly or remains blocked.

#### Exit Criteria

1. We have an updated, verified status for the heavy Game Boy import correctness gates after the memory-retention reductions.

## Acceptance Criteria

1. Native simulator callers can opt out of retaining full input JSON strings in Ruby memory.
2. Heavy Game Boy import correctness specs drop avoidable large references earlier.
3. Trace comparison avoids extra full-array copies.
4. Heavy parity specs can bypass importer-written runtime JSON artifacts when they only need imported execution/parity coverage.
5. Targeted regressions pass and at least one heavy sequential gate is rerun.

## Risks And Mitigations

1. Clearing retained JSON could break callers that expect `sim.ir_json` later.
   - Mitigation: make it opt-in and only use it in the heavy Game Boy import runner path.
2. Earlier GC/release steps could hide useful debugging context.
   - Mitigation: keep on-disk artifacts and concise failure summaries unchanged.
3. Trace comparison refactors could accidentally weaken parity assertions.
   - Mitigation: preserve the existing “first shared aligned prefix” comparison semantics.

## Implementation Checklist

- [x] Phase 1: Drop Avoidable Retained State
- [x] Phase 2: Remove Trace Comparison Duplication
- [ ] Phase 3: Validation
