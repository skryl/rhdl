# RISC-V Vector Extension (RVV) for Basic + Pipelined Cores PRD

## Status

Proposed (2026-02-20)

## Context

Current RISC-V core flows are integer-focused and Linux minimum profile defaults disable vector support.
RVV support is a major architectural milestone with wide changes across decode, register state, execution, memory semantics, and pipeline control.
Both core implementations are in scope:

- Single-cycle core path (`examples/riscv/hdl/cpu.rb`) with a practical multi-cycle vector execution strategy
- Pipelined core path (`examples/riscv/hdl/pipeline/pipelined_cpu.rb`, `examples/riscv/hdl/pipeline/pipelined_datapath.rb`)

Given complexity, this PRD targets a phased RVV subset with explicit capability boundaries before expanding toward broader coverage.

## Goals

1. Implement a clearly defined RVV baseline subset for both core implementations.
2. Add vector architectural state (`vtype`, `vl`, vector registers, related CSRs) with correct control semantics.
3. Ensure deterministic behavior for mixed scalar/vector programs.
4. Build strong red/green coverage for vector arithmetic, masking, and memory behavior.

## Non-Goals

1. Full RVV instruction-space coverage in a single milestone.
2. Performance-first vector microarchitecture tuning.
3. Multi-hart vector coherence work.
4. GPU-like acceleration features beyond standard RVV scope.

## Phased Plan (Red/Green)

### Phase 0 - RVV Scope Lock and ISA Contract

- Red: add failing tests for illegal-vector-op behavior when `V` is disabled.
- Red: add failing tests for enablement, `misa`/feature exposure, and unsupported-instruction error paths.
- Green: define baseline RVV subset and implementation parameters (`VLEN`, `ELEN`, supported instruction classes).
- Green: add feature gating and capability reporting in both core paths.

Exit Criteria:

- RVV baseline scope is documented and testable.
- Feature gating tests pass.

### Phase 1 - Vector Architectural State and Control

- Red: add failing tests for vector CSR state (`vl`, `vtype`, `vstart` as scoped), vector register reset/read/write behavior, and `vset*` instructions.
- Green: implement vector architectural state and CSR/control instruction handling.
- Green: ensure state transitions for `vsetvl`-style operations are deterministic and spec-aligned for scoped subset.

Exit Criteria:

- Vector state/control tests pass for both cores or shared core-parity harness.

### Phase 2 - Baseline Vector ALU and Mask Semantics

- Red: add failing tests for selected vector arithmetic/logical operations, mask enable/disable behavior, and tail policy handling for scoped subset.
- Green: implement baseline vector ALU instruction execution and mask/tail semantics.
- Green: add parity checks between single-cycle and pipelined outcomes for identical workloads.

Exit Criteria:

- Baseline vector ALU and mask tests pass.
- Core parity checks are green for scoped instruction set.

### Phase 3 - Vector Memory Operations

- Red: add failing tests for vector loads/stores, alignment constraints, stride/indexed mode support as scoped, and fault behavior.
- Green: implement vector memory operations for scoped addressing modes.
- Green: validate interaction with existing MMIO/memory model and fault paths.

Exit Criteria:

- Vector memory operation tests pass.
- No regressions in scalar memory behavior.

### Phase 4 - Pipeline Control, Hazards, and Progress Model

- Red: add failing tests for pipeline hazards between scalar and vector instructions, vector operation progress/drain behavior, and trap recovery.
- Green: integrate vector execution control into hazard/forwarding/stall/flush logic.
- Green: define deterministic long-op progress model and enforce it in both simulation and tests.

Exit Criteria:

- Pipeline vector hazard/progress tests pass.
- Mixed scalar/vector programs execute deterministically.

### Phase 5 - End-to-End Integration and Documentation

- Red: add failing end-to-end tests using RVV-enabled binaries for both cores.
- Green: wire CLI/harness configuration for vector-capable runs.
- Green: document supported RVV subset, unsupported operations, and extension roadmap.

Exit Criteria:

- End-to-end RVV tests are green for scoped subset.
- Documentation and help text match implemented scope.

## Acceptance Criteria

1. Scoped RVV baseline executes correctly on both basic and pipelined cores.
2. Vector state/control (`vl`, `vtype`, vector register state) is deterministic and tested.
3. Mixed scalar/vector programs behave consistently with defined hazard/progress rules.
4. Feature gating for `V` is explicit and stable.
5. Docs clearly define supported subset and limitations.

## Risks and Mitigations

1. Risk: RVV scope expands uncontrollably and delays delivery.
Mitigation: lock baseline subset in Phase 0 and reject out-of-scope additions until post-milestone.

2. Risk: vector memory semantics produce subtle bugs.
Mitigation: add focused failing tests per addressing mode and fault class before implementation.

3. Risk: pipeline control complexity causes regressions in scalar path.
Mitigation: add scalar regression gates and core parity tests after each vector phase.

4. Risk: mismatch between single-cycle and pipelined semantics.
Mitigation: maintain shared semantic fixtures and differential tests across cores.

## Implementation Checklist

- [ ] Phase 0: RVV subset definition and feature gate.
- [ ] Phase 1: Vector architectural state and control instructions.
- [ ] Phase 2: Baseline vector ALU and mask/tail semantics.
- [ ] Phase 3: Vector memory operations for scoped addressing modes.
- [ ] Phase 4: Pipeline hazard/progress integration for vector ops.
- [ ] Phase 5: End-to-end coverage and documentation updates.

