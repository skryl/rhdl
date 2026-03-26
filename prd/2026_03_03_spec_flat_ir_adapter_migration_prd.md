## Status
Completed (2026-03-03)

## Context
The CIRCT cutover introduced `to_flat_circt_nodes` as the adapter entrypoint, but a subset of specs still call `to_flat_ir` directly. This keeps test coverage tied to the legacy flattening contract and weakens confidence for upcoming backend-by-backend adapter removal.

This PRD migrates all remaining spec callsites from `to_flat_ir` to adapter-path usage (`to_flat_circt_nodes` + existing adapter consumers like `IRToJson.convert`).

## Goals
1. Eliminate all `to_flat_ir` usage in `spec/`.
2. Preserve current backend behavior by keeping `IRToJson` and simulator APIs unchanged.
3. Keep parity coverage intact while shifting all spec entrypoints through adapter paths.
4. Create a clean baseline for subsequent per-backend adapter removal with parity checks.

## Non-Goals
1. Removing `to_flat_ir` from production code in this PRD.
2. Converting interpreter/JIT/compiler to native CIRCT runtime format in this PRD.
3. Changing simulator JSON schemas or backend FFI interfaces.
4. Refactoring unrelated test logic beyond the migration scope.

## Scope
### In Scope
- Replace all `spec/` callsites of `to_flat_ir` with `to_flat_circt_nodes`.
- Update nearby comments/variable names where they explicitly reference flat legacy IR.
- Re-run targeted and broad lib test gates.

### Out of Scope
- `lib/` and `examples/` runtime callsites still using `to_flat_ir`.
- Backend adapter-removal work (planned as follow-on phases after this baseline).

## Remaining Callsite Inventory (Baseline)
1. `spec/examples/apple2/hdl/apple2_spec.rb` (5 refs)
2. `spec/examples/apple2/integration/karateka_divergence_spec.rb` (1 ref)
3. `spec/examples/mos6502/integration/karateka_divergence_spec.rb` (2 refs)
4. `spec/examples/8bit/hdl/cpu/ir_runner_extension_spec.rb` (1 ref)
5. `spec/examples/gameboy/hdl/link_spec.rb` (1 ref)
6. `spec/examples/gameboy/hdl/timer_spec.rb` (1 ref)
7. `spec/examples/gameboy/hdl/speedcontrol_spec.rb` (1 ref)
8. `spec/examples/gameboy/hdl/dma/hdma_spec.rb` (1 ref)
9. `spec/examples/gameboy/hdl/gb_spec.rb` (1 ref)
10. `spec/rhdl/codegen/ir/sim/ir_jit_memory_ports_spec.rb` (2 refs)
11. `spec/rhdl/codegen/ir/sim/ir_compiler_spec.rb` (1 ref)
12. `spec/rhdl/codegen/source_schematic_spec.rb` (1 ref)

Total baseline refs: 18.

## Phased Plan (Red/Green)
### Phase 1: Core Codegen/Adapter Spec Conversion
- Red:
  - Add or update expectations where necessary so specs still validate adapter behavior after callsite switch.
  - Confirm baseline grep shows `to_flat_ir` references in target files before edits.
- Green:
  - Convert:
    - `spec/rhdl/codegen/ir/sim/ir_jit_memory_ports_spec.rb`
    - `spec/rhdl/codegen/ir/sim/ir_compiler_spec.rb`
    - `spec/rhdl/codegen/source_schematic_spec.rb`
    - `spec/examples/8bit/hdl/cpu/ir_runner_extension_spec.rb`
- Exit Criteria:
  - Above files no longer call `to_flat_ir`.
  - Targeted codegen specs pass.

### Phase 2: Example Suite Conversion (Apple2, MOS6502, GameBoy)
- Red:
  - Capture current behavior expectations in touched helper methods (boot/parity helpers).
  - Preserve skip behavior in tool/ROM-dependent tests.
- Green:
  - Convert:
    - `spec/examples/apple2/hdl/apple2_spec.rb`
    - `spec/examples/apple2/integration/karateka_divergence_spec.rb`
    - `spec/examples/mos6502/integration/karateka_divergence_spec.rb`
    - `spec/examples/gameboy/hdl/link_spec.rb`
    - `spec/examples/gameboy/hdl/timer_spec.rb`
    - `spec/examples/gameboy/hdl/speedcontrol_spec.rb`
    - `spec/examples/gameboy/hdl/dma/hdma_spec.rb`
    - `spec/examples/gameboy/hdl/gb_spec.rb`
- Exit Criteria:
  - No functional regression in touched example specs (allowing environment/tool skips).

### Phase 3: Consolidation and Migration Gate
- Red:
  - Verify global grep still detects any `spec/` `to_flat_ir` references after phases 1-2.
- Green:
  - Remove any remaining `to_flat_ir` references in `spec/`.
  - Run broad confidence gate (`bundle exec rake spec[lib]`).
  - Record migration completion and residual risks.
- Exit Criteria:
  - `rg -n "to_flat_ir" spec` returns no matches.
  - Broad lib gate passes or documented skip/failure reasons are captured.

## Exit Criteria Per Phase
1. Phase 1 complete: Core codegen adapter specs are converted and green.
2. Phase 2 complete: Example suites are converted and maintain existing parity expectations.
3. Phase 3 complete: Zero `to_flat_ir` in `spec/` plus broad lib gate run.

## Acceptance Criteria (Full Completion)
1. There are zero `to_flat_ir` references under `spec/`.
2. All converted specs compile and run under existing test commands.
3. Existing parity assertions (backend comparisons and state checks) remain intact.
4. No changes to backend simulator public inputs/outputs in this PRD.
5. PRD checklist reflects true completion state.

## Risks and Mitigations
- Risk: Some specs rely on legacy object assumptions (`flat_ir` naming or class checks).
  - Mitigation: Keep adapter usage explicit and adjust local variable naming where clarity is needed.
- Risk: Environment-dependent suites (ROM/tooling/native extensions) can mask regressions.
  - Mitigation: Run deterministic core specs first, then broad gate, and document any skipped gates.
- Risk: Parallel edits across large spec files can conflict.
  - Mitigation: Assign strict file ownership per worker stream and avoid cross-stream edits.

## Execution Streams (Agent Team)
1. Stream A (Core Codegen Specs)
- Owner files:
  - `spec/rhdl/codegen/ir/sim/ir_jit_memory_ports_spec.rb`
  - `spec/rhdl/codegen/ir/sim/ir_compiler_spec.rb`
  - `spec/rhdl/codegen/source_schematic_spec.rb`
  - `spec/examples/8bit/hdl/cpu/ir_runner_extension_spec.rb`

2. Stream B (Apple2 Specs)
- Owner files:
  - `spec/examples/apple2/hdl/apple2_spec.rb`
  - `spec/examples/apple2/integration/karateka_divergence_spec.rb`

3. Stream C (MOS6502 + GameBoy Specs)
- Owner files:
  - `spec/examples/mos6502/integration/karateka_divergence_spec.rb`
  - `spec/examples/gameboy/hdl/link_spec.rb`
  - `spec/examples/gameboy/hdl/timer_spec.rb`
  - `spec/examples/gameboy/hdl/speedcontrol_spec.rb`
  - `spec/examples/gameboy/hdl/dma/hdma_spec.rb`
  - `spec/examples/gameboy/hdl/gb_spec.rb`

## Testing Gates
1. Stream-local targeted specs for each stream.
2. Combined touched-file rspec run.
3. Broad gate: `bundle exec rake spec[lib]`.
4. Migration grep gate: `rg -n "to_flat_ir" spec` must be empty.

## Implementation Checklist
- [x] PRD created with phased plan and ownership streams.
- [x] Phase 1 Red: Baseline `to_flat_ir` inventory captured and validated.
- [x] Phase 1 Green: Stream A files migrated to adapter path and targeted tests pass.
- [x] Phase 2 Red: Example helper assumptions validated in touched files.
- [x] Phase 2 Green: Streams B/C files migrated and targeted tests pass.
- [x] Phase 3 Red: Confirm no remaining `to_flat_ir` in `spec/` via grep.
- [x] Phase 3 Green: Run `bundle exec rake spec[lib]` and record outcome.
- [x] Mark PRD status `Completed (YYYY-MM-DD)` only after all acceptance criteria pass.

## Kickoff Status (2026-03-03)
- Stream planning and ownership handoff completed for Streams A/B/C.
- Stream and consolidated test gates completed:
  - `rg -n "to_flat_ir" spec` -> 0 matches
  - Stream-targeted `rspec` runs -> passing (with pre-existing pendings/skips)
  - Broad gate `bundle exec rake 'spec[lib]'` -> `2372 examples, 0 failures, 1 pending`
