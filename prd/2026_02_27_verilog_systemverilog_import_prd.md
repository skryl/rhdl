# Verilog/SystemVerilog Project Import to RHDL PRD

## Status
Proposed (2026-02-27)

## Context
RHDL currently has strong Verilog export flows but no project-scale Verilog/SystemVerilog import path. The target capability is to ingest an existing RTL project and emit a standalone RHDL project that preserves module naming and hierarchy.

Decisions already locked for this PRD:
- Output is pure-RHDL for all converted modules.
- Input language target is synthesizable Verilog-2001 plus a defined SystemVerilog RTL subset.
- Frontend parsing/elaboration uses external tooling (Verilator-based).
- Conversion writes partial output when unsupported modules exist, but command exits non-zero.
- Differential simulation checks run automatically (Icarus first, Verilator fallback) against all detected tops by default.
- Input supports both filelist mode and directory auto-scan mode.
- Converted output includes vendored HDL sources for portability and replayability.

## Goals
- Provide a project-level conversion workflow from Verilog/SystemVerilog to RHDL.
- Preserve module names, top detection behavior, and hierarchy where supported.
- Emit one Ruby file per converted module in a runnable RHDL project scaffold.
- Generate high-fidelity diagnostics for unsupported constructs and failed modules.
- Run automated differential checks between original RTL and converted RHDL-exported RTL.
- Expose both CLI and Ruby API entrypoints.

## Non-Goals
- Full IEEE SystemVerilog feature coverage in v1.
- Conversion of verification/testbench code in v1.
- Silent fallback to wrappers/blackboxes for unsupported modules.
- Formal equivalence in v1.
- Replacing existing export/simulation flows unrelated to import.

## Public Interfaces and Output Contract
- CLI: `rhdl import`.
- API: `RHDL::Import.project(...)`.
- Result object: `RHDL::Import::Result`.
- Output structure:
  - `<out>/lib/<project_slug>.rb`
  - `<out>/lib/<project_slug>/modules/**/<module>.rb`
  - `<out>/vendor/source_hdl/**`
  - `<out>/reports/import_report.json`
  - `<out>/reports/differential/**`
  - `<out>/rhdl_import.yml`

CLI options in scope for v1:
- Inputs: `--filelist`, `--src`, `--exclude`, `-I/--incdir`, `-D/--define`.
- Top selection: `--top` (repeatable) with default "all detected tops".
- Check controls: `--check`, `--no-check`, `--check-scope`, `--check-backend`, `--vectors`, `--seed`.
- Reporting: `--report`, `--keep-temp`.

Exit behavior in scope for v1:
- `0`: full conversion + checks pass.
- non-zero: partial conversion, check failures, or tool/internal failures.

## Supported v1 Language Subset
- Module declarations, ANSI ports, parameters/localparams.
- Net/reg/logic declarations and vector ranges.
- Continuous assigns.
- Module instantiation with named port mapping and parameter overrides.
- Procedural blocks: `always_comb`, `always @*`, `always_ff`, `always @(posedge/negedge ...)`.
- Statements: begin/end, if/else, case/default, blocking/non-blocking assignment.
- Expressions: literals, unary/binary ops, comparisons, shifts, ternary, concat/replication, bit/part select.

Out-of-scope constructs fail conversion for affected modules with diagnostics.

## Phased Plan (Red/Green/Refactor) with Agent Tranches

### Phase 0: Contracts, PRD lock, and failing tests
Red:
- Add failing specs for CLI dispatch, API entrypoint, report schema, and exit semantics.

Green:
- Land scaffolding for `rhdl import`, `RHDL::Import.project`, and result/report skeleton.

Refactor:
- Normalize options parsing and shared result serialization.

Agent tranches:
- Tranche A (Core contract): define API/result types and report schema tests.
- Tranche B (CLI contract): add command help/dispatch tests and command skeleton wiring.
- Tranche C (Test harness): add fixture helpers and common assertions for report/exit behavior.

Exit criteria:
- Contract tests are present and green with stable skeleton behavior.

### Phase 1: DSL/codegen readiness for imported RTL shapes
Red:
- Add failing DSL/codegen specs for parameterized widths, preserved module names, and procedural assignment nuances needed by importer output.

Green:
- Implement minimal DSL/codegen extensions required to faithfully emit supported imported constructs.

Refactor:
- Consolidate duplicated width/name handling and keep backward compatibility for existing paths.

Agent tranches:
- Tranche A (DSL semantics): parameterized width/range support and identifier preservation behavior.
- Tranche B (Procedural emission): blocking/non-blocking assignment rendering and process emission consistency.
- Tranche C (Regression shield): targeted regressions for existing export users.

Exit criteria:
- Import-targeted DSL/codegen tests pass without regressions in existing DSL/export tests.

### Phase 2: Source ingestion + Verilator frontend adapter
Red:
- Add failing tests for filelist parsing, auto-scan/exclude behavior, define/include handling, and deterministic frontend invocation.

Green:
- Implement source resolver and Verilator JSON frontend adapter with location metadata and normalized payload output.

Refactor:
- Isolate tool invocation, environment, and temp-artifact handling behind a single adapter.

Agent tranches:
- Tranche A (Input resolver): filelist parser, autoscan mode, exclusion policy.
- Tranche B (Tool adapter): Verilator invocation, JSON/meta capture, command reproducibility.
- Tranche C (Metadata): source map, normalized diagnostics span mapping.

Exit criteria:
- Fixture projects can be ingested in both input modes and produce stable normalized frontend output.

### Phase 3: Import IR, module translator, dependency pruning, and project writer
Red:
- Add failing translator tests for combinational, sequential, hierarchical, and parameterized fixtures.
- Add failing tests for unsupported-construct diagnostics and dependency-pruned output behavior.

Green:
- Build Import IR, AST mappers, module translators, hierarchy graph/top detection, and writer for one-file-per-module output.
- Implement partial-output behavior with non-zero exit when failures exist.

Refactor:
- Split mappers by node family and centralize diagnostics aggregation.

Agent tranches:
- Tranche A (IR + mapper): normalized Import IR and expression/statement/declaration mappers.
- Tranche B (Module translation): RHDL emitter for module bodies, ports, instances, parameters.
- Tranche C (Graph + writer): dependency graph, top detection, pruning, and filesystem writer/report emission.

Exit criteria:
- Supported fixtures fully convert into runnable RHDL project scaffolds.
- Unsupported fixtures produce detailed diagnostics and correct partial-output semantics.

### Phase 4: Differential check runner (auto-run)
Red:
- Add failing tests for backend selection (`iverilog` then `verilator`), check orchestration, mismatch diagnostics, and check-related exit semantics.

Green:
- Implement deterministic vector generation, original-vs-converted execution harnesses, comparison logic, and check reports.

Refactor:
- Separate backend adapters from stimulus generation and result comparison.

Agent tranches:
- Tranche A (Stimulus): deterministic vector generator and per-top harness templates.
- Tranche B (Backends): Icarus adapter with Verilator fallback adapter.
- Tranche C (Comparator/report): signal/cycle diff engine and report materialization.

Exit criteria:
- Passing fixtures show green checks for all detected tops.
- Mismatch fixtures emit deterministic, actionable failure reports.

### Phase 5: Productization, docs, and stabilization
Red:
- Add failing integration tests for end-to-end CLI behavior in success, partial-convert, and check-failure cases.

Green:
- Finalize CLI UX/messages, documentation (`docs/import.md`, README, CLI reference), and usage examples.

Refactor:
- Normalize error taxonomy and final summary output.

Agent tranches:
- Tranche A (UX + CLI polish): user-visible output, help text, exit summary.
- Tranche B (Docs): README/docs/CLI reference updates and consistency checks.
- Tranche C (Hardening): broader lib regression passes and flaky-case cleanup.

Exit criteria:
- End-to-end flows and docs align with implemented behavior.

## Exit Criteria Per Phase
- Phase 0: Contract-level tests and schema are green.
- Phase 1: DSL/codegen import-required behavior is green with no critical regressions.
- Phase 2: Ingestion works for both input modes with deterministic frontend payload.
- Phase 3: Converter emits correct project output with accurate partial-failure handling.
- Phase 4: Differential checks run automatically and produce deterministic pass/fail artifacts.
- Phase 5: CLI/docs stabilized and integration/regression checks are green.

## Acceptance Criteria (Full Completion)
- `rhdl import` converts supported project RTL into standalone RHDL project output.
- `RHDL::Import.project(...)` provides equivalent functionality programmatically.
- One-file-per-module output is generated with preserved naming and usable loader structure.
- Partial conversion writes successful modules, reports failures, and exits non-zero.
- Differential checks run automatically on all detected tops by default with reproducible results.
- Documentation and CLI help accurately reflect final behavior and options.

## Risks and Mitigations
- Risk: Verilator JSON AST/version drift affects parser assumptions.
  - Mitigation: adapter version checks, contract tests on fixture AST snapshots, explicit unsupported-node handling.
- Risk: Parameter preservation is lossy for some elaborated forms.
  - Mitigation: preserve symbolic params where representable; emit precise diagnostics when freezing would change behavior.
- Risk: Differential checks are slow on large tops.
  - Mitigation: deterministic bounded vectors, per-top timeouts, and explicit `--no-check` escape hatch.
- Risk: Unsupported constructs can cascade dependency failures.
  - Mitigation: dependency-pruning classification (`unsupported`, `failed_dependency`, `tool_failure`) in reports.
- Risk: Existing export/sim behavior regresses while extending DSL/codegen.
  - Mitigation: targeted regression suites in each phase and conservative refactors post-green.

## Testing Gates
1. Unit/op-level tests for import parser, mapper, translator, and DSL/codegen extensions.
2. Integration tests for CLI/API conversion flows, output layout, and diagnostics/report schemas.
3. Differential simulation checks across supported tops and mismatch fixtures.
4. Broader lib regression checks (`spec:lib`) and focused command/task checks for touched areas.

If any gate cannot run locally, capture the exact command and reason.

## Implementation Checklist
- [ ] Phase 0 complete: contracts and scaffolding are locked and green.
- [ ] Phase 1 complete: DSL/codegen supports import-required output semantics.
- [ ] Phase 2 complete: ingestion + frontend adapter stable for both input modes.
- [ ] Phase 3 complete: translator/writer + partial-output behavior implemented.
- [ ] Phase 4 complete: automatic differential checker integrated and green.
- [ ] Phase 5 complete: CLI/docs/productization and stabilization finished.

## Default Execution Topology (Tranches)
- Each phase is executed in 3 coordinated tranches (A/B/C) to enable parallel delivery.
- Tranche A owns semantic/model correctness for the phase.
- Tranche B owns interfaces/integration for the phase.
- Tranche C owns fixtures, diagnostics quality, and regression hardening for the phase.
- Phase completion requires all tranche exit conditions met and merged.
