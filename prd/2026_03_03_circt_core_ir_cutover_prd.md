## Status
Completed (2026-03-03)

## Context
RHDL currently lowers DSL constructs into a custom Ruby IR and then fans out to Verilog/FIRRTL/simulation flows. This PRD tracks the cutover to CIRCT IR as the canonical representation for the DSL codegen path, with `to_ir` returning CIRCT MLIR text and a raise flow from CIRCT MLIR back to RHDL DSL.

Verilog import/export conversion is explicitly delegated to external LLVM/CIRCT tooling. RHDL owns only:
- RHDL DSL -> CIRCT nodes -> CIRCT MLIR
- CIRCT MLIR -> CIRCT nodes -> RHDL DSL

## Goals
1. Make `Component#to_ir` return CIRCT MLIR text.
2. Add an explicit in-memory CIRCT node model in Ruby.
3. Add a CIRCT MLIR import API and DSL raise API.
4. Add CLI import workflow for `verilog -> circt mlir -> rhdl dsl` (via external tool shell-out).
5. Preserve migration runway with `to_legacy_ir` for non-migrated internal consumers.

## Non-Goals
1. Implementing native Verilog parsing in Ruby.
2. Implementing native Verilog emission from CIRCT in Ruby.
3. Full-fidelity raise for all CIRCT dialect ops in v1.
4. Rewriting Rust simulator backends in this change.

## Phased Plan (Red/Green)
### Phase 1: CIRCT core model + MLIR generation
- Red: add failing tests for `to_ir` string contract and CIRCT node generation.
- Green: implement CIRCT node classes, legacy-to-CIRCT lowering, and MLIR printer.
- Exit criteria: representative components emit non-empty CIRCT MLIR with `hw.module`.

### Phase 2: DSL contract cutover + compatibility bridge
- Red: fail old assumptions that `to_ir` returns custom IR object.
- Green: add `to_legacy_ir`, make `to_ir` emit MLIR, and keep internal legacy paths explicit.
- Exit criteria: core library paths that still require legacy IR call `to_legacy_ir`.

### Phase 3: CIRCT import/raise and CLI integration
- Red: add failing tests for MLIR import and DSL raising outputs.
- Green: add parser subset, raise generator, diagnostics, and `rhdl import` command.
- Exit criteria: verilog import command shells to external tool, then raises MLIR to Ruby DSL files.

## Exit Criteria Per Phase
- Phase 1: `RHDL::Codegen::CIRCT::{IR,Lower,MLIR}` exists and is wired.
- Phase 2: `to_ir` returns `String` and `to_legacy_ir` exists for migrated internals.
- Phase 3: `RHDL::Codegen::CIRCT::{Import,Raise}` + CLI task are functional for v1 subset.

## Acceptance Criteria
1. `to_ir` returns CIRCT MLIR string for DSL components.
2. `to_circt_nodes` and `to_legacy_ir` are available.
3. `RHDL::Codegen::CIRCT::Import.from_mlir` returns modules + diagnostics.
4. `RHDL::Codegen::CIRCT::Raise.to_dsl` writes Ruby source files and reports diagnostics.
5. `rhdl import --mode verilog` invokes external LLVM/CIRCT tooling and can raise to DSL.
6. `rhdl import --mode circt` raises MLIR directly to DSL.

## Risks And Mitigations
- Risk: broad breakage from `to_ir` contract change.
  - Mitigation: explicit `to_legacy_ir` shim and focused internal call-site migration.
- Risk: partial MLIR parser coverage.
  - Mitigation: diagnostics + partial output policy in raise flow.
- Risk: external tooling differences (`circt-translate` availability/flags).
  - Mitigation: configurable `--tool` and passthrough `--tool-arg` CLI options.

## Implementation Checklist
- [x] Phase 1: Add CIRCT node classes (`IR`) and legacy-lowering bridge.
- [x] Phase 1: Add CIRCT MLIR printer for `hw/comb/seq` subset.
- [x] Phase 2: Add `to_legacy_ir`, `to_circt_nodes`, and `to_ir` MLIR contract.
- [x] Phase 2: Update key internal legacy-IR consumers to call `to_legacy_ir`.
- [x] Phase 3: Add CIRCT MLIR import result + diagnostics surface.
- [x] Phase 3: Add CIRCT raise-to-DSL writer with partial output behavior.
- [x] Phase 3: Add CLI import task and `rhdl import` command wiring.
- [x] Add/expand regression tests for parser/printer/CLI import flow.
- [x] Update user docs (`README.md`, `docs/`) for new IR and import contracts.
