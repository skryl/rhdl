# 2026_03_04_sim_native_namespace_migration_prd

## Status
Completed (2026-03-04)

## Context
Simulator backends currently live under `lib/rhdl/codegen/{ir,netlist}/sim`, even though they are runtime simulation concerns, not code generation transforms.
This also leaks into Ruby namespacing (`RHDL::Codegen::IR::*` / `RHDL::Codegen::Netlist::*`) for simulator APIs.

Requested change:
1. Move IR simulator backend tree from `codegen/ir/sim` to `sim/native/ir`.
2. Move netlist simulator backend tree from `codegen/netlist/sim` to `sim/native/netlist`.
3. Fix namespacing and all callsites, with no backwards-compatibility stubs.

## Goals
1. Relocate simulator Ruby and Rust backend files to `lib/rhdl/sim/native/{ir,netlist}`.
2. Re-namespace simulator APIs under `RHDL::Sim::Native::{IR,Netlist}`.
3. Update all Ruby callsites/requires/constants to the new namespace.
4. Keep native build/check tasks and web benchmark/web-generate flows working with new paths.
5. Update docs that mention simulator paths/namespaces.

## Non-goals
1. Changing simulator behavior/performance semantics.
2. Introducing new simulator features.
3. Preserving old namespace compatibility aliases.

## Phased Plan

### Phase 1: Path + Namespace Cutover (Red/Green)
Red:
1. Capture baseline references that still point at `codegen/*/sim` or `RHDL::Codegen::{IR,Netlist}` simulator namespaces.
2. Identify failing require paths/constants after file moves.

Green:
1. Move simulator files/crates into `lib/rhdl/sim/native/{ir,netlist}`.
2. Update Ruby module declarations and class/constant names to `RHDL::Sim::Native::{IR,Netlist}`.
3. Update `lib/rhdl/codegen.rb`, CLI task paths, examples, and specs to new requires/constants/classes.

Refactor:
1. Remove leftover compatibility aliases in moved simulator modules.
2. Normalize naming to avoid redundant legacy class aliases.

Exit criteria:
1. `rg` finds no runtime references to `codegen/ir/sim` or `codegen/netlist/sim` in Ruby code/docs except historical PRD notes.
2. No simulator callsites use `RHDL::Codegen::IR::*` or `RHDL::Codegen::Netlist::*` simulator constants/classes.

### Phase 2: Validation + Docs Sync (Red/Green)
Red:
1. Run focused specs expected to fail if namespace/path cutover is incomplete.

Green:
1. Make final callsite/doc fixes until focused specs pass.
2. Verify native task path constants resolve under new locations.

Refactor:
1. Tidy any remaining naming inconsistencies in touched files.

Exit criteria:
1. Targeted simulator-related specs pass.
2. Documentation examples point to `RHDL::Sim::Native::*` and new file paths.

## Acceptance Criteria
1. IR simulator Ruby entrypoint is at `lib/rhdl/sim/native/ir/simulator.rb`.
2. Netlist simulator Ruby entrypoint is at `lib/rhdl/sim/native/netlist/simulator.rb`.
3. IR Rust crates are under `lib/rhdl/sim/native/ir/{ir_interpreter,ir_jit,ir_compiler}`.
4. Netlist Rust crates are under `lib/rhdl/sim/native/netlist/{netlist_interpreter,netlist_jit,netlist_compiler}`.
5. All callsites use `RHDL::Sim::Native::{IR,Netlist}` APIs with no compatibility shim constants/classes left behind.
6. Relevant tests pass locally or gaps are explicitly documented.

## Risks and Mitigations
1. Risk: Large replacement set misses dynamic constant checks.
Mitigation: Search for constant strings in CLI/native tasks and update `check_const` values.
2. Risk: Relative require paths break after file moves.
Mitigation: Re-run targeted specs and grep for stale paths.
3. Risk: Existing dirty worktree introduces unrelated noise.
Mitigation: Restrict edits to migration-related files and avoid reverting unrelated changes.

## Implementation Checklist
- [x] Phase 1: Move simulator trees into `lib/rhdl/sim/native/{ir,netlist}`.
- [x] Phase 1: Re-namespace simulator modules/classes/constants.
- [x] Phase 1: Update all Ruby callsites/requires and CLI path constants.
- [x] Phase 2: Update docs and README references.
- [x] Phase 2: Run focused specs and address failures.
- [x] Phase 2: Mark status `Completed` with date after all criteria are met.
