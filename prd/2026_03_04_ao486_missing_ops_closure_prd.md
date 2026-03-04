# AO486 CIRCT Import Missing-Ops Closure PRD

## Status
Completed (2026-03-04)

## Context
AO486 tree import reports still show skipped/unsupported operations in `raise_diagnostics` and structural/behavior fallbacks during CIRCT -> RHDL raise. This blocks strict no-skip import quality and produces low-fidelity output in modules with array-heavy LLHD/core patterns.

Observed missing classes from `examples/ao486/tmp/ao486_import_report.json`:
1. Parser-skipped ops (`dbg.variable`, `comb.replicate`, `hw.array_get`, `hw.array_create`, `hw.bitcast`, `llhd.prb` attr-bearing forms, `llhd.sig` array forms, `llhd.sig.array_get`, attr-bearing `comb.mux`/`comb.extract`).
2. `comb.icmp` unsupported predicate fallback (`ceq` -> `eq`).
3. Variadic `comb.add` fallback.
4. `raise.structure` unsupported instance input connections.
5. `raise.behavior` placeholder emission for unresolved outputs.

## Goals
1. Eliminate all currently observed missing-op warnings for AO486 tree import in strict mode.
2. Enforce strict gate behavior in AO486 import workflow and report output.
3. Preserve existing CIRCT ownership boundary:
   - Verilog <-> CIRCT tooling remains external.
   - RHDL owns CIRCT <-> RHDL only.

## Non-Goals
1. Implementing generic full LLHD process semantics beyond currently imported shapes.
2. Replacing external CIRCT tooling with Ruby frontend/backend code.
3. Refactoring unrelated legacy/test infrastructure.

## Phased Plan (Red/Green)

### Phase 0: PRD + Report/Gate Scaffolding
Red:
1. Add failing tests asserting AO486 report includes machine-readable missing-op summary and strict gate fields.

Green:
1. Extend AO486 report payload with normalized missing-op summary and strict gate status.
2. Keep defaults backwards compatible where necessary except AO486 import strict gate policy.

Exit criteria:
1. Report contains deterministic summary and strict gate sections.

### Phase 1: Parser Closure (Scalar + Attr-bearing Ops)
Red:
1. Add failing import specs for:
   - `dbg.variable` (ignored metadata)
   - attr-bearing `comb.mux`, `comb.extract`, `llhd.prb`
   - `comb.replicate`
   - variadic `comb.add`
   - `comb.icmp ceq`

Green:
1. Extend parser normalization for inline attr dictionaries before type annotations.
2. Ignore `dbg.variable` lines without diagnostics.
3. Lower `comb.replicate` to concatenation expression.
4. Accept variadic `comb.add` via fold.
5. Support `ceq` (and `cne`) predicates without fallback warning.

Exit criteria:
1. No parser warnings for phase-1 op set.
2. No `comb.icmp` fallback warning for `ceq`/`cne`.

### Phase 2: Array + LLHD Array Op Closure
Red:
1. Add failing specs for `hw.array_create/get`, `hw.bitcast`, `llhd.sig` array, `llhd.sig.array_get`.

Green:
1. Add parser-internal array value model.
2. Lower array ops into existing CIRCT IR exprs:
   - array create
   - array get (literal and dynamic index)
   - bitcast int <-> array
   - llhd array signal/probe/get access paths

Exit criteria:
1. No parser warnings for AO486 array/LLHD array op set.

### Phase 3: Raise Structure/Behavior Hardening
Red:
1. Add failing raise specs for non-signal instance input expressions and structural-only output modules.

Green:
1. Add deterministic bridge-wire lowering for complex instance input expressions.
2. Remove placeholder output fallback when outputs are structurally driven.
3. Keep strict-mode error behavior for truly unresolved outputs.

Exit criteria:
1. `raise.structure` unsupported input connection warnings drop to zero for AO486 import.
2. `raise.behavior` placeholder warnings drop to zero.

### Phase 4: AO486 Strict Gate Productization
Red:
1. Add failing AO486 task/importer specs asserting strict gate default and blocking categories.

Green:
1. Enable strict import/raise by default in AO486 importer path.
2. Fail AO486 import when missing-op blocking categories remain.
3. Emit blocking category list in JSON report.

Exit criteria:
1. AO486 import default run is strict-gated and deterministic.

### Phase 5: Full Validation and Reported Completion
Red:
1. Add final acceptance checks against AO486 report category counts.

Green:
1. Run targeted and integration gates.
2. Re-import AO486 tree flow and verify zero blocking missing-op categories.

Exit criteria:
1. All targeted missing-op classes closed for AO486 report.
2. AO486 strict gate passes.

## Acceptance Criteria
1. AO486 import report has zero entries in blocking categories:
   - parser skipped ops for targeted set
   - `comb.icmp` predicate fallback
   - variadic `comb.add` fallback
   - `raise.structure` unsupported input connection
   - `raise.behavior` placeholder emission
2. Strict AO486 import succeeds with same workflow entrypoints.
3. Import/raise/unit specs for touched code are green.

## Risks and Mitigations
1. Risk: Array lowering semantics mismatch CIRCT bit ordering.
   - Mitigation: Add explicit index/bit-order tests for int<->array bitcast and array_get dynamic mux behavior.
2. Risk: Structural bridge wires alter naming and outputs.
   - Mitigation: Deterministic bridge naming and focused golden source assertions.
3. Risk: AO486 strict default breaks previously tolerated warnings.
   - Mitigation: Report-driven blocking categories, clear diagnostics, no silent fallback.

## Test Gates
1. `bundle exec rspec spec/rhdl/codegen/circt/import_spec.rb`
2. `bundle exec rspec spec/rhdl/codegen/circt/raise_spec.rb`
3. `bundle exec rspec spec/rhdl/cli/tasks/ao486_task_spec.rb`
4. `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb`
5. `bundle exec rspec spec/examples/ao486/import/parity_spec.rb`
6. `bundle exec rspec spec/rhdl/import/import_paths_spec.rb`

## Implementation Checklist
- [x] Phase 0: Add report summary + strict gate scaffolding with red/green tests.
- [x] Phase 1: Close scalar parser gaps (`dbg.variable`, attr-bearing ops, `replicate`, `ceq`, variadic add).
- [x] Phase 2: Implement array + LLHD array operation lowering.
- [x] Phase 3: Remove structure/behavior raise fallbacks via bridge wires and structural-drive detection.
- [x] Phase 4: Enforce AO486 strict-gate defaults in task/importer and report.
- [x] Phase 5: Re-run AO486 import and all touched test gates; update status to Completed.

## Completion Notes
1. Implemented parser coverage for all previously reported missing op classes in AO486 report:
   - `dbg.variable` ignored as metadata.
   - attr-bearing `comb.mux`, `comb.extract`, `llhd.prb`.
   - `comb.replicate`.
   - variadic `comb.add`.
   - `comb.icmp` `ceq`/`cne`.
   - `hw.array_create/get`, `hw.bitcast`, `llhd.sig` array, `llhd.sig.array_get`.
2. Added forward SSA reference resolution during import so out-of-order SSA uses (for example `%305` used before definition) are resolved before raise.
3. Hardened raise structure/behavior:
   - expression-valued instance inputs now lower via deterministic bridge wires.
   - structural output drives are recognized as valid in strict mode.
4. AO486 report now includes:
   - `missing_ops_summary`
   - `strict_gate` with `passed` and `blocking_categories`
5. AO486 task now enforces strict gate failure semantics:
   - import fails when blocking categories remain, even if partial output/report is written.
6. AO486 importer now raises with `strict: true` by default.

## Final Validation
1. `bundle exec rspec spec/rhdl/codegen/circt/import_spec.rb` -> pass
2. `bundle exec rspec spec/rhdl/codegen/circt/raise_spec.rb` -> pass
3. `bundle exec rspec spec/rhdl/cli/tasks/ao486_task_spec.rb` -> pass
4. `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb` -> pass
5. `bundle exec rspec spec/examples/ao486/import/parity_spec.rb` -> pass
6. `bundle exec rspec spec/rhdl/import/import_paths_spec.rb` -> pass
