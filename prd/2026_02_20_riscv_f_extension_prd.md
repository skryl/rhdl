# RISC-V F Extension (RV32F) for Basic + Pipelined Cores PRD

## Status

Proposed (2026-02-20)

## Context

Current Linux and core flows in this repo default to integer-focused ISA profiles, and the Linux builder explicitly disables `FPU` in its minimum profile.
Implementing RV32F introduces substantial architectural state and control behavior that must remain consistent across both core implementations:

- Single-cycle core path (`examples/riscv/hdl/cpu.rb`)
- Pipelined core path (`examples/riscv/hdl/pipeline/pipelined_cpu.rb`, `examples/riscv/hdl/pipeline/pipelined_datapath.rb`)

RV32F support is primarily a compatibility and capability milestone, enabling toolchains and workloads that emit scalar floating-point instructions.

## Goals

1. Implement architecturally correct RV32F instruction support in both cores.
2. Implement floating-point architectural state (`f` register file and `fcsr` behavior) with correct privilege/CSR interaction.
3. Preserve deterministic behavior when `F` is disabled.
4. Add red/green tests for arithmetic correctness, rounding modes, and exception flags.

## Non-Goals

1. `D`, `Q`, and vector floating-point support.
2. High-performance pipelined FPU optimization.
3. Out-of-order or speculative FP execution work.
4. ABI or distro packaging work beyond repo-local build/test flows.

## Phased Plan (Red/Green)

### Phase 0 - RV32F Contract and Enablement

- Red: add failing tests asserting illegal-instruction behavior for `F` opcodes when `F` is disabled.
- Red: add failing tests for feature toggle visibility and CSR access behavior.
- Green: add explicit `F` feature flag plumbing through single-cycle and pipelined harness/runner paths.
- Green: define and document supported RV32F instruction subset for first milestone.

Exit Criteria:

- `F` enable/disable behavior is deterministic.
- Contract tests for illegal/allowed opcode behavior pass.

### Phase 1 - Floating-Point Architectural State

- Red: add failing tests for `f0..f31` register read/write semantics and `fcsr` (`fflags`, `frm`) behavior.
- Green: implement FP register file state and CSR mapping.
- Green: implement context/reset semantics and integration with existing trap/CSR infrastructure.

Exit Criteria:

- FP state tests pass in both core paths (or shared harness path with core parity checks).
- `fcsr` reads/writes and reset behavior are correct.

### Phase 2 - Single-Cycle RV32F Execution

- Red: add failing tests for core RV32F ops (`fadd.s`, `fsub.s`, `fmul.s`, `fdiv.s`, `fsqrt.s`, converts, compares, moves) and memory ops (`flw`, `fsw`).
- Red: add failing rounding-mode and exception-flag tests.
- Green: implement single-cycle RV32F execution path and memory operation handling.
- Green: wire exception flags and rounding mode behavior to architectural state.

Exit Criteria:

- Single-cycle RV32F functional tests pass.
- Rounding/flag behavior is validated against expected results for targeted cases.

### Phase 3 - Pipelined RV32F Integration

- Red: add failing pipeline tests for FP data hazards, forwarding, stalling, and WB ordering.
- Red: add failing tests for mixed integer/FP dependency chains.
- Green: integrate FP execution into pipeline control and writeback.
- Green: update hazard and forwarding logic to handle FP register dependencies and operation latency model.

Exit Criteria:

- Pipeline RV32F hazard/forwarding tests pass.
- Mixed integer/FP workloads are deterministic and correct.

### Phase 4 - Trap/Exception Semantics and Regression Hardening

- Red: add failing tests for illegal combinations, CSR edge cases, and exception-flag accumulation/clearing.
- Green: finalize trap and exception semantics for RV32F operations and CSR interactions.
- Green: add regression tests covering edge numeric values and denormal/NaN handling policy used by implementation.

Exit Criteria:

- Exception/CSR edge-case tests pass.
- Regression set captures known fragile points and is stable.

### Phase 5 - Integration and Documentation

- Red: add failing end-to-end specs running `F`-compiled binaries in both cores.
- Green: wire CLI/harness options for `F` mode selection.
- Green: document supported RV32F scope, known limitations, and test commands.

Exit Criteria:

- End-to-end `F` binary runs are green on both cores.
- Docs and help text match behavior.

## Acceptance Criteria

1. RV32F instructions execute correctly on both basic and pipelined cores.
2. `f` register file and `fcsr` behavior are architecturally consistent.
3. Rounding modes and FP exception flags behave as specified for supported instruction set.
4. `F` gating is deterministic and regression tested.
5. Existing non-`F` flows remain stable.

## Risks and Mitigations

1. Risk: FP semantics mismatch (rounding/flags) causes subtle correctness issues.
Mitigation: add oracle-based numeric tests and explicit flag assertions early.

2. Risk: pipeline latency assumptions create nondeterministic hazards.
Mitigation: define explicit latency model and test mixed dependency sequences before optimization.

3. Risk: CSR/trap integration regresses privileged behavior.
Mitigation: isolate FP CSR coverage and rerun targeted privileged compatibility tests.

4. Risk: scope creep into `D`/advanced FP features.
Mitigation: lock phase scope to RV32F milestone and defer `D`/`Q`/vector FP work.

## Implementation Checklist

- [ ] Phase 0: RV32F contract and feature gating.
- [ ] Phase 1: FP architectural state (`f` regs + `fcsr`) implementation.
- [ ] Phase 2: Single-cycle RV32F execute + memory operations.
- [ ] Phase 3: Pipelined RV32F hazard/control integration.
- [ ] Phase 4: Trap/exception semantics and regression hardening.
- [ ] Phase 5: End-to-end coverage and docs updates.

