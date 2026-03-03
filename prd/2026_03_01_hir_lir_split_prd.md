# HIR/LIR Split PRD

## Status
Completed (2026-03-02)

## Context
The current `RHDL::Codegen::IR` lowering path serves two different consumers:
1. Verilog export fidelity (wants high-level structure preserved).
2. Simulation execution (wants normalized deterministic updates).

This dual use currently forces premature lowering of indexed/sliced assignment targets into read-modify-write forms, which harms structural fidelity in exported Verilog and complicates importer parity work.

## Goals
1. Introduce explicit HIR/LIR separation in codegen interfaces.
2. Route Verilog export through HIR.
3. Keep simulation on LIR.
4. Preserve backward compatibility for existing simulation and import flows.
5. Add targeted tests proving split behavior.

## Non-Goals
1. Full HIR replacement of all existing LIR nodes in one tranche.
2. Rewriting Rust IR simulator backends in this tranche.
3. Full dynamic part-select canonicalization in one step.

## Phased Plan (Red/Green/Refactor)

### Phase 1: Interface Split Skeleton
Red:
1. Add failing specs for explicit HIR and LIR lower entry points.
2. Add failing spec asserting `RHDL::Codegen.verilog` uses HIR path.

Green:
1. Add `RHDL::Codegen::HIR` and `RHDL::Codegen::LIR` namespaces.
2. Add `HIR::Lower` and `LIR::Lower` entry points.
3. Keep existing `IR::Lower` as implementation backbone, defaulting to LIR mode.

Refactor:
1. Keep new namespaces thin wrappers for compatibility.

Exit criteria:
1. Export and simulation compile with explicit split entry points available.

### Phase 2: Target-Preservation in HIR vs Normalization in LIR
Red:
1. Add failing tests demonstrating:
   - HIR preserves indexed/sliced assignment targets.
   - LIR lowers indexed/sliced targets to read-modify-write forms.

Green:
1. Add mode-aware lowering in `IR::Lower`:
   - `mode: :hir` preserves recoverable lvalue targets.
   - `mode: :lir` retains current normalization behavior.
2. Ensure register-port detection still works with HIR target forms.

Refactor:
1. Extract helper methods for target-name discovery and mode checks.

Exit criteria:
1. HIR and LIR lowerers produce intentionally different target forms with passing specs.

### Phase 3: Verilog Uses HIR, Sim Uses LIR
Red:
1. Add failing tests showing:
   - Verilog emitter can accept HIR preserved targets.
   - IR simulator paths still consume LIR.

Green:
1. Route `RHDL::Codegen.verilog` and `RHDL::Export.to_verilog` through HIR lowering.
2. Keep simulator/harness calls on LIR lowering.
3. Add Verilog emitter handling for preserved HIR lvalue targets.

Refactor:
1. Isolate HIR-only emission helpers from LIR fallback recovery logic.

Exit criteria:
1. Export works via HIR without breaking LIR simulation behavior.

### Phase 4: Importer Regression and Ao486 Gate
Red:
1. Run importer roundtrip gates and capture failure deltas.

Green:
1. Fix HIR export regressions without regressing LIR sim semantics.
2. Re-run targeted importer and roundtrip specs.

Refactor:
1. Document known residual mismatches separately from split architecture.

Exit criteria:
1. No new parse regressions introduced by HIR/LIR split.

Phase 4 result (2026-03-02):
1. Red captured on `spec/examples/ao486/import/all_modules_ast_roundtrip_spec.rb` due invalid recovered lvalue emit in `sound_dsp` (`sample_dma[15:8]` and `sample_dma[7:0]` without memory index).
2. Green implemented in `IR::Lower` by lowering memory-like word-slice lvalues (`mem[idx][hi:lo]`) to `IR::MemoryWrite` with word-level RMW.
3. Regression specs added in `spec/rhdl/codegen/hir_lir_split_spec.rb` for HIR lowering and Verilog emission of indexed slice writes.
4. Ao486 gate rerun green:
   - `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486/import/all_modules_ast_roundtrip_spec.rb`
   - `bundle exec rspec spec/examples/ao486/import`
   - `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486` (`32 examples, 0 failures`)

## Acceptance Criteria
1. `RHDL::Codegen::HIR::Lower` and `RHDL::Codegen::LIR::Lower` exist and are tested.
2. Verilog export entry path uses HIR lowering.
3. Simulation entry paths remain on LIR lowering.
4. New tests verify indexed/sliced target preservation in HIR and lowering in LIR.
5. Existing targeted codegen/import specs remain green.

## Current Gate Results
1. HIR/LIR split entry points are implemented and covered by targeted specs.
2. Verilog export now uses HIR; CIRCT/simulation call paths use LIR.
3. Ao486 all-module roundtrip no longer fails Verilator parse on illegal scalar selects from recovered/preserved lvalues.
4. Ao486 importer and ao486 slow suite gates are green after memory-like slice lvalue fix.
5. Canonical AST structural mismatches remain a separate importer fidelity backlog, outside the HIR/LIR split completion gate.

## Risks and Mitigations
1. Risk: subtle breakage in existing export behavior.
   Mitigation: keep LIR default behavior unchanged and add focused exporter specs.
2. Risk: mixed target types break reg-port detection.
   Mitigation: centralize target-name extraction helper with tests.
3. Risk: importer roundtrip parse regressions.
   Mitigation: keep Verilog compatibility fallbacks and run ao486 roundtrip gate.

## Implementation Checklist
- [x] Phase 1 red tests added
- [x] Phase 1 green implementation complete
- [x] Phase 1 refactor complete
- [x] Phase 2 red tests added
- [x] Phase 2 green implementation complete
- [x] Phase 2 refactor complete
- [x] Phase 3 red tests added
- [x] Phase 3 green implementation complete
- [x] Phase 3 refactor complete
- [x] Phase 4 red/green/regression complete
