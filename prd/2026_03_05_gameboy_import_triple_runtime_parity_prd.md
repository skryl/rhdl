## Status
In Progress (2026-03-05)

## Context
Game Boy mixed import coverage currently validates:
1. mixed import path correctness,
2. semantic roundtrip signature stability,
3. imported-design behavioral checks on `ir_compiler`.

It does not yet provide one integration gate that compares runtime instruction progression across all target stages in the import chain:
1. `Mixed Verilog/VHDL -> GHDL -> staged pure Verilog` consumed by Verilator,
2. `... -> CIRCT MLIR` consumed by Arcilator,
3. `... -> raised RHDL` consumed by IR compiler.

## Goals
1. Add a deterministic runtime parity spec for Game Boy import under `spec/examples/gameboy/import`.
2. Compare PC/opcode progression between Verilator (staged pure Verilog) and IR compiler (raised RHDL).
3. Add Arcilator consumption of the CIRCT step and enforce 3-way parity when the CIRCT artifact is Arcilator-legal.
4. Ensure Arcilator consumes only the pure-Verilog-derived CIRCT lowering path (`staged Verilog -> CIRCT -> ARC`), with no fallback to RHDL-generated CIRCT.
5. Keep failure diagnostics actionable (which stage failed, command excerpt, first mismatching events).

## Non-Goals
1. Reworking the core import strategy selection (`mixed` vs `compat`).
2. Fixing all upstream CIRCT/Arcilator legality issues in this PRD if discovered.
3. Replacing existing Game Boy behavioral specs.

## Phased Plan (Red/Green)

### Phase 1: Red - 3-Way Runtime Parity Spec Scaffold
Red:
1. Add a new slow spec file for runtime parity with explicit toolchain gating.
2. Add failing expectations for Verilator-vs-IR progression parity and 3-way parity shape.

Green:
1. Wire importer invocation and deterministic ROM fixture generation.
2. Wire common trace normalization + comparison helpers.

Exit Criteria:
1. Spec scaffold runs and exercises importer + runtime harness setup path.

### Phase 2: Green - Verilator(Pure Verilog) vs IR Compiler(Raised RHDL)
Red:
1. Demonstrate pure staged Verilog cannot be consumed directly by Verilator due unsupported array-select LHS constructs.

Green:
1. Add deterministic post-staging runtime rewrite pass in GameBoy importer (`.mixed_import/runtime_sources` + `.mixed_import/mixed_runtime.v`) so both Verilator and Arcilator consume the same rewritten pure-Verilog artifact.
2. Add Verilator trace harness (PC/opcode progression via fetch-level/internal signals).
3. Add IR compiler trace harness using imported raised RHDL.
4. Assert strict parity between Verilator and IR traces.

Exit Criteria:
1. Verilator-vs-IR progression parity assertion is green.

### Phase 3: Green - Arcilator(CIRCT) Integration
Red:
1. Attempt direct Arcilator consumption of imported CIRCT MLIR and capture legalization failures.
2. Enforce pure-Verilog-only CIRCT source for Arcilator (remove re-emitted-RHDL fallback).

Green:
1. Add Arcilator compile-and-run harness path using pure-Verilog-derived CIRCT/ARC artifact only.
2. When Arcilator compile succeeds, assert strict parity against Verilator/IR traces.
3. When Arcilator compile fails due known CIRCT legality issues, convert to explicit pending with failure reason and command excerpt.

Exit Criteria:
1. Spec enforces 3-way parity when feasible and provides deterministic pending diagnostics otherwise.

### Phase 4: Regression and Workflow
Red:
1. Ensure spec is included in the slow Game Boy import suite.

Green:
1. Run targeted spec file.
2. Run broader `spec/examples/gameboy/import` suite with `INCLUDE_SLOW_TESTS=1`.

Exit Criteria:
1. New test path is stable and documented through spec naming/location.

## Acceptance Criteria
1. New runtime parity spec exists under `spec/examples/gameboy/import`.
2. Verilator consumes staged pure Verilog artifact (not raised RHDL Verilog export).
3. IR compiler consumes raised RHDL artifact.
4. Arcilator path is attempted on pure-Verilog-lowered CIRCT/ARC artifact and participates in parity when legal.
5. Failures/pending states include actionable stage-specific diagnostics.

## Risks and Mitigations
1. Risk: staged Verilog remains partially incompatible with Verilator.
   - Mitigation: apply deterministic importer-owned runtime rewrites and publish `mixed_import.runtime_entry_path` for all runtime consumers.
2. Risk: pure-Verilog CIRCT lowering may remain non-Arcilator-legal (`llhd.constant_time` conversion failures).
   - Mitigation: keep explicit pending gate with concrete ARC-lowering/compiler error excerpt; preserve strict parity assertion when compile succeeds.
3. Risk: runtime traces differ due reset/boot alignment.
   - Mitigation: normalize leading reset-only events and compare bounded deterministic windows.

## Implementation Checklist
- [x] Phase 1 scaffold added and wired.
- [x] Phase 2 Verilator normalization + trace harness implemented.
- [x] Phase 2 IR trace harness implemented.
- [x] Phase 2 Verilator-vs-IR parity assertion green.
- [x] Phase 3 Arcilator trace path implemented.
- [ ] Phase 3 3-way parity enforced when Arcilator compile succeeds.
- [x] Phase 3 explicit pending diagnostics for Arcilator compile failures.
- [ ] Phase 4 targeted and import-suite validation run.
