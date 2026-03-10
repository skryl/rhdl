## Status
In Progress (2026-03-05)
Runtime update - Verilator vs imported IR JIT parity gate is green. Imported runtime initialization now uses CIRCT-native flattening + runtime JSON normalization instead of a raised-DSL round trip. The local Arcilator harness also now uses an `llc` invocation compatible with the installed toolchain. (2026-03-05)
Validation update - targeted GameBoy runtime specs are green; full `spec/examples/gameboy/import` validation was started but not allowed to finish in this pass because a long roundtrip spec was still running without an early failure signal. (2026-03-05)
Runtime export update - the canonical imported runtime Verilog now preserves raw `firtool` output as a separate artifact and overlays only the generated VHDL memory modules needed to keep Verilator healthy on the imported GameBoy design; fresh direct import verification shows the canonical `gb.normalized.v` now passes `verilator --lint-only`, `verilator --cc`, and a short POP-ROM execution harness again. (2026-03-06)
Runtime cache update - mixed import now emits a cached `gb.runtime.json` artifact and the imported GameBoy `IrRunner` can consume it directly, cutting imported JIT startup materially versus reparsing the full cleaned CIRCT MLIR on each run while preserving the preexisting manual cycle semantics. (2026-03-06)
Runtime parity update - the 3-way spec now executes backends in `Verilator -> Arcilator -> IR compiler` order, and the Arcilator leg now consumes the imported `gb.core.mlir` artifact directly via `prepare_arc_mlir_from_circt_mlir(...)` instead of a second pure-Verilog ARC lowering path. Direct probes confirm Verilator completes, imported ARC preparation succeeds, and Arcilator is currently blocked later by loop-splitting failures in the imported ARC MLIR (`gb_savestates`, `sprites_extra`) before the IR compiler phase starts. (2026-03-09)
Shared-stub parity update - the 3-way spec now drives the importer with the same shared `stub_modules` set for all three backends (`gb_savestates`, `gb_statemanager__vhdl_2e2d161b9c1b`, `sprites_extra`), so Verilator consumes importer-emitted stubbed normalized Verilog and both Arcilator / IR compiler consume the same stubbed imported `gb.core.mlir`. Fresh direct probes on March 9, 2026 show imported `gb.core.mlir -> hwseq -> ARC` now succeeds and `arcilator` compiles the resulting `gb.arc.mlir`; the remaining full-spec bottleneck moved to the Arcilator LLVM runtime harness rather than ARC legality. (2026-03-09)
Validation strategy update - the default Game Boy import correctness gate is now the Verilator-only behavioral parity spec (`spec/examples/gameboy/import/behavioral_ir_compiler_spec.rb`), which compares staged source Verilog, normalized imported Verilog, and Verilog regenerated from raised RHDL and is green locally. This 3-way Verilator/Arcilator/IR parity spec is now opt-in via `RHDL_ENABLE_NON_VERILATOR_GAMEBOY_PARITY=1` because the non-Verilator backends remain too expensive for routine local suite runs. (2026-03-09)

## Context
Game Boy mixed import coverage currently validates:
1. mixed import path correctness,
2. semantic roundtrip signature stability,
3. default behavioral parity between staged source Verilog and normalized imported Verilog on Verilator.

It does not yet provide one integration gate that compares runtime instruction progression across all target stages in the import chain:
1. `Mixed Verilog/VHDL -> GHDL -> staged pure Verilog` consumed by Verilator,
2. `... -> imported CIRCT MLIR -> ARC MLIR` consumed by Arcilator,
3. `... -> imported CIRCT runtime path` consumed by the IR backend. The current runtime backend is `:compiler`.

## Goals
1. Add a deterministic runtime parity spec for Game Boy import under `spec/examples/gameboy/import`.
2. Compare PC/opcode progression between Verilator (staged pure Verilog) and the IR runtime leg. The current backend is `:compiler`.
3. Add Arcilator consumption of the CIRCT step and enforce 3-way parity when the CIRCT artifact is Arcilator-legal.
4. Keep Arcilator on the imported CIRCT artifact path (`imported gb.core.mlir -> hwseq -> ARC`) so it is comparing the same imported design leg as the IR compiler backend.
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
3. Add IR runtime trace harness for the imported design. The current backend is `:compiler`.
4. Assert strict parity between Verilator and IR traces.

Exit Criteria:
1. Verilator-vs-IR progression parity assertion is green.

### Phase 3: Green - Arcilator(CIRCT) Integration
Red:
1. Attempt direct Arcilator consumption of imported CIRCT MLIR and capture legalization failures.
2. Enforce imported-CIRCT source for Arcilator (remove alternate pure-Verilog ARC-lowering path in the parity gate).

Green:
1. Add Arcilator compile-and-run harness path using the imported `gb.core.mlir -> hwseq -> ARC` artifact only.
2. When Arcilator compile succeeds, assert strict parity against Verilator/IR traces.
3. When Arcilator compile fails due known ARC legality issues, surface explicit diagnostics with failure reason and command excerpt.

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
3. IR runtime consumes the imported design runtime path. The current backend is `:compiler`.
4. Arcilator path is attempted on imported-CIRCT-lowered ARC artifact and participates in parity when legal.
5. Failures/pending states include actionable stage-specific diagnostics.

## Risks and Mitigations
1. Risk: staged Verilog remains partially incompatible with Verilator.
   - Mitigation: apply deterministic importer-owned runtime rewrites and publish `mixed_import.runtime_entry_path` for all runtime consumers.
2. Risk: full unstubbed imported ARC lowering may remain non-Arcilator-legal (`loop splitting did not eliminate all loops` around `gb_savestates` / `sprites_extra`).
   - Mitigation: use importer-level shared stubs for disabled Game Boy subsystems so Verilator / Arcilator / IR compiler all consume the same stubbed imported design during parity runs; keep explicit diagnostics if the stubbed ARC leg still fails.
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
