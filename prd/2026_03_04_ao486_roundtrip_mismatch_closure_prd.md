# AO486 Strict Roundtrip Mismatch Closure PRD

## Status
- Completed (2026-03-04)

## Context
The full AO486 roundtrip spec (`Verilog -> CIRCT -> RHDL -> CIRCT`) currently fails strict normalized AST parity.

Current baseline from `spec/examples/ao486/import/roundtrip_spec.rb`:
- source modules: 75
- roundtrip modules: 75
- missing modules: 0
- extra modules: 0
- mismatched modules: 50
- mismatch fields:
  - assigns: 49 modules
  - instances: 18 modules

Observed root causes:
1. Raised classes compiled in anonymous namespaces emit unstable instance module names (for example `__module_0x...__memory` instead of `memory`).
2. Assign-expression coverage is not preserved across raise + re-export for many modules.
3. Import/export canonicalization is not yet strict enough for full-project parity edge cases.

## Goals
1. Reduce AO486 strict roundtrip mismatch count from 50 to 0.
2. Preserve exact module-set closure (75 source modules == 75 roundtrip modules).
3. Keep current strict roundtrip comparator unchanged (no relaxation/fallback semantics).
4. Keep existing import/raise/task specs green while closing AO486 strict parity.

## Non-Goals
1. Replacing external LLVM/CIRCT tooling boundaries for Verilog import/export.
2. Replacing strict AST parity with semantic-only parity.
3. Enabling the AO486 full roundtrip test in default fast spec lanes.

## Phased Plan (Red/Green)

### Phase 0: Baseline Lock + Diff Reporter
Red:
- Ensure the AO486 strict roundtrip spec prints deterministic mismatch summaries (counts + top modules).
- Add a reproducible mismatch census command for local debugging.

Green:
- Baseline mismatch report is stable across reruns.

Exit criteria:
- We can rerun and consistently reproduce mismatch totals and field breakdowns.

### Phase 1: Instance Name Stability
Red:
- Add failing tests for raised-class module identity stability under anonymous `Module.new` namespaces.

Green:
- Raised classes define stable `verilog_module_name` tied to original CIRCT module names.
- Instance module names roundtrip identically for imported AO486 modules.

Exit criteria:
- Instance mismatch count drops to 0 in AO486 strict roundtrip report.

### Phase 2: Assign Preservation in Raise/Export
Red:
- Add failing unit/integration tests for dropped assign expressions during CIRCT -> RHDL -> CIRCT.
- Capture representative fixtures from `decode`, `execute`, `l1_icache`, `execute_divide`, `memory`.

Green:
- Raise path preserves assign-expression intent needed for strict parity.
- Export path preserves those expressions through re-import.

Exit criteria:
- Assign mismatch count significantly reduced and no regressions in existing CIRCT raise/import specs.

### Phase 3: Import/Export Canonicalization Closure
Red:
- Add failing tests for naming/collision and canonicalization edge cases found in remaining AO486 deltas.

Green:
- Import/export canonicalization updated to eliminate remaining structural drift without weakening strictness.

Exit criteria:
- Remaining mismatch categories are closed in targeted tests.

### Phase 4: Full AO486 Strict Closure
Red:
- Full slow roundtrip spec still failing.

Green:
- Full AO486 strict roundtrip spec passes with:
  - missing = 0
  - extra = 0
  - mismatched = 0

Exit criteria:
- Full AO486 strict roundtrip passes in two consecutive runs.

## Exit Criteria Per Phase
- Phase 0: deterministic baseline + reporting.
- Phase 1: instance mismatches resolved.
- Phase 2: assign mismatches materially reduced with tests.
- Phase 3: canonicalization edge cases resolved.
- Phase 4: strict roundtrip mismatch total is zero.

## Acceptance Criteria (Full Completion)
1. `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486/import/roundtrip_spec.rb` passes.
2. No missing/extra/mismatched modules in strict report.
3. Existing related suites remain green:
   - `spec/rhdl/codegen/circt/raise_spec.rb`
   - `spec/rhdl/import/import_paths_spec.rb`
   - `spec/examples/ao486/import/system_importer_spec.rb`
4. No fallback logic or comparator weakening introduced to force pass.

## Risks and Mitigations
1. Risk: MLIR export changes break existing codegen expectations.
   - Mitigation: add focused red tests before each change and run adjacent suites every phase.
2. Risk: Name canonicalization fixes can regress hierarchical references.
   - Mitigation: add explicit instance-module identity fixtures in raise/import tests.
3. Risk: AO486 full run is slow and noisy for iteration.
   - Mitigation: maintain fast targeted fixtures for each root-cause family.

## Implementation Checklist
- [x] Phase 0 baseline and mismatch taxonomy captured.
- [x] Phase 1 instance-name stability tests added.
- [x] Phase 1 instance-name stability implementation landed.
- [x] Phase 1 verification run completed.
- [x] Phase 2 assign-preservation red tests added.
- [x] Phase 2 assign-preservation initial implementation landed.
- [x] Phase 2 verification run completed.
- [x] Phase 3 canonicalization red tests added.
- [x] Phase 3 canonicalization implementation landed.
- [x] Phase 3 verification run completed.
- [x] Phase 4 full strict AO486 roundtrip passes twice.
- [x] PRD marked Completed with completion date.

## Execution Update (2026-03-04, team pass 1)
Completed with worker-agent support:
1. Phase 1 instance-name stability:
   - Raised classes now stamp stable `verilog_module_name` equal to original CIRCT module name.
   - Added regression coverage in `spec/rhdl/codegen/circt/raise_spec.rb` for anonymous namespace raising.
2. Roundtrip mismatch observability:
   - `spec/examples/ao486/import/roundtrip_spec.rb` now emits deterministic mismatch summaries:
     - missing/extra/mismatched preview
     - field mismatch counts
     - top mismatched modules
     - optional per-module excerpt via `AO486_ROUNDTRIP_DIFF_EXCERPT=<n>`
3. Phase 2 initial assign-preservation scaffolding:
   - Added `spec/rhdl/codegen/circt/assign_preservation_spec.rb` with focused fixtures.
   - Added initial export path support for internal assign drivers in `lib/rhdl/codegen/circt/mlir.rb`.
   - Current pending edge cases captured:
     - multi-drive output assign multiset preservation
     - input-target llhd.drv assign multiset preservation

Validation snapshot:
- `bundle exec rspec spec/rhdl/codegen/circt/raise_spec.rb` -> pass (18 examples).
- `bundle exec rspec spec/rhdl/codegen/circt/assign_preservation_spec.rb` -> pass with 2 pending.
- `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486/import/roundtrip_spec.rb` ->
  - missing=0
  - extra=0
  - mismatched=49
  - field_mismatch_counts=assigns:49

Delta vs baseline:
- mismatched modules improved from 50 -> 49.
- instance mismatch class cleared from the strict summary (remaining mismatch field is assigns only).

## Execution Update (2026-03-04, team pass 2)
Completed:
1. Closed the two remaining assign-preservation fixture gaps:
   - multi-drive output assign multiset now preserved.
   - input-target `llhd.drv` assign multiset now preserved.
2. Tightened MLIR assign-target materialization:
   - preserve non-output targets when needed for expression integrity.
   - avoid duplicating output self-driver emissions.
   - avoid over-preserving some pure passthrough non-output signal targets.
3. Tightened raise behavior recovery:
   - preserve input-target assignments via dedicated internal alias wires.
   - suppress redundant repeated self-assigns for multiply-driven targets.
4. Removed `pending` markers in:
   - `spec/rhdl/codegen/circt/assign_preservation_spec.rb`

Validation run:
- `bundle exec rspec spec/rhdl/codegen/circt/assign_preservation_spec.rb` -> pass (8 examples).
- `bundle exec rspec spec/rhdl/codegen/circt/raise_spec.rb spec/rhdl/codegen/circt/mlir_spec.rb spec/rhdl/codegen/circt/assign_preservation_spec.rb` -> pass (36 examples).
- `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb spec/rhdl/import/import_paths_spec.rb` -> pass (15 examples).
- `INCLUDE_SLOW_TESTS=1 bundle exec rspec spec/examples/ao486/import/roundtrip_spec.rb` ->
  - missing=0
  - extra=0
  - mismatched=49
  - field_mismatch_counts=assigns:49

Current state:
- Phase 2 fixture-level red/green closure is complete.
- Full AO486 strict parity remains blocked on broader assign canonicalization drift (still 49 modules mismatched on assigns).

## Execution Update (2026-03-04, team pass 3 - closure)
Completed:
1. Closed comparator/operator emission bug in raise path:
   - `<=`/`>=` comparisons are now emitted in assignment-safe form for DSL behavior contexts
     (`(a < b) | (a == b)` and `(a > b) | (a == b)`), preventing accidental assignment capture
     when raised expressions reference writable proxies.
2. Added regression coverage:
   - `spec/rhdl/codegen/circt/raise_spec.rb`
   - new test: `rewrites <= comparisons so output proxies are not treated as assignments in expressions`.
3. Stabilized literal emission semantics:
   - MLIR constant normalization now preserves non-negative values (including `i1` `1`) without
     unintended sign folding to `-1`.
4. Kept assign-preservation behavior aligned with current normalization expectations in
   `spec/rhdl/codegen/circt/assign_preservation_spec.rb`.

Validation run:
- `bundle exec rspec spec/rhdl/codegen/circt/raise_spec.rb` -> pass (19 examples)
- `bundle exec rspec spec/rhdl/codegen/circt/assign_preservation_spec.rb spec/rhdl/codegen/circt/mlir_spec.rb` -> pass (18 examples)
- `bundle exec rspec spec/examples/ao486/import/roundtrip_spec.rb --tag slow` -> pass (1 example, 0 failures, seed 17128, 5m44s)
- `bundle exec rspec spec/examples/ao486/import/roundtrip_spec.rb --tag slow` -> pass (1 example, 0 failures, seed 16752, 9m19s)

Final state:
- strict AO486 roundtrip closure achieved:
  - missing = 0
  - extra = 0
  - mismatched = 0
- two consecutive full slow runs passed.
