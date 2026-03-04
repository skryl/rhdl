# CIRCT Import Path Round-Trip Validation PRD

## Status
Completed (2026-03-03)

## Context
RHDL now routes execution/codegen through CIRCT IR, but import-path testing is still fragmented across `codegen/circt` and CLI task specs. We need one focused import suite that explicitly validates the required path matrix:

1. Verilog -> CIRCT
2. CIRCT -> RHDL
3. Verilog -> CIRCT -> RHDL
4. CIRCT -> RHDL -> CIRCT
5. Verilog -> CIRCT -> RHDL -> CIRCT -> Verilog

For same-type round trips (CIRCT->...->CIRCT and Verilog->...->Verilog), tests must prove semantic retention. For RHDL targets, tests must enforce highest-available DSL raising (no fallback/degrade raise diagnostics).

## Goals
1. Add a dedicated import-path integration suite under `spec/rhdl/import`.
2. Cover all five required transformation paths.
3. Verify same-type semantic parity using:
   - normalized CIRCT-imported semantic AST signatures
   - behavioral simulation parity for source vs transformed Verilog
4. Enforce high-level RHDL raising quality when RHDL is the target.
5. Keep Verilog<->CIRCT conversion delegated to LLVM/CIRCT tooling only.

## Non-Goals
1. Re-implement Verilog parsing/export in Ruby.
2. Expand unsupported language coverage in the importer.
3. Change CIRCT lowering/runtime architecture.
4. Replace existing import/task specs outside this focused path suite.

## Phased Plan (Red/Green)
### Phase 1: Test Harness + Fixture Baseline
Red:
- Add failing skeleton for `spec/rhdl/import/import_paths_spec.rb` and fixture helpers.
- Add tool-gating checks for `circt-translate`, MLIR export tool (`firtool` or `circt-translate`), and `iverilog/vvp` for semantic simulation.

Green:
- Implement reusable spec-local helpers for:
  - Verilog->MLIR tooling invocation
  - MLIR->Verilog tooling invocation
  - CIRCT semantic signature extraction
  - behavioral simulation comparison

Exit criteria:
- New spec file exists with helper scaffolding and can run without crashes.

### Phase 2: Path Coverage + RHDL-Level Assertions
Red:
- Add failing examples for required paths 1/2/3.
- Add failing assertions for RHDL target quality.

Green:
- Implement path tests for:
  - Verilog -> CIRCT
  - CIRCT -> RHDL
  - Verilog -> CIRCT -> RHDL
- Enforce no degrade diagnostics (`raise.behavior`, `raise.expr`, `raise.memory_read`, `raise.case`, `raise.sequential`) when RHDL is a target.
- Assert raised sources contain high-level DSL constructs (`behavior`, `sequential`, structure where relevant).

Exit criteria:
- Paths 1/2/3 are green and quality assertions are enforced.

### Phase 3: Same-Type Semantic Parity
Red:
- Add failing semantic parity checks for paths 4 and 5.

Green:
- CIRCT round-trip (`CIRCT -> RHDL -> CIRCT`):
  - compare normalized CIRCT semantic signatures
  - compare behavioral outputs after exporting both source/round-tripped MLIR to Verilog
- Verilog round-trip (`Verilog -> CIRCT -> RHDL -> CIRCT -> Verilog`):
  - parse input/output Verilog through CIRCT import and compare normalized semantic signatures
  - compare behavioral simulation outputs on shared vectors

Exit criteria:
- Both same-type paths pass AST+behavior parity checks.

### Phase 4: Stabilization + Broader Gate
Red:
- Validate integration with existing CIRCT/import suites.

Green:
- Run new suite + existing related suites:
  - `spec/rhdl/import/import_paths_spec.rb`
  - `spec/rhdl/codegen/circt/import_spec.rb`
  - `spec/rhdl/codegen/circt/raise_spec.rb`
  - `spec/rhdl/codegen/circt/tooling_spec.rb`
  - `spec/rhdl/cli/tasks/import_task_spec.rb`

Exit criteria:
- New and adjacent import/circt suites are green.

## Exit Criteria Per Phase
1. Phase 1: harness/helpers in place and runnable.
2. Phase 2: paths 1/2/3 + RHDL quality checks green.
3. Phase 3: paths 4/5 semantic parity checks green.
4. Phase 4: targeted regression gate green.

## Acceptance Criteria (Full Completion)
1. `spec/rhdl/import/import_paths_spec.rb` exists and covers all five required paths.
2. Same-type round trips include semantic checks (normalized AST + behavior parity).
3. RHDL-target path checks fail on degrade/fallback raise diagnostics.
4. Tooling usage for Verilog<->CIRCT remains external (`circt-translate`/`firtool`).
5. PRD status moved to `Completed` only after all gates pass.

## Risks and Mitigations
- Risk: Tool availability differs locally/CI.
  - Mitigation: explicit tool-gated examples with clear skip reasons; CI already installs deps via `rake deps:install`.
- Risk: AST comparison too strict across export formatting/normalization.
  - Mitigation: compare normalized semantic signatures, not raw textual MLIR/Verilog trees.
- Risk: Behavioral parity flakiness due nondeterministic vectors.
  - Mitigation: deterministic fixed test vectors.

## Testing Gates
1. `bundle exec rspec spec/rhdl/import/import_paths_spec.rb`
2. `bundle exec rspec spec/rhdl/codegen/circt/import_spec.rb spec/rhdl/codegen/circt/raise_spec.rb spec/rhdl/codegen/circt/tooling_spec.rb`
3. `bundle exec rspec spec/rhdl/cli/tasks/import_task_spec.rb`

## Execution Update (2026-03-03)
- Added `spec/rhdl/import/import_paths_spec.rb` with explicit coverage for:
  - Verilog -> CIRCT
  - CIRCT -> RHDL
  - Verilog -> CIRCT -> RHDL
  - CIRCT -> RHDL -> CIRCT
  - Verilog -> CIRCT -> RHDL -> CIRCT -> Verilog
- Implemented same-type semantic checks:
  - normalized semantic AST signatures
  - behavioral parity via `iverilog` simulation.
- Implemented RHDL-target quality checks:
  - fail on degrade diagnostics (`raise.behavior`, `raise.expr`, `raise.memory_read`, `raise.case`, `raise.sequential`).
- Verilog import bridge for core-dialect raising:
  - `circt-translate --import-verilog` output is Moore dialect.
  - tests lower Moore to core CIRCT with:
    - `circt-opt --convert-moore-to-core --llhd-sig2reg --canonicalize`
  - this preserves delegation to LLVM/CIRCT tooling.
- Validation:
  - `bundle exec rspec spec/rhdl/import/import_paths_spec.rb` -> `5 examples, 0 failures`
  - `bundle exec rspec spec/rhdl/codegen/circt/import_spec.rb spec/rhdl/codegen/circt/raise_spec.rb spec/rhdl/codegen/circt/tooling_spec.rb spec/rhdl/cli/tasks/import_task_spec.rb spec/rhdl/import/import_paths_spec.rb` -> `52 examples, 0 failures`

## Implementation Checklist
- [x] PRD created.
- [x] Phase 1 red/green complete.
- [x] Phase 2 red/green complete.
- [x] Phase 3 red/green complete.
- [x] Phase 4 red/green complete.
- [x] Acceptance criteria all satisfied.
