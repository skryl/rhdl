# 2026_03_04_sim_entrypoint_hard_cutover_prd

## Status
In Progress

## Context
The repository has completed simulator backend path migration to `lib/rhdl/sim/native/*`, but runtime API ownership and namespace usage are still inconsistent:
1. Runtime sim entrypoint still exists under `RHDL::Codegen.gate_level`.
2. Large portions of code/spec/docs still reference legacy namespaces (`RHDL::Export::*`, `RHDL::Codegen::Structure::*`, `RHDL::Export::IR::*`).
3. Some CLI paths are broken or stale (for example gate diagram single-component path uses `RHDL::Gates::Lower`).
4. Shared task location policy is inconsistent for AO486 task loading.

User requirements:
1. Simulation entrypoint should be under `RHDL::Sim`, not `RHDL::Codegen`.
2. Canonical simulator implementations are under `lib/rhdl/sim`.
3. Execute cleanup via PRD-driven phased implementation.
4. Run full test suite including slow tests after implementation.

## Goals
1. Introduce canonical runtime sim facade `RHDL::Sim.gate_level` and remove `RHDL::Codegen.gate_level`.
2. Hard-cut all legacy runtime/codegen namespaces to canonical names:
   - Netlist lowering: `RHDL::Codegen::Netlist::*`
   - CIRCT IR nodes: `RHDL::Codegen::CIRCT::IR::*`
   - Runtime simulation: `RHDL::Sim::*`
3. Fix CLI callsites and broken diagram gate-level path.
4. Normalize shared task placement by moving AO486 task to `lib/rhdl/cli/tasks`.
5. Update docs and hygiene checks to prevent namespace regressions.
6. Run full specs with slow tests enabled.

## Non-goals
1. Changing simulator runtime semantics/performance.
2. Changing native backend wire protocol/FFI behavior.
3. Keeping backwards compatibility aliases or stubs for removed legacy namespaces.

## Phased Plan

### Phase 1: Sim Facade Ownership Cutover (Red/Green)
Red:
1. Add/adjust specs to assert canonical sim facade (`RHDL::Sim.gate_level`) behavior.
2. Add failing checks that detect legacy entrypoint usage in active code.

Green:
1. Implement `RHDL::Sim.gate_level(components, backend:, lanes:, name:)` under `lib/rhdl/sim` load path.
2. Move backend normalization logic from `RHDL::Codegen.gate_level` into `RHDL::Sim.gate_level`.
3. Remove `RHDL::Codegen.gate_level`.

Refactor:
1. Keep internals delegating to `RHDL::Codegen::Netlist::Lower` + `RHDL::Sim::Native::Netlist::Simulator`.

Exit criteria:
1. No runtime entrypoint remains under `RHDL::Codegen`.
2. Sim facade tests pass.

### Phase 2: Hard Namespace Cutover (Red/Green)
Red:
1. Add failing grep/hygiene checks for forbidden legacy symbols in active code/docs/specs.

Green:
1. Replace all `RHDL::Export::Structure::*` with `RHDL::Codegen::Netlist::*`.
2. Replace all `RHDL::Export::IR::*` with `RHDL::Codegen::CIRCT::IR::*`.
3. Replace all `RHDL::Export.gate_level` callsites with `RHDL::Sim.gate_level`.
4. Remove alias constants and shims:
   - `RHDL::Export`
   - `RHDL::Codegen::Structure`
   - `RHDL::Codegen::Behavior`
   - `lib/rhdl/export.rb`

Refactor:
1. Update stale comments in native crates referencing `Codegen::Structure`.

Exit criteria:
1. Zero legacy namespace usages outside historical PRD files.

### Phase 3: CLI/Task Organization and Runtime Path Fixes (Red/Green)
Red:
1. Add/adjust CLI task specs for gate diagram single-component path and gates task imports.
2. Add AO486 task loading/spec checks under shared task path.

Green:
1. Fix diagram gate-level single-component path (`RHDL::Gates::Lower` -> `RHDL::Codegen::Netlist::Lower`).
2. Update `diagram_task` and `gates_task` to stop requiring `rhdl/export` and use canonical namespaces.
3. Move AO486 task implementation to `lib/rhdl/cli/tasks/ao486_task.rb`.
4. Update `Rakefile` and AO486 task specs to new shared task path.
5. Remove old AO486 task file under `examples/ao486/utilities/tasks`.

Refactor:
1. Keep AO486 importer/runner logic in `examples/ao486/utilities/*` (example-specific code).

Exit criteria:
1. CLI task specs pass and command smoke checks succeed.
2. Shared tasks reside under `lib/rhdl/cli/tasks`.

### Phase 4: Docs + Hygiene Guardrail Sync (Red/Green)
Red:
1. Add failing hygiene/doc checks for stale references (`rake hdl:*`, `codegen/structure`, legacy backends/symbols).

Green:
1. Update `README.md`, `docs/export.md`, `docs/gate_level_backend.md`, `docs/diagrams.md`, and any touched docs to canonical APIs/paths.
2. Extend hygiene task checks for forbidden legacy patterns.
3. Standardize native crate ignore policy where touched by this migration.

Refactor:
1. Keep docs aligned with existing CLI surface from `exe/rhdl` and rake surface from `Rakefile`.

Exit criteria:
1. Docs contain no stale namespace/task references.
2. `bundle exec rake hygiene:check` passes with new guardrails.

### Phase 5: Full Validation and Completion
Red:
1. Run focused specs and command smokes to catch residual migration breakage.

Green:
1. Run full spec suite with slow tests enabled.
2. Confirm migration grep checks and hygiene checks pass.
3. Mark PRD Completed with date and checked checklist.

Refactor:
1. Record any non-runnable gates explicitly.

Exit criteria:
1. Full suite (including slow tests) passes or explicit failures are documented with root cause.

## Acceptance Criteria
1. `RHDL::Sim.gate_level` exists and is canonical runtime entrypoint.
2. `RHDL::Codegen.gate_level` is removed.
3. No active code/spec/docs use `RHDL::Export::*` or `RHDL::Codegen::Structure::*`.
4. `lib/rhdl/export.rb` is removed.
5. CLI gate diagram and gates task paths are fixed to canonical namespaces.
6. AO486 task is loaded from `lib/rhdl/cli/tasks/ao486_task.rb`.
7. Documentation references match current paths/APIs.
8. `bundle exec rake hygiene:check` passes.
9. Full specs pass with slow tests enabled.

## Risks and Mitigations
1. Risk: Large namespace replacement causes hidden runtime constant errors.
   Mitigation: Use focused gates before full suite; add grep/hygiene guardrails.
2. Risk: AO486 task move breaks rake/spec loading.
   Mitigation: Move task with direct require-path updates and AO486 task spec/rake smoke.
3. Risk: Existing dirty worktree creates unrelated churn.
   Mitigation: Restrict edits to owned files and do not revert unrelated changes.
4. Risk: Full slow suite runtime is long and may surface pre-existing failures.
   Mitigation: Capture exact failing files/examples and classify as migration vs pre-existing.

## Implementation Checklist
- [ ] Phase 1: Add `RHDL::Sim.gate_level` and remove `RHDL::Codegen.gate_level`.
- [ ] Phase 2: Hard-cut legacy namespaces and remove `lib/rhdl/export.rb`.
- [ ] Phase 3: Fix CLI gate paths and relocate AO486 shared task.
- [ ] Phase 4: Sync docs and hygiene guardrails.
- [ ] Phase 5: Run full slow+full test validation and mark PRD completed.
