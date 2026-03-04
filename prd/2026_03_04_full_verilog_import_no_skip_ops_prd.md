# Full Verilog Import No-Skip-Ops PRD

## Status
Completed (2026-03-04)

## Context
RHDL has a CIRCT import/raise path that currently permits unsupported operation lines to be skipped with warnings. This can produce placeholder behavior and low-fidelity imported designs for larger projects (notably LLHD-heavy outputs). We need a full-project Verilog import path that does not silently skip operations.

This PRD defines a strict, phased migration to no-skip semantics while preserving the existing CIRCT tooling boundary:
- Verilog -> CIRCT remains external (LLVM/CIRCT tooling).
- CIRCT -> RHDL and RHDL -> CIRCT remain RHDL-owned.

## Goals
1. Deliver full-project dependency-closure import for synthesizable RTL.
2. Eliminate silent op skipping in successful imports.
3. Enforce deterministic module-level failure reporting for unsupported operations.
4. Emit semantic-fidelity-first RHDL output.
5. Preserve partial-output + non-zero-exit behavior on mixed success/failure projects.

## Non-Goals
1. Testbench/non-synthesizable import in scope 1.
2. Auto-stubbing unresolved internal modules.
3. Replacing CIRCT frontend/backend tooling with Ruby implementations.

## Locked Decisions
1. Semantic strategy: lossless AST/import model.
2. Failure policy: partial output + fail (non-zero exit if any module fails).
3. Scope 1 coverage: synthesizable RTL only.
4. External handling: explicit extern boundaries only.
5. Output level: semantic fidelity first, high-level raise only when equivalence is provable.
6. Scope granularity: full project closure in scope 1.

## Phased Plan (Red/Green)
### Phase 0: Contracts + Op Census Baseline
Red:
1. Add failing tests for strict no-skip import contract.
2. Add failing tests for op-census coverage utility on CIRCT MLIR input.

Green:
1. Add strict-mode scaffolding to CIRCT import APIs without changing default behavior yet.
2. Add op-census utility to produce operation frequency maps for fixture corpora.

Exit criteria:
1. Strict-mode tests pass.
2. Op-census tests pass.
3. Existing non-strict import tests remain green.

### Phase 1: Lossless MLIR Structural Parsing
Red:
1. Add failing tests for nested region/block parsing and multiline op reconstruction.

Green:
1. Replace line-oriented skip-prone parser path with structured MLIR parser model.

Exit criteria:
1. No structural truncation on nested process regions.
2. Fixture corpus parses with zero unintended early module termination.

### Phase 2: Full Op Handling for In-Scope Dialects
Red:
1. Add failing handler tests per encountered op family (from census).

Green:
1. Implement handlers for in-scope ops (including LLHD process primitives needed by synthesizable flows).
2. Convert unhandled ops to explicit module failures in strict mode.

Exit criteria:
1. No successful module contains unsupported-op skips.
2. Unsupported ops are reported as deterministic module failures.

### Phase 3: Strict Raise (No Placeholder Fallback)
Red:
1. Add failing tests that reject placeholder output generation in successful modules.

Green:
1. Remove successful-path placeholder behavior.
2. Convert unresolved behavior to explicit failure classification.

Exit criteria:
1. Successful modules emit semantically backed assignments/processes only.

### Phase 4: Project Closure + Extern Policy Enforcement
Red:
1. Add failing tests for dependency closure and extern allowlist handling.

Green:
1. Implement full closure import for selected tops.
2. Enforce explicit extern declarations; unresolved non-extern modules fail.

Exit criteria:
1. Full closure output written for reachable successful modules.
2. Non-extern unresolved modules fail deterministically.

### Phase 5: CLI/API Productization + Reports + Parity Gates
Red:
1. Add failing CLI/API integration tests for strict behavior, exit codes, and report schema.

Green:
1. Wire strict flow to `rhdl import` project mode.
2. Emit module-level failure/coverage reports.
3. Run deterministic behavioral parity checks for successful modules/tops.

Exit criteria:
1. End-to-end strict project import is stable and documented.

## Exit Criteria Per Phase
1. Phase 0: strict contract + op census scaffold green.
2. Phase 1: structural parser handles nested regions/blocks correctly.
3. Phase 2: op handling coverage reaches full in-scope set or explicit failures.
4. Phase 3: no placeholder behavior in successful raised modules.
5. Phase 4: full-project closure and extern policy are enforced.
6. Phase 5: CLI/API + reports + parity gates are green.

## Acceptance Criteria
1. No silent skip semantics for successful imports.
2. Unsupported ops are surfaced as explicit module failures with diagnostics.
3. Full-project closure works for synthesizable scope-1 inputs.
4. Output remains semantic-fidelity-first.
5. CLI exits non-zero on partial failures while writing successful modules and reports.

## Risks and Mitigations
1. Risk: CIRCT output dialect mix varies by project.
   - Mitigation: op-census-driven handler backlog and strict explicit-failure policy.
2. Risk: parser regressions on nested regions.
   - Mitigation: dedicated structural fixtures and regression gates.
3. Risk: performance regressions from strict bookkeeping.
   - Mitigation: benchmark import on AO486 and representative medium fixtures each phase.

## Testing Gates
1. `bundle exec rspec spec/rhdl/codegen/circt/import_spec.rb spec/rhdl/codegen/circt/api_spec.rb`
2. `bundle exec rspec spec/rhdl/codegen/circt/raise_spec.rb`
3. `bundle exec rspec spec/rhdl/cli/tasks/import_task_spec.rb`
4. `bundle exec rspec spec/rhdl/import/import_paths_spec.rb`
5. `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb`
6. `bundle exec rspec spec/examples/ao486/import/parity_spec.rb`

If a gate cannot run locally, record exact command and reason.

## Implementation Checklist
- [x] PRD created.
- [x] Phase 0 Red: add strict-mode and op-census failing tests.
- [x] Phase 0 Green: implement strict-mode API scaffolding and op-census helper.
- [x] Phase 0 Exit: targeted + immediate regression gates green.
- [x] Phase 1 Red/Green.
- [x] Phase 2 Red/Green.
- [x] Phase 3 Red/Green.
- [x] Phase 4 Red/Green.
- [x] Phase 5 Red/Green.

## Execution Update (2026-03-04, Phase 0 start)
Started Phase 0 by adding strict no-skip contract scaffolding and op-census helper/tests in CIRCT import APIs, keeping default behavior non-strict during this phase to avoid destabilizing existing import flows.

## Execution Update (2026-03-04, Phase 0 complete)
Completed Phase 0 red/green with the following landed changes:
1. Added strict import contract option:
   - `RHDL::Codegen.import_circt_mlir(text, strict: false)`
   - `RHDL::Codegen::CIRCT::Import.from_mlir(text, strict: false)`
2. In strict mode, unsupported parse paths now escalate from warning to error for:
   - unsupported parser lines
   - unsupported `seq.compreg` forms
   - invalid `comb.concat` arity/type forms
3. Added `RHDL::Codegen::CIRCT::Import.op_census(text)` helper for operation frequency baselining.
4. Added/updated tests:
   - `spec/rhdl/codegen/circt/import_spec.rb`:
     - strict-mode failure on unsupported op line
     - op-census behavior
   - `spec/rhdl/codegen/circt/api_spec.rb`:
     - strict-mode API contract coverage

Validation gates run:
1. `bundle exec rspec spec/rhdl/codegen/circt/import_spec.rb spec/rhdl/codegen/circt/api_spec.rb` -> pass (`35 examples, 0 failures`)
2. `bundle exec rspec spec/rhdl/import/import_paths_spec.rb` -> pass (`5 examples, 0 failures`)
3. `bundle exec rspec spec/examples/ao486/import/system_importer_spec.rb` -> pass (`8 examples, 0 failures`)

## Execution Update (2026-03-04, Phases 1-2 complete)
Completed structural/parser and op-coverage phases with red/green tests and fixes:
1. Structural parsing:
   - Added nested `llhd.process` region test coverage to prevent premature `hw.module` termination.
   - Added module span validation (`module_spans`) coverage.
2. Op handling expansion:
   - Added strict tests for variadic `comb.or`/`comb.and`.
   - Added strict tests for `comb.icmp` operands carrying inline attribute dictionaries.
   - Added strict tests for untyped boolean `hw.constant true/false`.
   - Parser now supports:
     - variadic folding for `comb.and/or/xor`
     - robust operand token normalization for inline attr/loc payloads
     - untyped boolean constants as width-1 literals
3. Strict corpus verification:
   - AO486 normalized core MLIR strict import verified with zero diagnostics.

## Execution Update (2026-03-04, Phase 3 complete)
Completed strict-raise behavior hardening:
1. Added red tests asserting strict raise refuses placeholder fallback for missing output assignments.
2. Added red tests asserting strict raise fails on unsupported expression lowering (`IR::MemoryRead`).
3. Implemented strict raise mode in `CIRCT::Raise`:
   - `to_sources(..., strict:)`, `to_dsl(..., strict:)`, `to_components(..., strict:)`
   - strict mode emits errors and refuses placeholder emission for unresolved behavior.
   - non-strict mode preserves legacy warning+placeholder behavior for compatibility.
4. Propagated strict options through public API wrappers:
   - `RHDL::Codegen.raise_circt_sources`
   - `RHDL::Codegen.raise_circt`
   - `RHDL::Codegen.raise_circt_components`

## Execution Update (2026-03-04, Phase 4 complete)
Completed project-closure and extern policy enforcement:
1. Added red/green tests for unresolved instance targets in strict top-closure mode.
2. Added extern allowlist tests to permit explicit unresolved boundaries.
3. Extended import API:
   - `RHDL::Codegen.import_circt_mlir(text, strict:, top:, extern_modules:)`
   - `CIRCT::Import.from_mlir(text, strict:, top:, extern_modules:)`
4. Implemented closure checks:
   - reachability from selected top(s)
   - deterministic `import.closure` diagnostics for unresolved non-extern instance targets
   - top-not-found closure diagnostics

## Execution Update (2026-03-04, Phase 5 complete)
Completed strict CLI/API productization, report emission, and parity gate:
1. `rhdl import` productization:
   - added CLI options:
     - `--[no-]strict`
     - `--extern NAME` (repeatable)
     - `--report FILE`
   - import task now runs strict import first, then raise on imported modules.
2. Reporting:
   - emits JSON report (`<out>/import_report.json` default or `--report` path).
   - includes success flag, strict/top/extern config, op census, module spans, per-module import diagnostics, global import/raise diagnostics.
3. Partial output + failure semantics:
   - import task now raises non-zero on any import or raise errors while still writing generated outputs/report.
4. Parity gate:
   - AO486 parity spec executed and passed.

Validation gates run:
1. `bundle exec rspec spec/rhdl/codegen/circt/import_spec.rb spec/rhdl/codegen/circt/api_spec.rb spec/rhdl/codegen/circt/raise_spec.rb spec/rhdl/cli/tasks/import_task_spec.rb spec/rhdl/import/import_paths_spec.rb spec/examples/ao486/import/system_importer_spec.rb` -> pass (`76 examples, 0 failures`)
2. `bundle exec rspec spec/examples/ao486/import/parity_spec.rb` -> pass (`1 example, 0 failures`)
