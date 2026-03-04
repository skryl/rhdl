# Import Pretty-Print + RuboCop PRD

## Status
Completed (2026-03-04)

## Context
Imported CIRCT->RHDL files can contain dense behavior assignments and long logic lines that are difficult to review. We also need a repository-wide RuboCop baseline and automatic formatting for imported RHDL outputs.

## Goals
1. Add RuboCop as a first-class dependency/tool for this repository.
2. Add a standard RuboCop configuration for repo-wide usage.
3. Pretty-print long generated logic assignments (especially in `behavior` blocks).
4. Auto-format imported RHDL files during import workflows.

## Non-Goals
1. Repo-wide offense cleanup in this change.
2. Reformatting all existing hand-authored files.

## Phased Plan (Red/Green)
### Phase 1: Red tests for generated formatting behavior
Red:
1. Add failing raise spec that expects long behavioral logic emission to be multiline/pretty.
2. Add failing import-task spec that asserts import raise path requests formatting.

Green:
1. Implement long-expression pretty emission in CIRCT raise output.
2. Thread formatting flag through import flow.

Exit criteria:
1. New specs pass and no regressions in CIRCT raise/import task suites.

### Phase 2: RuboCop toolchain wiring
Red:
1. Add failing environment check/spec coverage as needed for RuboCop-backed formatting hook behavior.

Green:
1. Add RuboCop dependency and lockfile updates.
2. Add `.rubocop.yml` with standard baseline rules.
3. Add CIRCT raise post-write formatter hook using RuboCop auto-correct for generated files.

Exit criteria:
1. Generated import files are auto-formatted through RuboCop path.
2. Formatter failures are surfaced as diagnostics (not silent).

### Phase 3: Import path integration + validation
Red:
1. Ensure both generic `rhdl import` and AO486 import paths fail tests until formatting hook is enabled.

Green:
1. Enable formatting for `rhdl import` raised output.
2. Enable formatting for AO486 importer raised output.
3. Update CLI docs if behavior changes are user-visible.

Exit criteria:
1. Targeted test gates are green.
2. Import output now emits prettified logic and rubocop-normalized formatting.

## Exit Criteria Per Phase
1. Phase 1: Formatting behavior tests are green.
2. Phase 2: RuboCop config/dependency + formatter hook are landed and validated.
3. Phase 3: All import entry points format generated files and tests pass.

## Acceptance Criteria
1. RuboCop is available in repo tooling and config is present.
2. Long generated logic in behavior/sequential assignments is pretty-printed.
3. Import flows auto-format generated DSL files.
4. Diagnostics clearly report formatter failures.

## Risks and Mitigations
1. Risk: RuboCop unavailable in a runtime environment.
   - Mitigation: emit explicit formatting diagnostics when formatter cannot run.
2. Risk: Expression pretty-print can alter semantics.
   - Mitigation: preserve parenthesized semantics and validate with existing raise/import specs.
3. Risk: RuboCop rule drift across versions.
   - Mitigation: lock dependency via `Gemfile.lock` and keep a local `.rubocop.yml`.

## Implementation Checklist
- [x] PRD created.
- [x] Phase 1 Red tests added.
- [x] Phase 1 Green implementation complete.
- [x] Phase 2 RuboCop dependency/config landed.
- [x] Phase 2 formatter hook landed.
- [x] Phase 3 import integrations updated.
- [x] Phase 3 test gates green.

## Completion Notes
1. Added RuboCop tooling baseline:
   - `rubocop` development dependency in `rhdl.gemspec` (+ lockfile update).
   - root `.rubocop.yml` with standard default cops and repo exclusions, including `examples/*/reference/**/*`.
2. Implemented long-logic pretty emission in CIRCT raise:
   - assignment emitter now wraps long expressions in multi-line form for behavior and sequential logic.
   - preserved valid Ruby parsing by emitting binary/mux continuation operators on preceding lines.
3. Added import-time auto-format:
   - CIRCT raise `to_dsl(..., format: true)` now runs RuboCop auto-correct in layout-only mode.
   - output is suppressed during formatting and failures surface as `raise.format` diagnostics.
4. Wired import entry points to format generated files:
   - `rhdl import` task now passes `format: true`.
   - AO486 importer now passes `format: true`.
5. Added regression coverage:
   - long behavior logic pretty-print test.
   - import task asserts `format: true` path.
   - format-mode test ensures `<=` DSL assignment statements are preserved and generated files remain loadable.
