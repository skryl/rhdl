# RISC-V RV32F/RV32D Completion to ILP32D PRD

## Status
In Progress (2026-02-27)

Progress update (2026-02-27):
- Phase 3 DP arithmetic/conversion scope is now implemented and green in directed unit/integration gates (`assembler_fp_encoding_spec`, `fp_register_file_spec`, `rv32f_extension_spec`), including `fmadd.d`, `fmsub.d`, `fnmsub.d`, and `fnmadd.d` coverage on both single-cycle and pipelined cores.

## Context
The current RISC-V core and software stack are configured toward an ILP32D userspace target in Buildroot, but hardware ISA support is not yet aligned:
- `RV32F` is only a minimal subset (data movement + basic CSR interactions).
- `RV32D` is not implemented.
- Buildroot/toolchain assumptions (`riscv32-ilp32d`) require substantially broader floating-point coverage.

Result: userspace and runtime behavior can fail due to missing FP/DP instructions and incomplete FP architectural behavior.

## Goals
- Implement `RV32F` to practical ILP32D userspace completeness.
- Implement `RV32D` (architectural state + instruction set needed by toolchains/libc/runtime).
- Keep single-cycle and pipelined cores behaviorally aligned.
- Boot Linux + Buildroot ILP32D userspace to interactive shell with no illegal-instruction regressions from FP usage.
- Keep `misa` extension advertisement accurate for implemented ISA.

## Non-goals
- RV64 support.
- Full RVV or additional optional FP extensions (`Zfa`, etc.).
- Performance tuning/microarchitectural optimization beyond correctness and basic throughput parity.
- Broad ISA expansion unrelated to ILP32D enablement.

## Phased Plan (Red/Green)

### Phase 0: Baseline, observability, and failure locking
Red:
- Add failing targeted specs for missing `RV32F`/`RV32D` instruction classes and FP state semantics.
- Add integration checks that currently fail under ILP32D userspace startup (illegal instruction / trap signatures).

Green:
- Introduce minimal debug visibility needed to root-cause FP traps (`mcause`, `mtval`, faulting PC, decoded opcode class).
- Confirm deterministic repro for each missing area before implementation.

Exit criteria:
- Known failures are reproducible and encoded as tests/checks.
- Failure reports isolate missing instruction/semantics class, not generic boot failure.

### Phase 1: Complete RV32F architectural behavior (single precision)
Red:
- Add failing tests for missing `F` operations and state semantics beyond current subset.

Green:
- Implement missing `RV32F` operations expected by ILP32D toolchains/runtime, including:
  - arithmetic core (`fadd.s`, `fsub.s`, `fmul.s`, `fdiv.s`, `fsqrt.s`)
  - sign/min/max/compare/class ops used in generated code paths
  - conversion ops between integer/single where required
  - correct `fcsr`/`fflags`/`frm` behavior for implemented ops
- Ensure trap behavior is spec-conformant for unsupported/illegal forms.

Exit criteria:
- `RV32F` instruction/CSR suite passes for single-cycle and pipeline.
- No regressions in existing integer/privileged/MMU suites.

### Phase 2: RV32D architectural state + data movement foundation
Red:
- Add failing tests for `D` architectural invariants (FLEN=64 behavior, NaN-boxing interactions with `S` values, load/store).

Green:
- Extend FP register/state model to support `RV32D` correctly.
- Implement `fld`/`fsd`.
- Implement `fcvt.s.d` and `fcvt.d.s`.
- Ensure `misa.D` and related architectural reporting match actual support.

Exit criteria:
- All `D` state, boxing, and movement tests pass on both cores.
- Existing `RV32F` tests remain green under widened FP state.

### Phase 3: RV32D arithmetic/conversion completeness for ILP32D
Red:
- Add failing tests for DP arithmetic and conversion paths observed in toolchain/libc output.

Green:
- Implement core `RV32D` ops required for ILP32D userspace viability:
  - `fadd.d`, `fsub.d`, `fmul.d`, `fdiv.d`, `fsqrt.d`
  - `fsgnj*.d`, `fmin.d`, `fmax.d`
  - `feq.d`, `flt.d`, `fle.d`, `fclass.d`
  - `fcvt.d.w`, `fcvt.d.wu`, `fcvt.w.d`, `fcvt.wu.d`
  - fused ops (`fmadd.d`, `fmsub.d`, `fnmsub.d`, `fnmadd.d`) if emitted by target toolchain paths
- Validate rounding-mode and exception-flag behavior for implemented instructions.

Exit criteria:
- DP instruction suite passes in both cores and available backends.
- Differential parity (single-cycle vs pipeline) passes for added DP flows.

### Phase 4: Toolchain/kernel/buildroot alignment and end-to-end bring-up
Red:
- Add failing end-to-end checks for ILP32D userspace boot milestones.

Green:
- Align software configs and defaults with implemented ISA:
  - kernel DT `riscv,isa`
  - kernel config assumptions vs implemented FP/DP
  - Buildroot/toolchain ILP32D profile assumptions
- Rebuild artifacts and verify boot progression to shell.

Exit criteria:
- Default Linux build path reaches shell with ILP32D rootfs.
- No recurring FP illegal-instruction traps during init/userspace startup.

### Phase 5: Stabilization and regression hardening
Red:
- Add long-running and mixed-workload regressions to expose intermittent FP/CSR/context issues.

Green:
- Fix discovered edge cases.
- Lock in regression suites and document supported ISA/known limits.

Exit criteria:
- Regression suites for F/D + privileged/MMU + Linux boot remain stable.
- Documentation reflects current implemented ISA and guarantees.

## Test Strategy (by gate)
1. Unit/op-level:
- Instruction-by-instruction F/D semantics, rounding, flags, NaN-boxing, CSR behavior.
2. Integration:
- Single-cycle vs pipeline differential checks for new instruction families.
- MMU/privilege + FP interaction checks.
3. End-to-end:
- Linux boot milestones through userspace init and shell availability on default flow.
4. Workflow checks:
- Existing RISC-V task/spec commands for touched areas.

If any gate cannot run locally, record exact skipped command and reason.

## Acceptance Criteria (full completion)
- `RV32F` and `RV32D` instruction support required by ILP32D userspace is implemented and tested.
- `misa` and advertised ISA strings match real implementation.
- Single-cycle and pipeline cores match on architectural state for new FP/DP coverage.
- Default Linux + Buildroot ILP32D flow boots to interactive shell without FP illegal traps.
- Documentation/config defaults reflect final supported ISA behavior.

## Risks and Mitigations
- Risk: NaN-boxing/FLEN transition bugs create silent data corruption.
  - Mitigation: explicit boxing invariants and cross-core differential tests.
- Risk: `fcsr` rounding/flags drift from spec.
  - Mitigation: directed tests per op and rounding mode; compare against software reference model.
- Risk: toolchain emits less-common DP ops unexpectedly.
  - Mitigation: trap telemetry + opcode histogram from failing binaries; add ops incrementally with tests.
- Risk: pipeline-specific hazards for FP state updates.
  - Mitigation: mandatory parity tests and hazard-focused directed cases.
- Risk: config/ISA mismatch between kernel DT, kernel config, and userspace toolchain.
  - Mitigation: single source-of-truth checklist in build flow and CI guard checks.

## Implementation Checklist
- [ ] Phase 0: Baseline failures and observability in place.
- [ ] Phase 1: RV32F completion implemented and green.
- [ ] Phase 2: RV32D state + data movement implemented and green.
- [x] Phase 3: RV32D arithmetic/conversion completeness implemented and green.
- [ ] Phase 4: End-to-end ILP32D Linux/userspace boot green.
- [ ] Phase 5: Stabilization suite green; docs/configs updated.
